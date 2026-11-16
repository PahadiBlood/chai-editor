import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:chai_editor/library/library_location.dart';
import 'package:chai_editor/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> finishIO(WidgetTester tester, bool Function() ready) async {
  // Real filesystem work competes with the rest of the suite. Wait for actual
  // readiness before settling; a loading spinner cannot settle under fake time.
  final elapsed = Stopwatch()..start();
  while (!ready() && elapsed.elapsed < const Duration(seconds: 10)) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'Storage setup must finish before settling');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'storage failure hides private paths and asks before using local app storage',
      (tester) async {
    final root = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('chai-recovery-ui-')))!;
    final location = LibraryLocation(
      documentsDirectory: () async => throw const FileSystemException(
          'Permission denied',
          '/private-account/unavailable',
          OSError('Permission denied', 13)),
      supportDirectory: () async => Directory(p.join(root.path, 'support')),
    );
    await tester.pumpWidget(ChaiEditorApp(libraryLocation: location));
    await finishIO(
        tester, () => find.text('Use app storage').evaluate().isNotEmpty);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(AppFlowyEditor), findsNothing);
    expect(find.textContaining('/private-account'), findsNothing);
    expect(find.textContaining('FileSystemException'), findsNothing);
    await tester.runAsync(() async {
      expect(
          await File(p.join(root.path, 'support', 'library-location.json'))
              .exists(),
          false);
    });
    await tester.tap(find.text('Use app storage'));
    await finishIO(
        tester, () => find.byType(AppFlowyEditor).evaluate().isNotEmpty);
    expect(find.byType(AppFlowyEditor), findsOneWidget);
    await tester.runAsync(() async {
      expect(
          await File(p.join(
                  root.path, 'support', 'ChaiEditor', 'Notes', 'Welcome.md'))
              .exists(),
          true);
      expect((await location.resolve()).root,
          p.join(root.path, 'support', 'ChaiEditor'));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
