import 'package:appflowy_editor/appflowy_editor.dart';
import 'dart:io';

import 'package:chai_editor/library/library_model.dart';
import 'package:chai_editor/library/library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('library autosave waits five seconds after the last edit', () {
    expect(kLibraryAutosaveDelay, const Duration(seconds: 5));
  });

  test(
      'immediate exit flush and restart restore content, paths and sidebar state',
      () async {
    final root = await Directory.systemTemp.createTemp('chai-model-');
    final model = LibraryModel(LibraryService(root));
    await model.initialize();
    final editor = model.current!.editorState;
    await editor.apply(editor.transaction
      ..insertText(editor.document.first!, 0, 'Immediately saved '));
    model.width = 315;
    model.hidden = true;
    final open = model.current!.filePath!;
    final selected = p.dirname(open);
    model.selected = selected;
    model.expanded.clear();
    await model.flush();
    await model.saveState();
    model.dispose();
    final reopened = LibraryModel(LibraryService(root));
    await reopened.initialize();
    expect(reopened.current!.toMarkdown(), contains('Immediately saved'));
    expect(reopened.current!.filePath, open);
    expect(reopened.selected, open);
    expect(reopened.expanded, contains(selected));
    expect(reopened.width, 315);
    expect(reopened.hidden, true);
    reopened.dispose();
    await root.delete(recursive: true);
  });

  test(
      'renaming or moving a parent updates the open note and autosave destination',
      () async {
    final root = await Directory.systemTemp.createTemp('chai-model-');
    final model = LibraryModel(LibraryService(root));
    await model.initialize();
    final parent = p.dirname(model.current!.filePath!);
    await model.rename(parent, 'Renamed');
    expect(model.current!.filePath, p.join(root.path, 'Renamed', 'Welcome.md'));
    final destination =
        await model.service.create(root.path, folder: true, name: 'Outer');
    await model.move(p.dirname(model.current!.filePath!), destination);
    final editor = model.current!.editorState;
    await editor.apply(
        editor.transaction..insertText(editor.document.first!, 0, 'Moved '));
    await model.flush();
    expect(
        await File(model.current!.filePath!).readAsString(), contains('Moved'));
    model.dispose();
    await root.delete(recursive: true);
  });
}
