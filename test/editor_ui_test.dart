import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/flutter/scrollable_helpers.dart'
    as editor_scroll;
import 'package:chai_editor/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paste menu parses Markdown and preserves the plain paste option',
      (tester) async {
    AppFlowyClipboard.mockSetData(
        const AppFlowyClipboardData(text: '**bold**'));
    addTearDown(() => AppFlowyClipboard.mockSetData(null));
    await tester.pumpWidget(const ChaiEditorApp());
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

    await tester.pumpWidget(const ChaiEditorApp());
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
