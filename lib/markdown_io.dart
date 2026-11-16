import 'package:appflowy_editor/appflowy_editor.dart';

import 'code_block.dart';

/// Markdown text -> editor document.
Document markdownToEditorDocument(String markdown) {
  if (markdown.trim().isEmpty) {
    return Document.blank(withInitialText: true);
  }

  final document = markdownToDocument(
    markdown.replaceAll('\r\n', '\n'),
    markdownParsers: const [MarkdownCodeBlockParser()],
  );

  if (document.root.children.isEmpty) {
    return Document.blank(withInitialText: true);
  }
  return document;
}

/// Editor document -> Markdown text.
///
/// This is our own writer because the built-in one puts no blank line
/// between paragraphs and numbers every list item "1.".
String editorDocumentToMarkdown(Document document) {
  final out = StringBuffer();
  final nodes = document.root.children.toList();

  Node? previous;
  var number = 0;

  for (final node in nodes) {
    if (node.type == NumberedListBlockKeys.type) {
      number = previous?.type == NumberedListBlockKeys.type ? number + 1 : 1;
    }

    final text = _block(node, number: number).trimRight();
    if (text.isEmpty) {
      // Empty blocks are dropped so they do not create stray blank lines.
      continue;
    }

    if (previous != null) {
      // Items of the same kind of list stay together; everything else gets
      // a blank line.
      final sameList = _isList(node) && previous.type == node.type;
      out.write(sameList ? '\n' : '\n\n');
    }
    out.write(text);
    previous = node;
  }

  final result = out.toString().trimRight();
  return result.isEmpty ? '' : '$result\n';
}

bool _isList(Node node) =>
    node.type == BulletedListBlockKeys.type ||
    node.type == NumberedListBlockKeys.type ||
    node.type == TodoListBlockKeys.type;

String _inline(Node node) {
  final delta = node.delta;
  if (delta == null) return '';
  return DeltaMarkdownEncoder().convert(delta);
}

/// A soft line break (Shift+Enter) becomes a Markdown hard break.
String _inlineWithBreaks(Node node) => _inline(node).replaceAll('\n', '  \n');

String _block(Node node, {int number = 1}) {
  switch (node.type) {
    case 'heading':
      final level = (node.attributes[HeadingBlockKeys.level] as int?) ?? 1;
      return '${'#' * level} ${_inline(node).replaceAll('\n', ' ')}';

    case 'bulleted_list':
      return _listItem(node, '- ');

    case 'numbered_list':
      return _listItem(node, '$number. ');

    case 'todo_list':
      final checked = node.attributes[TodoListBlockKeys.checked] == true;
      return _listItem(node, checked ? '- [x] ' : '- [ ] ');

    case 'quote':
      return _inline(node)
          .split('\n')
          .map((line) => '> $line')
          .join('\n');

    case 'code':
      final language = (node.attributes[CodeBlockKeys.language] as String?) ?? '';
      final text = node.delta?.toPlainText() ?? '';
      return '```$language\n$text\n```';

    case 'divider':
      return '---';

    case 'image':
      return '![](${node.attributes[ImageBlockKeys.url] ?? ''})';

    case 'table':
      return const TableNodeParser().transform(node, null).trimRight();

    default:
      return _inlineWithBreaks(node);
  }
}

String _listItem(Node node, String prefix) {
  final buffer = StringBuffer('$prefix${_inlineWithBreaks(node)}');

  var childNumber = 0;
  Node? previous;
  for (final child in node.children) {
    if (child.type == NumberedListBlockKeys.type) {
      childNumber =
          previous?.type == NumberedListBlockKeys.type ? childNumber + 1 : 1;
    }
    final text = _block(child, number: childNumber).trimRight();
    final indent = ' ' * 3;
    for (final line in text.split('\n')) {
      buffer.write('\n$indent$line');
    }
    previous = child;
  }
  return buffer.toString();
}
