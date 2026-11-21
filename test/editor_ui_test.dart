import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/flutter/scrollable_helpers.dart'
    as editor_scroll;
import 'package:chai_editor/main.dart';
import 'package:chai_editor/paste.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('document prose is tighter while inline code keeps its spacing',
      (tester) async {
    await tester.pumpWidget(const ChaiEditorApp(enableLibrary: false));
    await tester.pumpAndSettle();
    final editor = find.byType(AppFlowyEditor);
    final state = tester.widget<AppFlowyEditor>(editor).editorState;
    state.selection = Selection.collapsed(Position(path: [0]));
    await tester.runAsync(() => pasteContent(state,
        text: 'A short line `x + y`', mode: PasteMode.markdown));
    await tester.pumpAndSettle();

    final text = tester
        .widgetList<RichText>(
            find.descendant(of: editor, matching: find.byType(RichText)))
        .firstWhere(
            (widget) => widget.text.toPlainText() == 'A short line x + y')
        .text;
    final styles = <String, TextStyle?>{};
    text.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        styles[span.text!] = span.style;
      }
      return true;
    });
    expect(styles['A short line ']?.letterSpacing, lessThan(0));
    expect(styles['A short line ']?.wordSpacing, lessThan(0));
    expect(styles['x + y']?.letterSpacing, 0);
    expect(styles['x + y']?.wordSpacing, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('text style menu preserves the selection and applies a heading',
      (tester) async {
    await tester.pumpWidget(const ChaiEditorApp(enableLibrary: false));
    await tester.pumpAndSettle();
    final editor = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
    final state = editor.editorState;
    await state.apply(
        state.transaction..insertText(state.document.first!, 0, 'Title'));
    editor.focusNode!.requestFocus();
    final selection = Selection(
      start: Position(path: [0], offset: 0),
      end: Position(path: [0], offset: 5),
    );
    state.selection = selection;
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Text style'));
    await tester.pumpAndSettle();
    expect(state.selection, selection);
    await tester.tap(find.text('Heading 2'));
    await tester.pumpAndSettle();

    final heading = state.document.first!;
    expect(heading.type, HeadingBlockKeys.type);
    expect(heading.attributes[HeadingBlockKeys.level], 2);
    expect(heading.delta!.toPlainText(), 'Title');
    expect(state.selection, selection);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('paste menu parses Markdown and preserves the plain paste option',
      (tester) async {
    AppFlowyClipboard.mockSetData(
        const AppFlowyClipboardData(text: '**bold**'));
    addTearDown(() => AppFlowyClipboard.mockSetData(null));
    await tester.pumpWidget(const ChaiEditorApp(enableLibrary: false));
    await tester.pumpAndSettle();
    final state =
        tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editorState;
    state.selection = Selection.collapsed(Position(path: [0]));
    await tester.ensureVisible(find.byTooltip('Insert'));
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    expect(find.text('Paste as plain text    ⌘⇧V'), findsOneWidget);
    await tester.tap(find.text('Paste as Markdown    ⌘⌥⇧V'));
    await tester.pumpAndSettle();
    expect(state.document.first!.delta!.toPlainText(), 'bold');
    expect(state.document.first!.delta!.toJson().first['attributes'],
        {'bold': true});
    AppFlowyClipboard.mockSetData(
        const AppFlowyClipboardData(text: '# literal'));
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste as plain text    ⌘⇧V'));
    await tester.pumpAndSettle();
    expect(state.document.first!.delta!.toPlainText(), 'bold# literal');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('editor renders and switches tabs without framework errors',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ChaiEditorApp(enableLibrary: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Bold  ⌘B'), findsOneWidget);
    expect(find.byTooltip('Bulleted list'), findsOneWidget);

    await tester.tap(find.byTooltip('Tabs and file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tab        ⌘N'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Tabs and file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Untitled').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'toolbar keeps file actions in one menu and avoids duplicate inserts',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ChaiEditorApp(enableLibrary: false));
    await tester.pumpAndSettle();

    // Open, Save and Save As live in the document-name menu, not as repeated
    // right-side icons. Table and image have their own direct buttons.
    expect(find.byTooltip('Open  ⌘O'), findsNothing);
    expect(find.byTooltip('Save  ⌘S'), findsNothing);
    await tester.tap(find.byTooltip('Tabs and file'));
    await tester.pumpAndSettle();
    expect(find.text('Open…        ⌘O'), findsOneWidget);
    expect(find.text('Save        ⌘S'), findsOneWidget);
    expect(find.text('Save as…        ⇧⌘S'), findsOneWidget);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();
    expect(find.text('New Note'), findsNothing);
    expect(find.text('Save As…'), findsNothing);
    expect(find.text('Table'), findsNothing);
    expect(find.text('Image…'), findsNothing);
    expect(find.text('Code block'), findsOneWidget);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Quote'), findsOneWidget);
    await tester.tap(find.byTooltip('Text style'));
    await tester.pumpAndSettle();
    expect(find.text('Quote'), findsNothing);
    expect(find.text('Code block'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'instant auto-scroll yields and can be stopped on a long document',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        controller: controller,
        child: const SizedBox(height: 2000000),
      ),
    ));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final scroller = editor_scroll.EdgeDraggingAutoScroller(
      scrollable,
      velocityScalar: 7,
    );
    scroller.startAutoScrollIfNecessary(
      const Rect.fromLTWH(0, 1000, 10, 10),
      duration: Duration.zero,
    );
    expect(controller.offset, 20);
    expect(scroller.scrolling, isTrue);
    await tester.pump();
    expect(controller.offset, greaterThan(20));
    scroller.stopAutoScroll();
    final stoppedOffset = controller.offset;
    await tester.pumpAndSettle();
    expect(controller.offset, stoppedOffset);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
