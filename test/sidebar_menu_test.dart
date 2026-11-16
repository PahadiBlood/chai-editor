import 'dart:io';
import 'package:chai_editor/library/library_model.dart';
import 'package:chai_editor/library/library_service.dart';
import 'package:chai_editor/theme.dart';
import 'package:chai_editor/widgets/sidebar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('secondary clicks open note, folder, empty-space and trash menus',
      (tester) async {
    late Directory root;
    late LibraryModel model;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('chai-menu-');
      model = LibraryModel(LibraryService(root));
      await model.initialize();
    });
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
            body: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                    width: 300,
                    child: ChangeNotifierProvider.value(
                        value: model,
                        child:
                            LibrarySidebar(onOpen: (_) {}, onHide: () {})))))));
    await tester.pumpAndSettle();
    final open = model.openNote;
    await tester.tap(find.text('Welcome'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    for (final name in [
      'Open',
      'Rename',
      'Duplicate',
      'Move to',
      'Export',
      'Show in Finder',
      'Delete'
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(model.openNote, open);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Welcome'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(model.openNote, open);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('New Note'), findsOneWidget);
    expect(find.text('New Folder'), findsOneWidget);
    expect(find.text('Move to'), findsOneWidget);
    await tester.tap(find.byTooltip('Move to'));
    await tester.pumpAndSettle();
    expect(find.text('On My Mac'), findsNWidgets(2));
    final self = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Notes').last);
    expect(self.enabled, false);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(150, 400), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('New Note'), findsOneWidget);
    expect(find.text('New Folder'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.runAsync(() => model.delete(open!));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently Deleted'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Welcome'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Delete Permanently'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently Deleted').last,
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Empty'), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
