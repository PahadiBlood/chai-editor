import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'clipboard_html.dart';
import 'code_block.dart';
import 'markdown_io.dart';

const enableRichPaste =
    bool.fromEnvironment('CHAI_RICH_PASTE', defaultValue: true);
const _clipboard = MethodChannel('chai/clipboard');

enum PasteMode { automatic, markdown, plainText }

/// Only block syntax triggers automatic Markdown. Inline emphasis stays literal.
bool hasBlockMarkdown(String text) => RegExp(
      r'^ {0,3}(?:#{1,6}(?:\s|$)|[-*+]\s+|\d+[.)]\s+|>\s?|`{3,}|~{3,}|\|[^\n]*\|)',
      multiLine: true,
    ).hasMatch(text.replaceAll('\r\n', '\n'));

final richPasteCommand = CommandShortcutEvent(
  key: pasteCommand.key,
  getDescription: () => pasteCommand.description ?? 'Paste',
  command: 'ctrl+v',
  macOSCommand: 'cmd+v',
  handler: (state) => _startPaste(state, PasteMode.automatic),
);

final pasteAsMarkdownCommand = CommandShortcutEvent(
  key: 'paste as Markdown',
  getDescription: () => 'Paste as Markdown',
  command: 'ctrl+alt+shift+v',
  macOSCommand: 'cmd+alt+shift+v',
  handler: (state) => _startPaste(state, PasteMode.markdown),
);

final chaiPastePlainTextCommand = pasteTextWithoutFormattingCommand.copyWith(
  handler: (state) => _startPaste(state, PasteMode.plainText),
);

KeyEventResult _startPaste(EditorState state, PasteMode mode) {
  if (state.selection == null || !state.editable) return KeyEventResult.ignored;
  unawaited(pasteFromClipboard(state, mode: mode).catchError(
    (Object error, StackTrace stack) => FlutterError.reportError(
      FlutterErrorDetails(
          exception: error, stack: stack, library: 'Chai paste'),
    ),
  ));
  return KeyEventResult.handled;
}

Future<void> pasteFromClipboard(
  EditorState state, {
  PasteMode mode = PasteMode.automatic,
}) async {
  final selection = state.selection;
  if (selection == null || !state.editable || state.isDisposed) return;
  final text = (await AppFlowyClipboard.getData()).text;
  String? html;
  final inCode =
      state.getNodeAtPath(selection.start.path)?.type == CodeBlockKeys.type;
  if (mode == PasteMode.automatic && !inCode) {
    try {
      html = await _clipboard.invokeMethod<String>('getHtml');
    } on MissingPluginException {
      // Older runners and test hosts still support text clipboard paste.
    } on PlatformException {
      // A failed HTML read must not prevent text paste.
    }
  }
  // Clipboard reads yield: never paste into a different tab or moved selection.
  if (state.isDisposed || state.selection != selection || !state.editable) {
    return;
  }
  await pasteContent(state, text: text, html: html, mode: mode);
}

