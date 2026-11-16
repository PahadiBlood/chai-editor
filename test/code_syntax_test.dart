import 'package:chai_editor/code_block.dart';
import 'package:chai_editor/code_syntax.dart';
import 'package:chai_editor/markdown_io.dart';
import 'package:chai_editor/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final highlighter = CodeHighlighter();
  test('aliases and fence labels map to the supported languages', () {
    for (final entry in {
      'SH': 'bash',
      'zsh': 'bash',
      'shell': 'bash',
      'js': 'javascript',
      'ts': 'typescript',
      'yml': 'yaml',
      '```xml': 'xml',
      'language-kotlin': 'kotlin',
      'lang-rs': 'rust',
      'auto': '',
      'c++': 'cpp',
    }.entries) {
      expect(normalizeCodeLanguage(entry.key), entry.value);
    }
    expect(codeLanguages, containsAll(commonCodeLanguages));
    expect(codeLanguages.toSet().length, codeLanguages.length);
  });

  test(
      'every grammar preserves UTF-16 text, whitespace, tabs and trailing lines',
      () {
    const input = '  const value = "<& 😀 हिन्दी";\n\t// comment\n\n';
    for (final language in ['', ...commonCodeLanguages, 'unsupported']) {
      final result = highlighter.highlight(input, language);
      expect(result.tokens.map((t) => t.text).join(), input, reason: language);
      final span = result.toTextSpan(const TextStyle(fontFamily: monoFont));
      expect(span.toPlainText(), input, reason: language);
      expect(span.toPlainText().length, input.length);
      expect(
          result.lines.map((line) => line.map((t) => t.text).join()).join('\n'),
          input);
    }
  });

  test(
      'Dart has keyword, number, string and italic comment tokens in both palettes',
      () {
    final result =
        highlighter.highlight('const x = 42; // comment\nprint("hi");', 'dart');
    final tokens = result.tokens;
    expect(
        tokens.any((t) => t.scope == 'keyword' && t.text == 'const'), isTrue);
    expect(tokens.any((t) => t.scope == 'number' && t.text == '42'), isTrue);
    expect(tokens.any((t) => t.scope == 'string'), isTrue);
    expect(
        tokens.any((t) => t.italic && t.text.contains('// comment')), isTrue);
    expect(CodeSyntaxColors.dark.forScope('keyword'), const Color(0xFFFF7B72));
    expect(CodeSyntaxColors.light.forScope('keyword'), const Color(0xFFCF222E));
    expect(
        CodeSyntaxColors.dark.forScope('title.class'), const Color(0xFFFFA657));
    expect(CodeSyntaxColors.dark.forScope('operator'), AppColors.codeText);
  });

  test(
      'cache uses normalized language and never alters stored language on detection',
      () {
    const text = 'const answer = 42;';
    expect(
        identical(highlighter.highlight(text, 'js'),
            highlighter.highlight(text, 'javascript')),
        isTrue);
    final document = markdownToEditorDocument(
        '```\nimport json\nfrom pathlib import Path\n\ndef hello(name):\n    # Read a value\n    with open("file.json") as f:\n        data = json.load(f)\n    return {"name": name, "data": data}\n\nif __name__ == "__main__":\n    print(hello("World"))\n```');
    final node = document.first!;
    final before = document.toJson();
    final result = highlighter.highlight(node.delta!.toPlainText());
    expect(result.detectedLanguage, 'python');
    expect(document.toJson(), before);
    expect(editorDocumentToMarkdown(document), startsWith('```\n'));
    expect(highlighter.highlight('hello').detectedLanguage, isNull);
  });

  test('20,000 limit and unknown languages fail safely to one plain span', () {
    for (final text in ['x' * 20001, 'normal unsupported text']) {
      final result =
          highlighter.highlight(text, text.length > 20000 ? 'dart' : 'unknown');
      expect(result.tokens.length, 1);
      expect(result.tokens.single.scope, '');
      expect(result.tokens.single.text, text);
      expect(result.detectedLanguage, isNull);
    }
  });

  test(
      'Markdown retains aliases canonically, embedded fences and exact code newlines',
      () {
    const text = '\tconst x = "```";\n\n';
    final document = markdownToEditorDocument('````js\n$text\n````');
    expect(document.first!.attributes['language'], 'javascript');
    expect(document.first!.delta!.toPlainText(), text);
    final reopened =
        markdownToEditorDocument(editorDocumentToMarkdown(document));
    expect(reopened.first!.delta!.toPlainText(), text);
    expect(reopened.first!.attributes['language'], 'javascript');
  });
  test(
      'bounded cache evicts old text; printing wraps without splitting graphemes',
      () {
    final local = CodeHighlighter();
    final first = local.highlight('const first = 1;', 'dart');
    for (var i = 0; i < 70; i++) {
      local.highlight('const value = $i;', 'dart');
    }
    expect(identical(first, local.highlight(first.text, 'dart')), isFalse);
    const text = 'ab😀é\tvalue';
    final wrapped = wrapCodeLine(const [CodeToken(text, 'string')], columns: 4);
    expect(wrapped.expand((line) => line).map((t) => t.text).join(), text);
    expect(wrapped.first.single.text, 'ab😀é');
  });
}
