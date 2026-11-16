import 'dart:async';
import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'code_syntax.dart';
import 'export/export_model.dart';
import 'markdown_io.dart';
import 'theme.dart';

const enableRichCopy =
    bool.fromEnvironment('CHAI_RICH_COPY', defaultValue: true);
const _channel = MethodChannel('chai/clipboard');
const _escape = HtmlEscape(HtmlEscapeMode.element);
const _escapeAttribute = HtmlEscape(HtmlEscapeMode.attribute);

String coloredCodeHtml(String text, String language) {
  final highlighted = CodeHighlighter.shared.highlight(text, language);
  final lang = normalizeCodeLanguage(language);
  final spans = highlighted.tokens
      .map((token) =>
          '<span style="color:#${syntaxColorHex(CodeSyntaxColors.dark.forScope(token.scope))};${token.italic ? 'font-style:italic;' : ''}">${_escape.convert(token.text)}</span>')
      .join();
  return '<pre data-chai-code="true" style="background:#151517;color:#E6E6E6;padding:12px;white-space:pre-wrap;font-family:Menlo,Consolas,monospace;"><code class="language-${_escapeAttribute.convert(lang)}">$spans</code></pre>';
}

/// Standalone inline styles travel to apps which discard stylesheets/classes.
String documentClipboardHtml(Document document) {
  String inline(ExportBlock block) => block.runs.map((run) {
        var value = _escape.convert(run.text).replaceAll('\n', '<br>');
        if (run.has('code')) value = '<code>$value</code>';
        if (run.has('bold')) value = '<strong>$value</strong>';
        if (run.has('italic')) value = '<em>$value</em>';
        if (run.has('underline')) value = '<u>$value</u>';
        if (run.has('strikethrough')) value = '<s>$value</s>';
        if (run.link != null) {
          value = '<a href="${_escapeAttribute.convert(run.link!)}">$value</a>';
        }
        return value;
      }).join();
  String blocks(List<ExportBlock> input) {
    final out = StringBuffer();
    var i = 0;
    while (i < input.length) {
      final block = input[i++];
      final value = inline(block);
      switch (block.type) {
        case 'code':
          out.write(coloredCodeHtml(block.text, block.language));
        case 'heading':
          final level = block.level.clamp(1, 6);
          out.write('<h$level>$value</h$level>');
        case 'bulleted_list' || 'numbered_list' || 'todo_list':
          final tag = block.type == 'numbered_list' ? 'ol' : 'ul';
          out.write('<$tag>');
          void item(ExportBlock item) {
            final task = item.type == 'todo_list'
                ? ' data-type="taskItem" data-checked="${item.checked}"'
                : '';
            final checkbox = item.type == 'todo_list'
                ? '<input type="checkbox"${item.checked ? ' checked' : ''}>'
                : '';
            out.write(
                '<li$task>$checkbox${inline(item)}${blocks(item.children)}</li>');
          }
          item(block);
          while (i < input.length && input[i].type == block.type) {
            item(input[i++]);
          }
          out.write('</$tag>');
          continue;
        case 'table':
          out.write('<table>');
          for (var row = 0; row < block.rows.length; row++) {
            final cellTag = row == 0 ? 'th' : 'td';
            out.write(
                '<tr>${block.rows[row].map((cell) => '<$cellTag${row == 0 ? ' style="font-weight:normal"' : ''}>${inline(cell)}</$cellTag>').join()}</tr>');
          }
          out.write('</table>');
        case 'quote':
          out.write('<blockquote><p>$value</p></blockquote>');
        case 'divider':
          out.write('<hr>');
        case 'image':
          out.write('<img src="${_escapeAttribute.convert(block.image)}">');
        default:
          out.write('<p>$value</p>');
      }
      out.write(blocks(block.children));
    }
    return out.toString();
  }

  return '<html><body><!--StartFragment-->${blocks(ExportModel.fromDocument(document).blocks)}<!--EndFragment--></body></html>';
}

Future<void> writeDocumentClipboard(Document document) async {
  final text = editorDocumentToMarkdown(document);
  final html = documentClipboardHtml(document);
  try {
    final success = await _channel.invokeMethod<bool>('setClipboard', {
      'text': text,
      'html': html,
    });
    if (success != true) {
      throw PlatformException(code: 'clipboard_write_failed');
    }
  } on MissingPluginException {
    await Clipboard.setData(ClipboardData(text: text));
  } on PlatformException {
    await Clipboard.setData(ClipboardData(text: text));
  }
}

final richCopyCommand =
    copyCommand.copyWith(handler: (state) => _startCopy(state, cut: false));
final richCutCommand =
    cutCommand.copyWith(handler: (state) => _startCopy(state, cut: true));

KeyEventResult _startCopy(EditorState state, {required bool cut}) {
  final selection = state.selection;
  if (selection == null || selection.isCollapsed || (cut && !state.editable)) {
    return KeyEventResult.ignored;
  }
  unawaited(copyEditorSelection(state, cut: cut).catchError(
    (Object error, StackTrace stack) => FlutterError.reportError(
        FlutterErrorDetails(
            exception: error, stack: stack, library: 'Chai copy')),
  ));
  return KeyEventResult.handled;
}

Future<void> copyEditorSelection(EditorState state, {bool cut = false}) async {
  final selection = state.selection?.normalized;
  if (state.isDisposed ||
      selection == null ||
      selection.isCollapsed ||
      (cut && !state.editable)) {
    return;
  }
  final before = cut ? jsonEncode(state.document.toJson()) : null;
  final nodes = state.getSelectedNodes(selection: selection);
  if (nodes.isEmpty) return;
  final document = Document(root: Node(type: 'page', children: nodes));
  await writeDocumentClipboard(document);
  // A clipboard write yields. Never cut from a changed document/selection/tab,
  // and never delete anything until a clipboard flavour was successfully written.
  if (!cut ||
      state.isDisposed ||
      !state.editable ||
      state.selection?.normalized != selection ||
      jsonEncode(state.document.toJson()) != before) {
    return;
  }
  if (state.undoManager.undoStack.isNonEmpty) {
    state.undoManager.undoStack.last.seal();
  }
  await state.deleteSelection(selection);
  if (state.undoManager.undoStack.isNonEmpty) {
    state.undoManager.undoStack.last.seal();
  }
}
