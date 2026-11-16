import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:chai_editor/clipboard_html.dart';
import 'package:chai_editor/code_block.dart';
import 'package:chai_editor/markdown_io.dart';
import 'package:chai_editor/paste.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

EditorState editor(String markdown, {int offset = 0}) {
  final state = EditorState(document: markdownToEditorDocument(markdown))
    ..selection = Selection.collapsed(Position(path: [0], offset: offset));
  addTearDown(state.dispose);
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Markdown detection', () {
    for (final text in [
      '# Heading',
      '- item',
      '* item',
      '1. item',
      '> quote',
      '```dart\nx\n```',
      '~~~bash\nx\n~~~',
      '| a | b |',
      'Intro\r\n\r\n## Heading',
      '- [x] done'
    ]) {
      test('recognizes $text', () => expect(hasBlockMarkdown(text), isTrue));
    }
    for (final text in [
      'hello',
      'some **bold** text',
      'x # tag',
      'a - b',
      '1.5 is a number',
      '#hashtag',
      'a | b',
      '    - indented code'
    ]) {
      test('leaves $text alone', () => expect(hasBlockMarkdown(text), isFalse));
    }
  });

  test('HTML preserves block types and removes browser wrapper junk', () {
    final doc = clipboardHtmlToDocument('''
      <html><head><meta charset="utf-8"><style>p {color:red}</style></head><body>
      unwanted<!--StartFragment--><div><h2>Heading</h2>
      <p>A <strong>bold <em>and italic</em></strong> <code>x()</code>
      <a href="https://example.com">link</a></p>
      <ul><li>bullet<ul><li>nested</li></ul></li></ul>
      <ol start="3"><li>numbered</li></ol>
      <ul><li><input type="checkbox" checked>done</li><li data-checked="false">todo</li></ul>
      <blockquote><p>quote</p></blockquote>
      <pre><code class="language-dart">  if (a &lt; b) {\n    run();\n  }\n</code></pre>
      <table><thead><tr><th>A</th><th>B</th></tr></thead>
      <tbody><tr><td><strong>one</strong></td><td>two</td></tr></tbody></table>
      <p><img src="https://example.com/img.png"></p></div><!--EndFragment-->
      unwanted</body></html>''');
    final nodes = doc.root.children.toList();
    expect(nodes.map((n) => n.type), [
      'heading',
      'paragraph',
      'bulleted_list',
      'numbered_list',
      'todo_list',
      'todo_list',
      'quote',
      'code',
      'table',
      'image',
    ]);
    expect(nodes.first.attributes[HeadingBlockKeys.level], 2);
    final delta = nodes[1].delta!;
    expect(delta.toJson(), contains(containsPair('insert', 'bold ')));
    expect(
        delta.toJson(),
        contains(allOf(
          containsPair('insert', 'and italic'),
          containsPair('attributes', containsPair('bold', true)),
          containsPair('attributes', containsPair('italic', true)),
        )));
    expect(delta.toJson(),
        contains(containsPair('attributes', containsPair('code', true))));
    expect(
        delta.toJson(),
        contains(containsPair(
            'attributes', containsPair('href', 'https://example.com'))));
    expect(nodes[2].children.single.delta!.toPlainText(), 'nested');
    expect(nodes[3].attributes[NumberedListBlockKeys.number], 3);
    expect(nodes[4].attributes[TodoListBlockKeys.checked], true);
    expect(nodes[5].attributes[TodoListBlockKeys.checked], false);
    expect(nodes[7].attributes[CodeBlockKeys.language], 'dart');
    expect(nodes[7].delta!.toPlainText(), '  if (a < b) {\n    run();\n  }');
    final table = TableNode(node: nodes[8]);
    expect(table.getCell(0, 1).children.single.delta!.toPlainText(), 'one');
    expect(table.getCell(1, 0).children.single.delta!.toPlainText(), 'B');
    expect(
        nodes[9].attributes[ImageBlockKeys.url], 'https://example.com/img.png');
    expect(editorDocumentToMarkdown(doc), isNot(contains('unwanted')));
  });

  test('HTML handles Apple styled spans, nested wrappers and line breaks', () {
    final nodes = clipboardHtmlToDocument('''<meta charset="utf-8"><div><div>
      <p><span style="font-weight: 700; font-style: italic">Notes</span><br>next</p>
      <pre data-language="bash"><span>echo one</span><br>echo two</pre>
      </div></div>''').root.children.toList();
    expect(nodes.length, 2);
    expect(nodes[0].delta!.toPlainText(), 'Notes\nnext');
    expect(nodes[0].delta!.toJson().first['attributes'],
        {'bold': true, 'italic': true});
    expect(nodes[1].delta!.toPlainText(), 'echo one\necho two');
    expect(nodes[1].attributes['language'], 'bash');
  });

  test('HTML keeps styles on block containers and monospace spans', () {
    final nodes = clipboardHtmlToDocument('<p style="font-weight:700">bold</p>'
            '<p><span style="font-family:Menlo">code</span></p>')
        .root
        .children
        .toList();
    expect(nodes[0].delta!.toJson().first['attributes'], {'bold': true});
    expect(nodes[1].delta!.toJson().first['attributes'], {'code': true});
  });

  test('HTML takes priority over Markdown, replacing an empty paragraph',
      () async {
    final state = editor('');
    await pasteContent(state, html: '<h1>Rich</h1>', text: '# Plain');
    expect(state.document.root.children.single.type, 'heading');
    expect(state.document.first!.delta!.toPlainText(), 'Rich');
    expect(
        state.selection, Selection.collapsed(Position(path: [0], offset: 4)));
    state.undoManager.undo();
    expect(state.document.first!.type, 'paragraph');
    expect(state.document.first!.delta!.isEmpty, isTrue);
  });

  test('rich one-line text pastes inline with formatting', () async {
    final state = editor('before after', offset: 7);
    await pasteContent(state, html: '<p><b>rich</b></p>', text: 'rich');
    expect(state.document.root.children.length, 1);
    expect(state.document.first!.delta!.toPlainText(), 'before richafter');
    expect(state.selection!.end.offset, 11);
  });

  test('blocks go after cursor block and one undo restores selection',
      () async {
    final state = editor('before after', offset: 7);
    final before = state.document.toJson();
    await pasteContent(state, text: '# Title\n\n```dart\nx\n```');
    expect(state.document.root.children.map((n) => n.type),
        ['paragraph', 'heading', 'code']);
    expect(state.document.first!.delta!.toPlainText(), 'before after');
    expect(
        state.selection, Selection.collapsed(Position(path: [2], offset: 1)));
    state.undoManager.undo();
    expect(state.document.toJson(), before);
    expect(
        state.selection, Selection.collapsed(Position(path: [0], offset: 7)));
    state.undoManager.redo();
    expect(state.document.root.children.length, 3);
  });

  test('reversed selection across paragraphs is replaced atomically', () async {
    final state = editor('first\n\nsecond');
    state.selection = Selection(
      start: Position(path: [1], offset: 3),
      end: Position(path: [0], offset: 2),
    );
    final before = state.document.toJson();
    final selection = state.selection;
    await pasteContent(state, text: '- pasted\n- list');
    expect(state.document.first!.delta!.toPlainText(), 'fiond');
    expect(state.document.root.children.map((n) => n.type),
        ['paragraph', 'bulleted_list', 'bulleted_list']);
    state.undoManager.undo();
    expect(state.document.toJson(), before);
    expect(state.selection, selection);
  });

  test('code block paste stays raw, including newlines and Markdown syntax',
      () async {
    final state = editor('```dart\nhello world\n```', offset: 6);
    state.selection = Selection(
        start: Position(path: [0], offset: 6),
        end: Position(path: [0], offset: 11));
    final before = state.document.toJson();
    await pasteContent(state,
        html: '<h1>ignore</h1>', text: '# raw\n- x', mode: PasteMode.markdown);
    expect(state.document.root.children.length, 1);
    expect(state.document.first!.delta!.toPlainText(), 'hello # raw\n- x');
    state.undoManager.undo();
    expect(state.document.toJson(), before);
  });

  test('normal plain paste replaces selection and stays inline', () async {
    final state = editor('hello world');
    state.selection = Selection(
        start: Position(path: [0], offset: 6),
        end: Position(path: [0], offset: 11));
    await pasteContent(state, text: '**literal**');
    expect(state.document.first!.delta!.toPlainText(), 'hello **literal**');
    state.undoManager.undo();
    expect(state.document.first!.delta!.toPlainText(), 'hello world');
  });

  test('explicit Markdown parses inline emphasis, plain mode preserves syntax',
      () async {
    final state = editor('');
    await pasteContent(state, text: '**bold**', mode: PasteMode.markdown);
    expect(state.document.first!.delta!.toPlainText(), 'bold');
    expect(state.document.first!.delta!.toJson().first['attributes'],
        {'bold': true});
    await pasteContent(state, text: '\n# literal', mode: PasteMode.plainText);
    expect(state.document.root.children.last.delta!.toPlainText(), '# literal');
  });

  test('a pasted table gets a valid cursor target and is one undo item',
      () async {
    final state = editor('');
    await pasteContent(state,
        html:
            '<table><tr><td>A</td><td>B</td></tr><tr><td>1</td><td>2</td></tr></table>');
    expect(state.document.root.children.map((n) => n.type),
        ['table', 'paragraph']);
    expect(state.selection, Selection.collapsed(Position(path: [1])));
    state.undoManager.undo();
    expect(state.document.root.children.single.type, 'paragraph');
  });

  test('non-text blocks after a populated cursor get a following paragraph',
      () async {
    final state = editor('existing', offset: 3);
    final before = state.document.toJson();
    await pasteContent(state, html: '<img src="https://example.com/a.png">');
    expect(state.document.root.children.map((n) => n.type),
        ['paragraph', 'image', 'paragraph']);
    expect(state.selection, Selection.collapsed(Position(path: [2])));
    state.undoManager.undo();
    expect(state.document.toJson(), before);
  });

  test('paste stays separate from immediately preceding typing', () async {
    final state = editor('a', offset: 1);
    final typing = state.transaction..insertText(state.document.first!, 1, 'b');
    typing.afterSelection = Selection.collapsed(Position(path: [0], offset: 2));
    await state.apply(typing);
    await pasteContent(state, text: '# Heading');
    state.undoManager.undo();
    expect(state.document.root.children.single.delta!.toPlainText(), 'ab');
    state.undoManager.undo();
    expect(state.document.root.children.single.delta!.toPlainText(), 'a');
  });

  test('metadata-only HTML falls through to Markdown', () async {
    final state = editor('');
    await pasteContent(state,
        html: '<meta charset="utf-8"><!--StartFragment--><!--EndFragment-->',
        text: '# Heading');
    expect(state.document.first!.type, 'heading');
  });

  test('plain shortcut keeps its binding and raw code-block behavior',
      () async {
    expect(chaiPastePlainTextCommand.command,
        pasteTextWithoutFormattingCommand.command);
    expect(pasteAsMarkdownCommand.command,
        isNot(chaiPastePlainTextCommand.command));
    AppFlowyClipboard.mockSetData(
        const AppFlowyClipboardData(text: '# raw\n- line'));
    addTearDown(() => AppFlowyClipboard.mockSetData(null));
    final state = editor('```\ncode\n```', offset: 4);
    chaiPastePlainTextCommand.handler(state);
    await Future<void>.delayed(Duration.zero);
    expect(state.document.root.children.single.type, 'code');
    expect(state.document.first!.delta!.toPlainText(), 'code# raw\n- line');
  });

  test('the sample Markdown retains headings, lists, tables and fences',
      () async {
    final sample = File('samples/kafka-minimum-setup.md').readAsStringSync();
    final state = editor('');
    await pasteContent(state, text: sample);
    final types = state.document.root.children.map((n) => n.type).toSet();
    expect(types, containsAll(['heading', 'code', 'table']));
    expect(
        state.document.root.children
            .where((n) => n.type == 'code')
            .any((n) => n.attributes['language'] == 'bash'),
        isTrue);
    state.undoManager.undo();
    expect(state.document.root.children.single.delta!.isEmpty, isTrue);
  });

  test('native bridge reads HTML and gracefully falls back when unavailable',
      () async {
    const channel = MethodChannel('chai/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    AppFlowyClipboard.mockSetData(const AppFlowyClipboardData(text: '# Plain'));
    addTearDown(() {
      AppFlowyClipboard.mockSetData(null);
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getHtml');
      return '<h2>Native HTML</h2>';
    });
    final state = editor('');
    await pasteFromClipboard(state);
    expect(state.document.first!.delta!.toPlainText(), 'Native HTML');
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'unavailable'));
    final fallback = editor('');
    await pasteFromClipboard(fallback);
    expect(fallback.document.first!.delta!.toPlainText(), 'Plain');
  });
}
