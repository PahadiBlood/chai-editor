import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:chai_editor/code_block.dart';
import 'package:chai_editor/main.dart';
import 'package:chai_editor/paste.dart';
import 'package:chai_editor/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('code colours debounce without changing text, selection or undo',
      (tester) async {
    await tester.pumpWidget(const ChaiEditorApp(enableLibrary: false));
    await tester.pumpAndSettle();
    final state =
        tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editorState;
    state.selection = Selection.collapsed(Position(path: [0]));
    await tester.runAsync(() =>
        pasteContent(state, text: '```dart\nconst x = 42; // comment\n```'));
    await tester.pumpAndSettle();
    final node = state.document.first!;
    expect(node.type, 'code');
    RichText codeText() => tester
        .widgetList<RichText>(find.descendant(
            of: find.byType(CodeBlockComponentWidget),
            matching: find.byType(RichText)))
        .firstWhere((w) => w.text.toPlainText() == node.delta!.toPlainText());
    List<Color?> colors(InlineSpan span) => [
          span.style?.color,
          if (span is TextSpan) ...?span.children?.expand(colors),
        ];
    expect(colors(codeText().text), contains(CodeSyntaxColors.dark.keyword));
    final original = node.delta!.toPlainText();
    final transaction = state.transaction
      ..insertText(node, 0, 'final y = "😀";\n');
    transaction.afterSelection =
        Selection.collapsed(Position(path: [0], offset: 16));
    await tester.runAsync(() => state.apply(transaction));
    await tester.pump();
    final selection = state.selection;
    await tester.pump();
    expect(codeText().text.toPlainText(), 'final y = "😀";\n$original');
    expect(colors(codeText().text),
        isNot(contains(CodeSyntaxColors.dark.keyword)));
    await tester.pump(const Duration(milliseconds: 149));
    expect(colors(codeText().text),
        isNot(contains(CodeSyntaxColors.dark.keyword)));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(colors(codeText().text), contains(CodeSyntaxColors.dark.keyword));
    expect(codeText().text.toPlainText(), node.delta!.toPlainText());
    expect(state.selection, selection);
    state.undoManager.undo();
    await tester.pumpAndSettle();
    expect(node.delta!.toPlainText(), original);
    expect(codeText().text.toPlainText(), original);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'auto label is muted and never writes detected language to Markdown',
      (tester) async {
    await tester.pumpWidget(const ChaiEditorApp(enableLibrary: false));
    await tester.pumpAndSettle();
    final state =
        tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editorState;
    state.selection = Selection.collapsed(Position(path: [0]));
    const text =
        'import json\nfrom pathlib import Path\n\ndef hello(name):\n    # Read a value\n    with open("file.json") as f:\n        data = json.load(f)\n    return {"name": name, "data": data}\n\nif __name__ == "__main__":\n    print(hello("World"))';
    await tester.runAsync(
        () => pasteContent(state, text: text, mode: PasteMode.codeBlock));
    await tester.pumpAndSettle();
    expect(find.text('auto: python'), findsOneWidget);
    expect(tester.widget<Text>(find.text('auto: python')).style?.color,
        AppColors.textMuted);
    expect(state.document.first!.attributes['language'], '');
    await tester.tap(find.byTooltip('Language'));
    await tester.pumpAndSettle();
    expect(find.text('kotlin'), findsOneWidget);
    expect(find.text('rust'), findsOneWidget);
    await tester.tap(find.text('swift'));
    await tester.pumpAndSettle();
    expect(state.document.first!.attributes['language'], 'swift');
    expect(state.document.first!.delta!.toPlainText(), text);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('code Copy button and shortcut use HTML plus fenced Markdown',
      (tester) async {
    const channel = MethodChannel('chai/clipboard');
    Map<dynamic, dynamic>? payload;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      payload = call.arguments as Map;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const ChaiEditorApp(enableLibrary: false));
    await tester.pumpAndSettle();
    final widget = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
    final state = widget.editorState;
    expect(
        widget.commandShortcutEvents
            .where((e) => e.key == copyCommand.key)
            .length,
        1);
    expect(
        widget.commandShortcutEvents
            .where((e) => e.key == cutCommand.key)
            .length,
        1);
    state.selection = Selection.collapsed(Position(path: [0]));
    await tester.runAsync(
        () => pasteContent(state, text: '```dart\nconst x = 42;\n```'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(CodeBlockComponentWidget),
        matching: find.byIcon(Icons.copy_rounded)));
    await tester.pumpAndSettle();
    expect(payload!['text'], '```dart\nconst x = 42;\n```\n');
    expect(payload!['html'], contains('color:#FF7B72'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
