import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'code_block.dart';
import 'code_syntax.dart';

// Retain the former external-pre newline trimming for compatibility if needed.
const trimExternalPreNewline =
    bool.fromEnvironment('CHAI_TRIM_EXTERNAL_PRE_NEWLINE', defaultValue: false);

/// Decode clipboard fragments without browser metadata or executable content.
/// A DOM-to-node conversion avoids Markdown escaping and preserves rich deltas.
Document clipboardHtmlToDocument(String source) {
  final fragment = RegExp(
    r'<!--\s*StartFragment\s*-->([\s\S]*?)<!--\s*EndFragment\s*-->',
    caseSensitive: false,
  ).firstMatch(source);
  final document = html.parse(fragment?.group(1) ?? source);
  for (final element in document.querySelectorAll(
    'meta, style, script, title, link, noscript, button, svg',
  )) {
    element.remove();
  }
  final body = document.body;
  return Document(
      root: Node(
          type: 'page',
          children: _blocks(
            body != null && _isCodeContainer(body) ? [body] : body?.nodes ?? [],
          )));
}

const _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'main',
  'header',
  'footer',
  'figure',
  'figcaption',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'pre',
  'ul',
  'ol',
  'li',
  'blockquote',
  'table',
  'hr',
  'img',
};

List<Node> _blocks(Iterable<dom.Node> source) {
  final result = <Node>[];
  var inline = <dom.Node>[];
  void flush() {
    final delta = _inline(inline);
    if (delta.toPlainText().trim().isNotEmpty) {
      result.add(paragraphNode(delta: delta));
    }
    inline = [];
  }

  for (final child in source) {
    if (child is! dom.Element) {
      inline.add(child);
      continue;
    }
    final tag = child.localName;
    if (_isCodeContainer(child)) {
      flush();
      final code = child.querySelector('code');
      final language = _codeLanguage(child);
      var text = _preText(tag == 'pre' ? (code ?? child) : child)
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll('\u00a0', ' ');
      // Code whitespace is content. Keep the former layout-newline trimming
      // available behind a flag, while exact clipboard round trips stay intact.
      if (trimExternalPreNewline &&
          tag == 'pre' &&
          child.attributes['data-chai-code'] != 'true' &&
          text.endsWith('\n')) {
        text = text.substring(0, text.length - 1);
      }
      result.add(codeBlockNode(text: text, language: language));
      continue;
    }
    // Clipboard producers often wrap a whole document in a span or <b>.
    if (!_blockTags.contains(tag) &&
        child.querySelectorAll(_blockTags.join(',')).isEmpty &&
        !child.querySelectorAll('[style], code').any(_isCodeContainer)) {
      inline.add(child);
      continue;
    }
    flush();
    if (tag == 'ul' || tag == 'ol') {
      var number = int.tryParse(child.attributes['start'] ?? '') ?? 1;
      for (final item in child.children.where((e) => e.localName == 'li')) {
        final content = _blocks(item.nodes);
        final first = content.isNotEmpty && content.first.delta != null
            ? content.removeAt(0)
            : paragraphNode();
        final checkbox = item.querySelector('input[type="checkbox"]');
        final task = checkbox != null ||
            item.attributes['data-type'] == 'taskItem' ||
            item.attributes.containsKey('data-checked') ||
            item.attributes.containsKey('aria-checked');
        result.add(Node(
          type: task
              ? TodoListBlockKeys.type
              : tag == 'ol'
                  ? NumberedListBlockKeys.type
                  : BulletedListBlockKeys.type,
          attributes: {
            blockComponentDelta: first.delta!.toJson(),
            if (task)
              TodoListBlockKeys.checked:
                  checkbox?.attributes.containsKey('checked') == true ||
                      item.attributes['data-checked'] == 'true' ||
                      item.attributes['aria-checked'] == 'true',
            if (tag == 'ol') NumberedListBlockKeys.number: number++,
          },
          children: [...first.children, ...content],
        ));
      }
    } else if (tag == 'table') {
      final rows = child
          .querySelectorAll('tr')
          .where((row) {
            var parent = row.parent;
            while (parent != null && parent.localName != 'table') {
              parent = parent.parent;
            }
            return parent == child;
          })
          .map((row) => row.children
              .where((cell) => cell.localName == 'td' || cell.localName == 'th')
              .map((cell) => paragraphNode(delta: _inline([cell])))
              .toList())
          .where((row) => row.isNotEmpty)
          .toList();
      if (rows.isNotEmpty) {
        final width =
            rows.map((row) => row.length).reduce((a, b) => a > b ? a : b);
        result.add(TableNode.fromList<Node>([
          for (var col = 0; col < width; col++)
            [
              for (final row in rows)
                col < row.length ? row[col] : paragraphNode(),
            ],
        ]).node);
      }
    } else if (tag == 'img') {
      final url = child.attributes['src'];
      if (url != null && url.isNotEmpty) result.add(imageNode(url: url));
    } else if (tag == 'hr') {
      result.add(dividerNode());
    } else if (tag == 'blockquote') {
      final content = _blocks(child.nodes);
      for (final node in content) {
        result.add(node.delta != null && node.type == ParagraphBlockKeys.type
            ? node.copyWith(type: QuoteBlockKeys.type)
            : node);
      }
    } else if (RegExp(r'^h[1-6]$').hasMatch(tag ?? '')) {
      result
          .add(headingNode(level: int.parse(tag![1]), delta: _inline([child])));
    } else if ((tag == 'p' || tag == 'div') &&
        child.querySelectorAll(_blockTags.join(',')).isEmpty &&
        !child.querySelectorAll('[style], code').any((element) =>
            _isCodeContainer(element) &&
            (element.localName != 'span' ||
                RegExp(r'white-space\s*:\s*pre|display\s*:\s*block')
                    .hasMatch(element.attributes['style'] ?? '')))) {
      final delta = _inline([child]);
      if (delta.isNotEmpty) result.add(paragraphNode(delta: delta));
    } else {
      result.addAll(_blocks(child.nodes));
    }
  }
  flush();
  return result;
}

