import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:chai_editor/clipboard_html.dart';
import 'package:chai_editor/clipboard_writer.dart';
import 'package:chai_editor/code_block.dart';
import 'package:chai_editor/markdown_io.dart';
import 'package:chai_editor/paste.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('chai/clipboard');
  EditorState editor(String markdown) {
    final state = EditorState(document: markdownToEditorDocument(markdown))
      ..selection = Selection.collapsed(Position(path: [0]));
    addTearDown(state.dispose);
    return state;
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
      'styled editor divs, block code and pre-wrap spans become one code block',
      () {
    final fixtures = [
      '<div style="font-family:Menlo" data-language="js"><div><span>const x = 1;</span></div><div>&nbsp;&nbsp;run();</div></div>',
      '<div style="white-space: pre-wrap !important" class="hljs js">const x = 1;<br>&nbsp;&nbsp;run();</div>',
      '<code style="display:block" class="lang-js">const x = 1;<br>&nbsp;&nbsp;run();</code>',
      '<span style="white-space:pre" data-language="javascript">const x = 1;\n  run();</span>',
    ];
    for (final html in fixtures) {
      final nodes = clipboardHtmlToDocument(html).root.children;
      expect(nodes.length, 1, reason: html);
      expect(nodes.single.type, 'code');
      expect(nodes.single.delta!.toPlainText(), 'const x = 1;\n  run();');
      expect(nodes.single.attributes['language'], 'javascript');
    }
    for (final family in [
      'Monaco',
      'Consolas',
      'Courier New',
      'SF Mono',
      'JetBrains Mono',
      'Fira Code',
      'monospace'
    ]) {
      expect(
          clipboardHtmlToDocument('<div style="font-family:$family">x</div>')
              .first!
              .type,
          'code');
    }
  });

  test('line-number columns are discarded while tabs and blank lines survive',
      () {
    final node = clipboardHtmlToDocument(
            '<div style="font-family:monospace"><div><span class="line-number">1</span>\tstart</div><div><br></div><div><span class="lineno">3</span>  end</div></div>')
        .first!;
    expect(node.delta!.toPlainText(), '\tstart\n\n  end');
    final table = clipboardHtmlToDocument(
            '<table><tr><td class="blob-num">1</td><td class="blob-code">one</td></tr><tr><td class="blob-num">2</td><td class="blob-code">  two</td></tr></table>')
        .first!;
    expect(table.type, 'code');
    expect(table.delta!.toPlainText(), 'one\n  two');
  });

  test('HTML code wrappers keep every line, source newline and code child', () {
    for (final html in [
      '<div style="font-family:SFMono-Regular"><div><code>one</code></div><div><code>two</code></div></div>',
      '<p><code style="display:block">one<br>two</code></p>',
      '<div style="font-family:monospace"><table><tr><td class="hljs-ln-line hljs-ln-numbers">1</td><td class="hljs-ln-line hljs-ln-code">one</td></tr><tr><td class="hljs-ln-line hljs-ln-numbers">2</td><td class="hljs-ln-line hljs-ln-code">two</td></tr></table></div>',
    ]) {
      final node = clipboardHtmlToDocument(html).first!;
      expect(node.type, 'code', reason: html);
      expect(node.delta!.toPlainText(), 'one\ntwo', reason: html);
    }
    final node =
        clipboardHtmlToDocument('<pre><code>  one\n\n</code></pre>').first!;
    expect(node.delta!.toPlainText(), '  one\n\n');
    expect(
        clipboardHtmlToDocument('<body style="white-space:pre">a\nb</body>')
            .first!
            .type,
        'code');
  });

  test('inline code and normal prose remain inline and grey', () {
    final node = clipboardHtmlToDocument(
            '<p>Run <code>x()</code> and <span style="font-family:Menlo">y()</span>.</p>')
        .first!;
    expect(node.type, 'paragraph');
    expect(node.delta!.toPlainText(), 'Run x() and y().');
    expect(
        node.delta!
            .toJson()
            .where((op) => op['attributes']?['code'] == true)
            .length,
        2);
  });

  test(
      'code HTML has escaped inline token colours and round-trips trailing newlines',
      () {
    const code = 'const x = "<&😀";\n\t// comment\n\n';
    final doc = Document(
        root: Node(
            type: 'page',
            children: [codeBlockNode(text: code, language: 'dart')]));
    final html = documentClipboardHtml(doc);
    expect(html, contains('color:#FF7B72'));
    expect(html, contains('font-style:italic'));
    expect(html, contains('&lt;&amp;'));
    expect(html, isNot(contains('<style>')));
    final pasted = clipboardHtmlToDocument(html).first!;
    expect(pasted.type, 'code');
    expect(pasted.attributes['language'], 'dart');
    expect(pasted.delta!.toPlainText(), code);
  });

  test(
      'rich document copy preserves headings, emphasis, nested lists, links and tables',
      () {
    final doc = markdownToEditorDocument(
        '# Title\n\n**bold** *italic* [link](https://example.com)\n\n- parent\n   - child\n\n1. numbered\n\n- [x] done\n\n| A | B |\n|---|---|\n| 1 | 2 |');
    final html = documentClipboardHtml(doc);
    final roundTrip = clipboardHtmlToDocument(html);
    expect(editorDocumentToMarkdown(roundTrip), editorDocumentToMarkdown(doc));
  });

  test(
      'explicit code paste replaces selection in one undo; code destination stays raw',
      () async {
    final state = editor('before');
    state.selection = Selection.single(path: [0], startOffset: 0, endOffset: 6);
    final before = state.document.toJson();
    await pasteContent(state,
        text: '\tplain\n  code', mode: PasteMode.codeBlock);
    expect(state.document.first!.type, 'code');
    expect(state.document.first!.delta!.toPlainText(), '\tplain\n  code');
    state.undoManager.undo();
    expect(state.document.toJson(), before);
    final codeState = editor('```dart\nx\n```');
    codeState.selection = Selection.collapsed(Position(path: [0], offset: 1));
    await pasteContent(codeState,
        text: '# literal\n- literal',
        html: '<pre>converted</pre>',
        mode: PasteMode.codeBlock);
    expect(codeState.document.root.children.length, 1);
    expect(codeState.document.first!.delta!.toPlainText(),
        'x# literal\n- literal');
    expect(pasteAsCodeBlockCommand.command, contains('+alt+v'));
    expect(pasteAsCodeBlockCommand.command,
        isNot(chaiPastePlainTextCommand.command));
    expect(
        pasteAsCodeBlockCommand.command, isNot(pasteAsMarkdownCommand.command));
  });

  test('copy uses native plain Markdown and HTML for exactly the selected code',
      () async {
    Map<dynamic, dynamic>? payload;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setClipboard');
      payload = call.arguments as Map;
      return true;
    });
    final state = editor('```dart\nconst x = 42;\n```');
    final before = state.document.toJson();
    state.selection =
        Selection.single(path: [0], startOffset: 6, endOffset: 12);
    await copyEditorSelection(state);
    expect(payload!['text'], '```dart\nx = 42\n```\n');
    expect(
        clipboardHtmlToDocument(payload!['html'] as String)
            .first!
            .delta!
            .toPlainText(),
        'x = 42');
    expect(state.document.toJson(), before);
  });

  test('cut waits for clipboard success and is one undo action', () async {
    final ready = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (_) => ready.future);
    final state = editor('abcdef');
    state.selection = Selection.single(path: [0], startOffset: 1, endOffset: 4);
    final before = state.document.toJson();
    final pending = copyEditorSelection(state, cut: true);
    await Future<void>.delayed(Duration.zero);
    expect(state.document.toJson(), before);
    ready.complete(true);
    await pending;
    expect(state.document.first!.delta!.toPlainText(), 'aef');
    state.undoManager.undo();
    expect(state.document.toJson(), before);
  });

  test(
      'cut cannot delete after a selection/document changes or a failed clipboard',
      () async {
    final ready = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (_) => ready.future);
    final state = editor('abcdef');
    state.selection = Selection.single(path: [0], startOffset: 1, endOffset: 4);
    final pending = copyEditorSelection(state, cut: true);
    state.selection = Selection.collapsed(Position(path: [0]));
    ready.complete(true);
    await pending;
    expect(state.document.first!.delta!.toPlainText(), 'abcdef');
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'failed'));
    messenger.setMockMethodCallHandler(SystemChannels.platform,
        (_) async => throw PlatformException(code: 'failed'));
    state.selection = Selection.single(path: [0], startOffset: 0, endOffset: 2);
    await expectLater(copyEditorSelection(state, cut: true),
        throwsA(isA<PlatformException>()));
    expect(state.document.first!.delta!.toPlainText(), 'abcdef');
  });

  test('older runners fall back to plain Markdown clipboard', () async {
    String? plain;
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw MissingPluginException());
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        plain = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await writeDocumentClipboard(
        markdownToEditorDocument('```bash\necho hi\n```'));
    expect(plain, '```bash\necho hi\n```\n');
  });
  test('reversed mixed-block copy and cut clip text and retain code fences',
      () async {
    Map<dynamic, dynamic>? payload;
    messenger.setMockMethodCallHandler(channel, (call) async {
      payload = call.arguments as Map;
      return true;
    });
    final state = editor('# Alpha\n\n```dart\nconst x = 42;\n```\n\nOmega');
    state.selection = Selection(
        start: Position(path: [2], offset: 2),
        end: Position(path: [0], offset: 2));
    final before = state.document.toJson();
    await copyEditorSelection(state, cut: true);
    expect(payload!['text'], '# pha\n\n```dart\nconst x = 42;\n```\n\nOm\n');
    expect(
        clipboardHtmlToDocument(payload!['html'] as String)
            .root
            .children
            .map((n) => n.type),
        ['heading', 'code', 'paragraph']);
    expect(state.document.root.children.single.delta!.toPlainText(), 'Alega');
    state.undoManager.undo();
    expect(state.document.toJson(), before);
  });

  test('cut cannot delete after content changes while selection is unchanged',
      () async {
    final ready = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (_) => ready.future);
    final state = editor('abcdef');
    state.selection = Selection.single(path: [0], startOffset: 1, endOffset: 4);
    final pending = copyEditorSelection(state, cut: true);
    await state.apply(
        state.transaction..insertText(state.document.first!, 6, '!'),
        withUpdateSelection: false);
    ready.complete(true);
    await pending;
    expect(state.document.first!.delta!.toPlainText(), 'abcdef!');
  });
  test(
      'a null native result requires a confirmed plain clipboard fallback before cut',
      () async {
    String? copied;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    final state = editor('abcdef');
    state.selection = Selection.single(path: [0], startOffset: 1, endOffset: 4);
    await copyEditorSelection(state, cut: true);
    expect(copied, 'bcd\n');
    expect(state.document.first!.delta!.toPlainText(), 'aef');
  });
}
