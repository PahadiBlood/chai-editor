import 'dart:convert';
import 'dart:io';

import 'package:chai_editor/library/atomic_file.dart';
import 'package:chai_editor/library/library_location.dart';
import 'package:chai_editor/library/library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final target = p.join(destination.path, p.basename(entity.path));
    if (entity is File) await entity.copy(target);
    if (entity is Directory) await copyDirectory(entity, Directory(target));
  }
}

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('chai-portable-');
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
      'write recreates a parent removed between mkdir and opening the temporary file',
      () async {
    final target = p.join(temporary.path, 'library', '.chai', 'state.json');
    var attempts = 0;
    final writer =
        AtomicFileWriter(afterParentCreated: (parent, attempt) async {
      attempts++;
      if (attempt == 0) await parent.delete(recursive: true);
    });
    await writer.write(target, 'complete');
    expect(attempts, 2);
    expect(await File(target).readAsString(), 'complete');
    expect((await Directory(p.dirname(target)).list().toList()).length, 1);
  });

  test(
      'overlapping writes finish in submission order without temporary file leftovers',
      () async {
    final target = p.join(temporary.path, 'state.json');
    final writer = AtomicFileWriter();
    await Future.wait(
        [for (var i = 0; i < 30; i++) writer.write(target, '$i')]);
    expect(await File(target).readAsString(), '29');
    expect((await temporary.list().toList()).length, 1);
  });

  test('permission failure keeps existing content and does not loop retries', () async {
    final file = File(p.join(temporary.path, 'note.md'));
    await file.writeAsString('original text');
    var attempts = 0;
    final writer = AtomicFileWriter(afterParentCreated: (_, __) async {
      attempts++;
      throw FileSystemException('Permission denied', file.path, const OSError('Permission denied', 13));
    });
    await expectLater(writer.write(file.path, 'replacement'), throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), 'original text');
    expect(attempts, 1);
  });

  test('an unavailable preference directory does not block an available Documents library', () async {
    final documents = Directory(p.join(temporary.path, 'documents'));
    final location = LibraryLocation(documentsDirectory: () async => documents,
      supportDirectory: () async => throw StateError('Platform preference directory unavailable'));
    expect((await location.resolve()).root, p.join(documents.path, 'ChaiEditor'));
  });

  test(
      'sidebar state and trash restore correctly after a library is copied to another root',
      () async {
    final original = LibraryService(
        Directory(p.join(temporary.path, 'person-one', 'ChaiEditor')));
    await original.initialize();
    final folder = (await original.tree()).single.path;
    final note = await original.create(folder, name: 'Portable');
    await original.writeNote(note, 'keep this text');
    await original.writeState({
      'open': note,
      'selected': note,
      'expanded': [folder],
      'width': 310,
      'hidden': true
    });
    final trashed = await original.create(folder, name: 'Restore me');
    await original.writeNote(trashed, 'trash text');
    await original.delete(trashed);
    expect(await File(original.statePath).readAsString(),
        isNot(contains(original.root)));
    expect(await File(p.join(original.trashPath, 'index.json')).readAsString(),
        isNot(contains(original.root)));
    final destination =
        Directory(p.join(temporary.path, 'different-person', 'copied-notes'));
    await copyDirectory(Directory(original.root), destination);
    final reopened = LibraryService(destination);
    await reopened.initialize();
    final state = await reopened.readState();
    expect(state['open'], p.join(destination.path, 'Notes', 'Portable.md'));
    expect(state['expanded'], [p.join(destination.path, 'Notes')]);
    expect(state['width'], 310);
    final restored = await reopened.restore((await reopened.trash()).single);
    expect(restored, p.join(destination.path, 'Notes', 'Restore me.md'));
    expect(await reopened.readNote(restored), 'trash text');
  });

  test(
      'legacy local absolute paths migrate; invalid state types and foreign paths fall back safely',
      () async {
    final library = LibraryService(temporary);
    await library.initialize();
    final note = (await library.tree()).single.children.single.path;
    await File(library.statePath).writeAsString(jsonEncode({
      'open': note,
      'selected': note,
      'expanded': [p.dirname(note)]
    }));
    expect((await library.readState())['open'], note);
    await File(library.statePath).writeAsString(jsonEncode({
      'open': '/another-account/secret.md',
      'expanded': 'wrong type',
      'width': 'wide'
    }));
    final state = await library.readState();
    expect(state['open'], null);
    expect(state['expanded'], isEmpty);
    expect(state['width'], 260);
    await File(library.statePath).writeAsString('[]');
    expect(await library.readState(), isEmpty);
    await Directory(p.dirname(library.statePath)).delete(recursive: true);
    expect(await library.readState(), isEmpty);
    await library.writeState({'open': note});
    expect(await File(library.statePath).exists(), true);
  });

  test(
      'default location follows OS directories; only explicit app-storage choice changes future launches',
      () async {
    final documents = Directory(p.join(temporary.path, 'my-documents'));
    final support = Directory(p.join(temporary.path, 'my-app-data'));
    final location = LibraryLocation(
        documentsDirectory: () async => documents,
        supportDirectory: () async => support);
    expect(
        (await location.resolve()).root, p.join(documents.path, 'ChaiEditor'));
    await location.rememberAppStorage();
    final preference = await File(p.join(support.path, 'library-location.json'))
        .readAsString();
    expect(preference, isNot(contains(temporary.path)));
    expect((await location.resolve()).root, p.join(support.path, 'ChaiEditor'));
    expect(await documents.exists(),
        false); // No migration or copying was performed.
  });
}
