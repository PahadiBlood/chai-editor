import 'dart:convert';
import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:chai_editor/library/library_model.dart';
import 'package:chai_editor/library/library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('more than eight opened notes retain their editor and undo history',
      () async {
    final root = await Directory.systemTemp.createTemp('chai-sessions-');
    final model = LibraryModel(LibraryService(root));
    addTearDown(() async {
      model.dispose();
      await root.delete(recursive: true);
    });
    await model.initialize();
    final first = model.current!;
    final original = first.toMarkdown();
    final state = first.editorState;
    state.selection = Selection.collapsed(Position(path: [0]));
    await state.apply(
        state.transaction..insertText(state.document.first!, 0, 'Changed '));
    for (var i = 0; i < 10; i++) {
      final path = await model.service.create(root.path, name: 'Note $i');
      await model.open(path);
    }
    expect(model.openTabs.length, 11);
    await model.open(first.filePath!);
    expect(identical(model.current, first), true);
    state.undoManager.undo();
    expect(first.toMarkdown(), original);
    await model.flush();
  });

  test(
      'removing a folder preserves disk contents and portable state across restart',
      () async {
    final root = await Directory.systemTemp.createTemp('chai-removal-');
    final service = LibraryService(root);
    final model = LibraryModel(service);
    await model.initialize();
    final note = model.current!;
    final path = note.filePath!;
    final folder = p.dirname(path);
    final before = await File(path).readAsString();
    model.holdAutosaves([note]);
    await note.editorState.apply(note.editorState.transaction
      ..insertText(note.editorState.document.first!, 0, 'Discarded '));
    note.discardPendingChanges();
    await model.removeFromEditor(folder);
    model.resumeAutosaves([note]);
    expect(model.entries, isEmpty);
    expect(model.openTabs, isEmpty);
    expect(await File(path).readAsString(), before);
    expect(await service.trash(), isEmpty);
    final json =
        jsonDecode(await File(service.statePath).readAsString()) as Map;
    expect(json['removed'], ['Notes']);
    expect(json.toString(), isNot(contains(root.path)));
    model.dispose();
    final reopened = LibraryModel(service);
    await reopened.initialize();
    expect(reopened.entries, isEmpty);
    expect(await File(path).readAsString(), before);
    await reopened.showRemovedItems();
    expect(reopened.entries.single.path, folder);
    await reopened.open(path);
    expect(reopened.current!.toMarkdown(), contains('Welcome'));
    reopened.dispose();
    await root.delete(recursive: true);
  });
}
