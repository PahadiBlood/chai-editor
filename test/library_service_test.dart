import 'dart:convert';
import 'dart:io';

import 'package:chai_editor/library/library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late LibraryService service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chai-library-test-');
    service = LibraryService(directory);
    await service.initialize();
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
      'first launch creates Notes/Welcome and subsequent launches preserve files',
      () async {
    expect((await service.tree()).single.name, 'Notes');
    final welcome = (await service.tree()).single.children.single;
    expect(await service.readNote(welcome.path), contains('Welcome'));
    await service.initialize();
    expect((await service.tree()).single.children.length, 1);
  });
  test(
      'create, nested folders, counts, folders-first and case-insensitive ordering',
      () async {
    final root = await service.create(service.root, folder: true, name: 'Work');
    final sub = await service.create(root, folder: true, name: 'zSub');
    await service.create(root, name: 'Beta');
    await service.create(root, name: 'alpha');
    await service.create(sub, name: 'nested');
    final work = (await service.tree()).firstWhere((e) => e.name == 'Work');
    expect(work.noteCount, 3);
    expect(work.children.map((e) => e.name), ['zSub', 'alpha', 'Beta']);
  });
  test('rename note and folder keeps text and physical paths', () async {
    final folder =
        await service.create(service.root, folder: true, name: 'One');
    final note = await service.create(folder, name: 'Original');
    await service.writeNote(note, 'content');
    final renamed = await service.rename(note, 'Renamed');
    expect(await File(note).exists(), false);
    expect(await service.readNote(renamed), 'content');
    final moved = await service.rename(folder, 'Two');
    expect(await service.readNote(p.join(moved, 'Renamed.md')), 'content');
  });
  test('rename cleans names, numbers clashes and leaves empty names unchanged',
      () async {
    final note = await service.create(service.root, name: 'Name');
    final second = await service.create(service.root, name: 'name');
    expect(p.basename(second), 'name 2.md');
    expect(await service.rename(note, '   '), note);
    final cleaned = await service.rename(note, '.bad/name:here');
    expect(p.basename(cleaned), 'bad name here.md');
    final third = await service.create(service.root, name: 'name');
    expect(p.basename(third), 'name.md');
  });
  test(
      'moves notes, duplicates content, rejects drops into self and descendants',
      () async {
    final folder =
        await service.create(service.root, folder: true, name: 'Folder');
    final sub = await service.create(folder, folder: true, name: 'Sub');
    final note = await service.create(service.root, name: 'Note');
    await service.writeNote(note, '**text**');
    final moved = await service.move(note, sub);
    final duplicate = await service.duplicate(moved);
    expect(await service.readNote(duplicate), '**text**');
    await expectLater(service.move(folder, sub), throwsArgumentError);
    await expectLater(service.move(folder, folder), throwsArgumentError);
    expect(await Directory(folder).exists(), true);
  });
  test('delete/restore notes and nested folders, preserving origin and clashes',
      () async {
    final folder =
        await service.create(service.root, folder: true, name: 'Archive');
    final note = await service.create(folder, name: 'Keep');
    await service.writeNote(note, 'kept');
    await service.delete(folder);
    expect(await Directory(folder).exists(), false);
    expect((await service.trash()).single.originalPath, folder);
    await service.create(service.root, folder: true, name: 'Archive');
    final restored = await service.restore((await service.trash()).single);
    expect(p.basename(restored), 'Archive 2');
    expect(await service.readNote(p.join(restored, 'Keep.md')), 'kept');
    final restoredNote = p.join(restored, 'Keep.md');
    await service.delete(restoredNote);
    await service.restore((await service.trash()).single);
    expect(await service.readNote(restoredNote), 'kept');
    expect(await service.trash(), isEmpty);
  });
  test('hidden entries and symlinks are excluded, writes cannot escape root',
      () async {
    await File(p.join(service.root, '.secret.md')).writeAsString('hidden');
    expect((await service.tree()).any((e) => e.name.startsWith('.')), false);
    expect(() => service.readNote(p.join(service.root, '..', 'outside.md')),
        throwsArgumentError);
    if (!Platform.isWindows) {
      await Link(p.join(service.root, 'link')).create(directory.parent.path);
      expect((await service.tree()).any((e) => e.name == 'link'), false);
      expect(() => service.readNote(p.join(service.root, 'link', 'file.md')),
          throwsArgumentError);
    }
  });
  test('atomic writes and state survive a new service instance', () async {
    final path = await service.create(service.root, name: 'Persist');
    await service.writeNote(path, 'first');
    await service.writeNote(path, 'second');
    await service.writeState({
      'open': path,
      'expanded': [service.root],
      'width': 300,
      'hidden': true
    });
    final reopened = LibraryService(Directory(service.root));
    await reopened.initialize();
    expect(await reopened.readNote(path), 'second');
    expect((await reopened.readState())['width'], 300);
    expect(
        (await Directory(service.root).list().toList())
            .any((e) => e.path.endsWith('.tmp')),
        false);
  });
  test('permanent delete and launch purging remove expired trash only',
      () async {
    final old = await service.create(service.root, name: 'Old');
    await service.delete(old);
    final trash = (await service.trash()).single;
    await File(p.join(service.trashPath, 'index.json'))
        .writeAsString(jsonEncode([
      {
        ...trash.toJson(),
        'time':
            DateTime.now().subtract(const Duration(days: 31)).toIso8601String()
      },
    ]));
    await service.initialize();
    expect(await service.trash(), isEmpty);
    expect(await File(p.join(service.trashPath, trash.id)).exists(), false);
    final recent = await service.create(service.root, name: 'Recent');
    await service.delete(recent);
    await service.initialize();
    expect((await service.trash()).length, 1);
    await service.purge((await service.trash()).single);
    expect(await service.trash(), isEmpty);
  });
}