/// Testable paste pipeline; the live document changes only once, after preparation.
Future<void> pasteContent(
  EditorState state, {
  String? text,
  String? html,
  PasteMode mode = PasteMode.automatic,
}) async {
  final selection = state.selection;
  if (selection == null || !state.editable || state.isDisposed) return;
  final inCode =
      state.getNodeAtPath(selection.start.path)?.type == CodeBlockKeys.type;
  List<Node>? nodes;
  if (!inCode && mode != PasteMode.plainText) {
    if (mode == PasteMode.automatic && html != null && html.trim().isNotEmpty) {
      try {
        nodes = clipboardHtmlToDocument(html).root.children.toList();
      } on FormatException {
        // Invalid fragments can still fall back to their plain representation.
      }
    }
    if ((nodes == null || nodes.isEmpty) &&
        text != null &&
        text.isNotEmpty &&
        (mode == PasteMode.markdown || hasBlockMarkdown(text))) {
      nodes = markdownToEditorDocument(text).root.children.toList();
    }
  }
  if ((nodes == null || nodes.isEmpty) && (text == null || text.isEmpty)) {
    return;
  }

  final draft =
      EditorState(document: Document.fromJson(state.document.toJson()))
        ..selection = selection;
  final operations = <Operation>[];
  final subscription = draft.transactionStream.listen((event) {
    if (event.$1 != TransactionTime.before) return;
    // The draft owns its nodes; capture independent operation payloads before
    // applying so subsequent edits and disposal cannot mutate the live undo data.
    operations.addAll(event.$2.operations.map(_copyOperation));
  });
  try {
    if (inCode) {
      await _pasteRawCode(draft, text ?? '');
    } else if (nodes == null || nodes.isEmpty) {
      // Preserve the editor's normal text/link and multiline paste behavior.
      await pastePlainTextContent(draft, text!);
    } else {
      if (!selection.isCollapsed) await draft.deleteSelection(selection);
      await _insertNodes(draft, nodes);
    }
    if (operations.isEmpty) return;
    if (state.isDisposed || state.selection != selection || !state.editable) {
      return;
    }
    final transaction = state.transaction
      ..operations = operations
      ..afterSelection = draft.selection;
    // Isolate paste from typing on either side of it in the history stack.
    if (state.undoManager.undoStack.isNonEmpty) {
      state.undoManager.undoStack.last.seal();
    }
    await state.apply(transaction, skipHistoryDebounce: true);
  } finally {
    await subscription.cancel();
    draft.dispose();
  }
}

Operation _copyOperation(Operation op) => switch (op) {
      InsertOperation() => InsertOperation.fromJson(op.toJson()),
      DeleteOperation() => DeleteOperation.fromJson(op.toJson()),
      UpdateOperation() => UpdateOperation.fromJson(op.toJson()),
      UpdateTextOperation() => UpdateTextOperation.fromJson(op.toJson()),
    };

Future<void> _pasteRawCode(EditorState state, String text) async {
  if (text.isEmpty) return;
  final selection = state.selection!.normalized;
  if (!selection.isCollapsed) await state.deleteSelection(selection);
  final cursor = state.selection!.end;
  final node = state.getNodeAtPath(cursor.path);
  if (node?.delta == null) return;
  final transaction = state.transaction..insertText(node!, cursor.offset, text);
  transaction.afterSelection = Selection.collapsed(
    Position(path: cursor.path, offset: cursor.offset + text.length),
  );
  await state.apply(transaction);
}

Future<void> _insertNodes(EditorState state, List<Node> nodes) async {
  final cursor = state.selection!.end;
  final current = state.getNodeAtPath(cursor.path);
  final transaction = state.transaction;
  // A single rich paragraph is inline content, even when copied from HTML.
  if (current?.delta != null &&
      nodes.length == 1 &&
      nodes.first.type == ParagraphBlockKeys.type &&
      nodes.first.children.isEmpty) {
    final delta = nodes.first.delta!;
    transaction.insertTextDelta(current!, cursor.offset, delta);
    transaction.afterSelection = Selection.collapsed(
      Position(path: cursor.path, offset: cursor.offset + delta.length),
    );
  } else {
    final replace = current?.type == ParagraphBlockKeys.type &&
        current?.delta?.isEmpty == true;
    final path = current == null
        ? <int>[state.document.root.children.length]
        : replace
            ? current.path
            : current.path.next;
    transaction.insertNodes(path, nodes);
    if (replace) transaction.deleteNode(current!);
    var endPath = [...path.parent, path.last + nodes.length - 1];
    var last = nodes.last;
    while (last.children.isNotEmpty) {
      endPath = [...endPath, last.children.length - 1];
      last = last.children.last;
    }
    // Non-text blocks need a trailing paragraph as an editable cursor target.
    if (nodes.last.delta == null || last.delta == null) {
      endPath = [...path.parent, path.last + nodes.length];
      // This path refers to the document after the preceding insert/delete.
      transaction.add(InsertOperation(endPath, [paragraphNode()]),
          transform: false);
      last = paragraphNode();
    }
    transaction.afterSelection = Selection.collapsed(
      Position(path: endPath, offset: last.delta?.length ?? 0),
    );
  }
  await state.apply(transaction);
}