bool _isCodeContainer(dom.Element element) {
  final tag = element.localName;
  final style = (element.attributes['style'] ?? '').toLowerCase();
  if (tag == 'pre') return true;
  if (tag == 'code' &&
      (RegExp(r'display\s*:\s*block').hasMatch(style) ||
          element.nodes.any(
              (n) => n is dom.Element && _blockTags.contains(n.localName)) ||
          element.parent?.localName == 'body')) {
    return true;
  }
  if (RegExp(r'white-space\s*:\s*pre(?:-wrap)?(?:\s*[;!]|\s*$)')
      .hasMatch(style)) {
    return true;
  }
  if (RegExp(
          r'font-family\s*:[^;]*(?:monospace|menlo|monaco|consolas|courier|sf\s?mono|jetbrains\s?mono|fira\s?code)')
      .hasMatch(style)) {
    return true;
  }
  // GitHub and highlight.js line-number tables do not always carry styles.
  return tag == 'table' &&
      element.querySelector('.blob-code, .hljs-ln-code') != null;
}

String _codeLanguage(dom.Element element) {
  for (final candidate in [element, ...element.querySelectorAll('*')]) {
    final data = candidate.attributes['data-language'];
    if (data != null && data.trim().isNotEmpty) {
      return normalizeCodeLanguage(data);
    }
    final match = RegExp(r'(?:language|lang)-([\w+#.-]+)')
        .firstMatch(candidate.className);
    if (match != null) return normalizeCodeLanguage(match.group(1)!);
    if (candidate.classes.contains('hljs')) {
      for (final cls in candidate.classes) {
        final lang = normalizeCodeLanguage(cls);
        if (commonCodeLanguages.contains(lang)) return lang;
      }
    }
  }
  return '';
}

