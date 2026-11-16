import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:chai_editor/file_manager.dart';
import 'package:chai_editor/library/library_service.dart';
import 'package:chai_editor/main.dart';
import 'package:chai_editor/toolbar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Picker extends FilePicker {
  final opened = <String?>[];
  final saved = <String?>[];
  int saveCalls = 0;
  @override
  Future<FilePickerResult?> pickFiles(
      {String? dialogTitle,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Function(FilePickerStatus)? onFileLoading,
      bool allowCompression = false,
      int compressionQuality = 0,
      bool allowMultiple = false,
      bool withData = false,
      bool withReadStream = false,
      bool lockParentWindow = false,
      bool readSequential = false}) async {
    final path = opened.removeAt(0);
    return path == null
        ? null
        : FilePickerResult([
            PlatformFile(path: path, name: p.basename(path), size: 0),
          ]);
  }

  @override
  Future<String?> saveFile(
      {String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow = false}) async {
    saveCalls++;
    return saved.removeAt(0);
  }
}

Future<void> finishIO(WidgetTester tester, bool Function() ready) async {
  final elapsed = Stopwatch()..start();
  while (!ready() && elapsed.elapsed < const Duration(seconds: 10)) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'Document operation must finish');
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Picker picker;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('chai-document-workflows-');
    picker = _Picker();
    FilePicker.platform = picker;
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  EditorToolbar toolbar(WidgetTester tester) =>
      tester.widget<EditorToolbar>(find.byType(EditorToolbar));
  EditorState editor(WidgetTester tester) =>
      tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editorState;
  Future<void> start(WidgetTester tester, {bool library = false}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChaiEditorApp(
        enableLibrary: library,
        libraryService: library
            ? LibraryService(Directory(p.join(root.path, 'library')))
            : null));
    await finishIO(
        tester, () => find.byType(AppFlowyEditor).evaluate().isNotEmpty);
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    final state = editor(tester);
    state.selection = Selection.collapsed(Position(path: [0]));
    await state
        .apply(state.transaction..insertText(state.document.first!, 0, text));
    await tester.pump();
  }

  Future<String> file(WidgetTester tester, String name, String content) async {
    final path = p.join(root.path, name);
    await tester.runAsync(() => File(path).writeAsString(content));
    return path;
  }

  testWidgets(
      'open keeps separate files, unsaved buffers and history; reopening selects the existing file',
      (tester) async {
    final first = await file(tester, 'First.md', 'First');
    final second = await file(tester, 'Second.md', 'Second');
    await start(tester);
    await type(tester, 'Draft');
    final draft = editor(tester);
    picker.opened.add(first);
    toolbar(tester).onOpen();
    await finishIO(tester, () => toolbar(tester).activeTab?.filePath == first);
    final firstEditor = editor(tester);
    await type(tester, 'Changed ');
    picker.opened.add(second);
    toolbar(tester).onOpen();
    await finishIO(tester, () => toolbar(tester).activeTab?.filePath == second);
    expect(toolbar(tester).tabs.length, 3);
    expect(firstEditor.document.first!.delta!.toPlainText(), 'Changed First');
    expect(draft.document.first!.delta!.toPlainText(), 'Draft');
    picker.opened.add(first);
    toolbar(tester).onOpen();
    await finishIO(tester, () => identical(editor(tester), firstEditor));
    expect(toolbar(tester).tabs.length, 3);
    await tester.ensureVisible(find.byTooltip('Undo  ⌘Z'));
    await tester.tap(find.byTooltip('Undo  ⌘Z'));
    await tester.pumpAndSettle();
    expect(firstEditor.document.first!.delta!.toPlainText(), 'First');
    await tester.tap(find.byTooltip('Redo  ⇧⌘Z'));
    await tester.pumpAndSettle();
    expect(firstEditor.document.first!.delta!.toPlainText(), 'Changed First');
    expect(await tester.runAsync(() => File(first).readAsString()), 'First');
    await stop(tester);
  });

  testWidgets(
      'Save chooses a path once, reuses it, and Save As adopts the new location',
      (tester) async {
    await start(tester);
    await type(tester, 'First');
    final first = p.join(root.path, 'Chosen');
    picker.saved.add(first);
    toolbar(tester).onSave();
    await finishIO(
        tester, () => toolbar(tester).activeTab?.savePath == '$first.md');
    expect(picker.saveCalls, 1);
    expect(await tester.runAsync(() => File('$first.md').readAsString()),
        'First\n');
    await type(tester, 'Changed ');
    toolbar(tester).onSave();
    await finishIO(tester, () => !toolbar(tester).activeTab!.needsSave);
    expect(picker.saveCalls, 1);
    expect(await tester.runAsync(() => File('$first.md').readAsString()),
        'Changed First\n');
    final other = p.join(root.path, 'Other.md');
    picker.saved.add(other);
    toolbar(tester).onSaveAs();
    await finishIO(tester, () => toolbar(tester).activeTab?.savePath == other);
    await type(tester, 'Again ');
    toolbar(tester).onSave();
    await finishIO(tester, () => !toolbar(tester).activeTab!.needsSave);
    expect(picker.saveCalls, 2);
    expect(await tester.runAsync(() => File(other).readAsString()),
        'Again Changed First\n');
    expect(await tester.runAsync(() => File('$first.md').readAsString()),
        'Changed First\n');
    await stop(tester);
  });

  testWidgets(
      'closing unsaved files supports Cancel, cancelled Save, Save and Discard',
      (tester) async {
    await start(tester);
    await type(tester, 'Unsaved');
    final original = toolbar(tester).activeTab!;
    toolbar(tester).onCloseTab();
    await tester.pumpAndSettle();
    expect(find.text('Save changes to Untitled?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(toolbar(tester).activeTab, original);
    picker.saved.add(null);
    toolbar(tester).onCloseTab();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(toolbar(tester).activeTab, original);
    expect(original.needsSave, true);
    final path = p.join(root.path, 'Saved.md');
    picker.saved.add(path);
    toolbar(tester).onCloseTab();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await finishIO(tester, () => !toolbar(tester).tabs.contains(original));
    expect(await tester.runAsync(() => File(path).readAsString()), 'Unsaved\n');
    picker.opened.add(path);
    toolbar(tester).onOpen();
    await finishIO(tester, () => toolbar(tester).activeTab?.filePath == path);
    await type(tester, 'Discard this ');
    toolbar(tester).onCloseTab();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => File(path).readAsString()), 'Unsaved\n');
    await stop(tester);
  });

  testWidgets(
      'library Save opens a destination dialog and later saves update that file',
      (tester) async {
    await start(tester, library: true);
    final destination = p.join(root.path, 'My note.md');
    final tab = toolbar(tester).activeTab!;
    await type(tester, 'Added ');
    picker.saved.add(destination);
    toolbar(tester).onSave();
    await finishIO(tester, () => tab.savePath == destination);
    expect(picker.saveCalls, 1);
    await type(tester, 'Updated ');
    toolbar(tester).onSave();
    await finishIO(tester, () => !tab.needsSave);
    expect(picker.saveCalls, 1);
    expect(await tester.runAsync(() => File(destination).readAsString()),
        contains('Updated Added'));
    expect(tab.libraryManaged, true);
    await stop(tester);
  });

  testWidgets(
      'external sidebar removal keeps the original and file-manager action sends its exact path',
      (tester) async {
    final path = await file(tester, 'Name with spaces.md', 'original');
    await start(tester, library: true);
    picker.opened.add(path);
    toolbar(tester).onOpen();
    await finishIO(tester, () => toolbar(tester).activeTab?.filePath == path);
    const channel = MethodChannel('chai/files');
    Map<dynamic, dynamic>? revealed;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'reveal');
      revealed = call.arguments as Map;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final row = find.widgetWithText(ListTile, 'Name with spaces.md');
    await tester.tap(row, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(fileManagerLabel()));
    await finishIO(tester, () => revealed != null);
    expect(revealed, {'path': path, 'directory': false});
    await tester.tap(find.descendant(
        of: row, matching: find.byTooltip('Remove from editor')));
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    expect(await tester.runAsync(() => File(path).readAsString()), 'original');
    await stop(tester);
  });
}
