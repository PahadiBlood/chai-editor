import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:chai_editor/library/library_service.dart';
import 'package:chai_editor/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'responsive library renders at phone and desktop widths and exit awaits saving',
      (tester) async {
    final root = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('chai-ui-')))!;
    final service = LibraryService(root);
    await tester.runAsync(service.initialize);
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChaiEditorApp(libraryService: service));
    // Filesystem work must run outside fake async.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      if (find.text('Welcome').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.text('On My Mac'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);
    final state =
        tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editorState;
    await state.apply(state.transaction
      ..insertText(state.document.first!, 0, 'Saved on exit '));
    AppExitResponse? response;
    tester.binding.handleRequestAppExit().then((value) => response = value);
    for (var i = 0; i < 100 && response == null; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
    }
    expect(response, AppExitResponse.exit);
    await tester.runAsync(() async {
      final note = (await service.tree()).single.children.single;
      expect(await service.readNote(note.path), contains('Saved on exit'));
    });
    for (final width in [320.0, 390.0, 600.0, 800.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