bool _lineNumber(dom.Element element) =>
    element.attributes['data-chai-line-number'] == 'true' ||
    ((element.attributes.containsKey('data-line-number') ||
            RegExp(r'user-select\s*:\s*none')
                .hasMatch(element.attributes['style'] ?? '')) &&
        RegExp(r'^\s*\d+\s*$').hasMatch(element.text)) ||
    element.classes.any((cls) => RegExp(
            r'^(?:line-numbers?(?:-rows)?|linenos?|gutter|blob-num|hljs-ln-numbers|linenumber)$',
            caseSensitive: false)
        .hasMatch(cls));

String _preText(dom.Node node) {
  if (node is dom.Text) return node.text;
  if (node is! dom.Element) return node.nodes.map(_preText).join();
  if (_lineNumber(node)) return '';
  if (node.localName == 'br') return '\n';
  final out = StringBuffer();
  var previousWasBlock = false;
  for (final child in node.nodes) {
    if (child is dom.Element && _lineNumber(child)) continue;
    final block = child is dom.Element &&
        const {'div', 'p', 'tr', 'li'}.contains(child.localName);
    final value = _preText(child);
    if ((block || previousWasBlock) &&
        out.isNotEmpty &&
        !out.toString().endsWith('\n')) {
      out.write('\n');
    }
    out.write(value);
    if (block && value.isEmpty) out.write('\n');
    previousWasBlock = block;
  }
  return out.toString();
}

Delta _inline(Iterable<dom.Node> nodes) {
  final delta = Delta();
  void visit(dom.Node node, Map<String, dynamic> inherited) {
    if (node is dom.Text) {
      final text = node.text
          .replaceAll(RegExp(r'[\t\r\n ]+'), ' ')
          .replaceAll('\u00a0', ' ');
      delta.insert(text, attributes: inherited);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    if (tag == 'input') return;
    if (tag == 'br') {
      delta.insert('\n', attributes: inherited);
      return;
    }
    final style = <String, String>{};
    for (final declaration in (node.attributes['style'] ?? '').split(';')) {
      final colon = declaration.indexOf(':');
      if (colon > 0) {
        style[declaration.substring(0, colon).trim().toLowerCase()] =
            declaration.substring(colon + 1).trim().toLowerCase();
      }
    }
    final weight = style['font-weight'];
    final attributes = <String, dynamic>{
      ...inherited,
      if (tag == 'b' ||
          tag == 'strong' ||
          (tag == 'th' && weight != 'normal' && weight != '400') ||
          weight == 'bold' ||
          (int.tryParse(weight ?? '') ?? 0) >= 600)
        AppFlowyRichTextKeys.bold: true,
      if (tag == 'i' || tag == 'em' || style['font-style'] == 'italic')
        AppFlowyRichTextKeys.italic: true,
      if (tag == 'code' ||
          tag == 'tt' ||
          RegExp(r'monospace|menlo|monaco|courier|consolas|sf\s?mono|jetbrains\s?mono|fira\s?code')
              .hasMatch(style['font-family'] ?? ''))
        AppFlowyRichTextKeys.code: true,
      if (tag == 'u' || (style['text-decoration'] ?? '').contains('underline'))
        AppFlowyRichTextKeys.underline: true,
      if (tag == 's' ||
          tag == 'del' ||
          (style['text-decoration'] ?? '').contains('line-through'))
        AppFlowyRichTextKeys.strikethrough: true,
      if (tag == 'a' && node.attributes['href'] != null)
        AppFlowyRichTextKeys.href: node.attributes['href'],
    };
    for (final child in node.nodes) {
      visit(child, attributes);
    }
    if (tag == 'p' || tag == 'div') delta.insert('\n');
  }

  for (final node in nodes) {
    visit(node, {});
  }
  // HTML indentation is layout whitespace, not content at paragraph boundaries.
  final text = delta.toPlainText();
  final start = text.length - text.trimLeft().length;
  final end = text.trimRight().length;
  return end > start ? delta.slice(start, end) : Delta();
}
