import 'package:appflowy_editor/appflowy_editor.dart';

import 'code_block.dart';

/// Everything the toolbar can do to a document.

bool isInlineActive(EditorState state, Selection? selection, String key) {
  selection = selection ?? state.selection;
  if (selection == null) return false;

  if (selection.isCollapsed) {
    return state.toggledStyle.containsKey(key);
  }
  final nodes = state.getNodesInSelection(selection);
  return nodes.allSatisfyInSelection(selection, (delta) {
    return delta.everyAttributes((attributes) => attributes[key] == true);
  });
}

bool isBlockActive(
  EditorState state,
  Selection? selection,
  String type, {
  int? level,
}) {
  selection = selection ?? state.selection;
  if (selection == null) return false;
  final nodes = state.getNodesInSelection(selection);
  if (nodes.isEmpty) return false;
  return nodes.every((node) =>
      node.type == type &&
      (level == null || node.attributes[HeadingBlockKeys.level] == level));
}

Future<void> toggleInline(EditorState state, String key) async {
  await state.toggleAttribute(key);
}

/// Turns the selected text blocks into [type]. Doing it again turns them
/// back into a paragraph.
Future<void> convertBlock(
  EditorState state,
  String type, {
  Map<String, Object?> extra = const {},
}) async {
  await state.formatNode(null, (node) {
    if (node.delta == null) return node;

    final same = node.type == type &&
        extra.entries.every((e) => node.attributes[e.key] == e.value);
    if (same) {
      return node.copyWith(type: ParagraphBlockKeys.type);
    }
    return node.copyWith(
      type: type,
      attributes: {...node.attributes, ...extra},
    );
  });
}

Future<void> toParagraph(EditorState state) async {
  await state.formatNode(null, (node) {
    if (node.delta == null) return node;
    return node.copyWith(type: ParagraphBlockKeys.type);
  });
}

Future<void> toHeading(EditorState state, int level) => convertBlock(
      state,
      HeadingBlockKeys.type,
      extra: {HeadingBlockKeys.level: level},
    );

Future<void> toBulletedList(EditorState state) =>
    convertBlock(state, BulletedListBlockKeys.type);

Future<void> toNumberedList(EditorState state) =>
    convertBlock(state, NumberedListBlockKeys.type);

Future<void> toChecklist(EditorState state) => convertBlock(
      state,
      TodoListBlockKeys.type,
      extra: {TodoListBlockKeys.checked: false},
    );

Future<void> toQuote(EditorState state) =>
    convertBlock(state, QuoteBlockKeys.type);

Future<void> toCodeBlock(EditorState state) => convertBlock(
      state,
      CodeBlockKeys.type,
      extra: {CodeBlockKeys.language: ''},
    );

/// Inserts [node] after the cursor block. An empty paragraph is replaced.
/// With no cursor, the block goes at the end of the document.
Future<void> insertBlock(
  EditorState state,
  Node node, {
  List<int> cursorOffsetPath = const [],
}) async {
  final selection = state.selection;
  final transaction = state.transaction;
  late final Path insertedAt;

  final current =
      selection == null ? null : state.getNodeAtPath(selection.end.path);

  if (current == null) {
    insertedAt = [state.document.root.children.length];
    transaction.insertNode(insertedAt, node);
  } else if (current.delta != null && current.delta!.isEmpty) {
    insertedAt = current.path;
    transaction
      ..insertNode(insertedAt, node)
      ..deleteNode(current);
  } else {
    insertedAt = current.path.next;
    transaction.insertNode(insertedAt, node);
  }

  transaction.afterSelection = Selection.collapsed(
    Position(path: [...insertedAt, ...cursorOffsetPath]),
  );
  await state.apply(transaction);
}

Future<void> insertTable(EditorState state) {
  final table = TableNode.fromList([
    ['', '', ''],
    ['', '', ''],
    ['', '', ''],
  ]);
  return insertBlock(state, table.node, cursorOffsetPath: const [0, 0]);
}

Future<void> insertDivider(EditorState state) =>
    insertBlock(state, dividerNode());

Future<void> insertImage(EditorState state, String pathOrUrl) =>
    insertBlock(state, imageNode(url: pathOrUrl));

Future<void> insertCodeBlock(EditorState state) =>
    insertBlock(state, codeBlockNode());
