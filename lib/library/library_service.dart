import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class LibraryEntry {
  const LibraryEntry(this.path, this.isFolder, [this.children = const []]);
  final String path;
  final bool isFolder;
  final List<LibraryEntry> children;
  String get name =>
      isFolder ? p.basename(path) : p.basenameWithoutExtension(path);
  int get noteCount =>
      isFolder ? children.fold(0, (sum, e) => sum + e.noteCount) : 1;
}

class TrashEntry {
  TrashEntry(this.id, this.originalPath, this.isFolder, this.deletedAt);
  final String id;
  final String originalPath;
  final bool isFolder;
  final DateTime deletedAt;
  String get name => isFolder
      ? p.basename(originalPath)
      : p.basenameWithoutExtension(originalPath);
  Map<String, dynamic> toJson() => {
        'id': id,
        'path': originalPath,
        'folder': isFolder,
        'time': deletedAt.toIso8601String()
      };
  factory TrashEntry.fromJson(Map<String, dynamic> json) => TrashEntry(
      json['id'] as String,
      json['path'] as String,
      json['folder'] as bool,
      DateTime.parse(json['time'] as String));
}

/// All paths are absolute and confined to the library. Symlinks are not followed.
class LibraryService {
  LibraryService(Directory directory)
      : root = p.normalize(p.absolute(directory.path));
  final String root;
  String get trashPath => p.join(root, '.trash');
  String get statePath => p.join(root, '.chai', 'state.json');
  int _serial = 0;

  void _check(String path, {bool hidden = false}) {
    final normalized = p.normalize(p.absolute(path));
    if (normalized != root && !p.isWithin(root, normalized)) {
      throw ArgumentError('Outside library');
    }
    if (!hidden &&
        p
            .relative(normalized, from: root)
            .split(p.separator)
            .any((part) => part.startsWith('.') && part != '.')) {
      throw ArgumentError('Hidden library path');
    }
    var current = normalized;
    while (current != root && p.isWithin(root, current)) {
      if (FileSystemEntity.isLinkSync(current)) {
        throw ArgumentError('Symbolic links are not library entries');
      }
      current = p.dirname(current);
    }
  }

  Future<void> initialize() async {
    final first = !await File(statePath).exists() &&
        !await Directory(p.join(root, '.chai')).exists();
    await Directory(root).create(recursive: true);
    await Directory(p.dirname(statePath)).create(recursive: true);
    await Directory(trashPath).create(recursive: true);
    if (first && (await tree()).isEmpty) {
      final folder = await create(root, folder: true, name: 'Notes');
      final note = await create(folder, name: 'Welcome');
      await writeNote(note,
          '# Welcome to Chai Editor\n\nA clean space for your notes.\n\nCreate folders and notes in the sidebar. Your library saves automatically.\n');
    }
    for (final entry in await trash()) {
      if (DateTime.now().difference(entry.deletedAt) >
          const Duration(days: 30)) {
        await purge(entry);
      }
    }
  }

  Future<List<LibraryEntry>> tree([String? folder]) async {
    final path = folder ?? root;
    _check(path);
    final result = <LibraryEntry>[];
    if (!await Directory(path).exists()) return result;
    await for (final entity in Directory(path).list(followLinks: false)) {
      if (p.basename(entity.path).startsWith('.')) continue;
      if (entity is Directory) {
        result.add(LibraryEntry(entity.path, true, await tree(entity.path)));
      } else if (entity is File &&
          p.extension(entity.path).toLowerCase() == '.md') {
        result.add(LibraryEntry(entity.path, false));
      }
    }
    result.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  String cleanName(String name, {bool folder = false}) {
    var value = name
        .replaceAll(RegExp(r'[/\\:\x00-\x1f<>"|?*]'), ' ')
        .trim()
        .replaceFirst(RegExp(r'^\.+'), '')
        .trim();
    value = value.replaceFirst(RegExp(r'[. ]+$'), '');
    if (!folder && value.toLowerCase().endsWith('.md')) {
      value = value.substring(0, value.length - 3).trim();
    }
    return value.isEmpty ? (folder ? 'New Folder' : 'Untitled') : value;
  }

  Future<String> _unique(String parent, String name, bool folder,
      {String? except}) async {
    _check(parent);
    if (!await Directory(parent).exists()) {
      throw FileSystemException('Folder no longer exists', parent);
    }
    final base = cleanName(name, folder: folder);
    final occupied = (await Directory(parent).list(followLinks: false).toList())
        .where((e) => e.path != except)
        .map((e) => p.basename(e.path).toLowerCase())
        .toSet();
    var label = base;
    var number = 2;
    while (occupied.contains('$label${folder ? '' : '.md'}'.toLowerCase())) {
      label = '$base ${number++}';
    }
    return p.join(parent, '$label${folder ? '' : '.md'}');
  }

  Future<String> create(String parent,
      {bool folder = false, String? name}) async {
    final target = await _unique(
        parent, name ?? (folder ? 'New Folder' : 'Untitled'), folder);
    if (folder) {
      await Directory(target).create();
    } else {
      await File(target).writeAsString('');
    }
    return target;
  }

  Future<String> rename(String path, String name) async {
    _check(path);
    if (path == root) throw ArgumentError('Cannot rename library root');
    if (name.trim().isEmpty) return path;
    final folder = await FileSystemEntity.isDirectory(path);
    final target = await _unique(p.dirname(path), name, folder, except: path);
    if (target != path) await _rename(path, target, folder);
    return target;
  }

  Future<String> move(String path, String parent) async {
    _check(path);
    _check(parent);
    if (path == root || path == parent || p.isWithin(path, parent)) {
      throw ArgumentError('Cannot move a folder into itself or its children');
    }
    if (p.dirname(path) == parent) return path;
    final folder = await FileSystemEntity.isDirectory(path);
    final target = await _unique(parent, p.basename(path), folder);
    await _rename(path, target, folder);
    return target;
  }

  Future<void> _rename(String from, String to, bool folder) async {
    if (folder) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  Future<String> duplicate(String path) async {
    _check(path);
    final target = await _unique(
        p.dirname(path), '${p.basenameWithoutExtension(path)} copy', false);
    await File(path).copy(target);
    return target;
  }

  Future<String> importNote(String from, String parent) async {
    final target =
        await _unique(parent, p.basenameWithoutExtension(from), false);
    await File(from).copy(target);
    return target;
  }

  Future<String> readNote(String path) {
    _check(path);
    return File(path).readAsString();
  }

  Future<void> writeNote(String path, String text) async {
    _check(path);
    await atomicWrite(path, text);
  }

  Future<void> atomicWrite(String path, String text) async {
    final temporary = File(p.join(p.dirname(path),
        '.${p.basename(path)}.${DateTime.now().microsecondsSinceEpoch}.${_serial++}.tmp'));
    try {
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Map<String, dynamic>> readState() async {
    if (!await File(statePath).exists()) return {};
    try {
      return Map<String, dynamic>.from(
          jsonDecode(await File(statePath).readAsString()) as Map);
    } on FormatException {
      return {};
    }
  }

  Future<void> writeState(Map<String, dynamic> state) =>
      atomicWrite(statePath, jsonEncode(state));

  Future<List<TrashEntry>> trash() async {
    final index = File(p.join(trashPath, 'index.json'));
    if (!await index.exists()) return [];
    final data = jsonDecode(await index.readAsString()) as List;
    return data
        .map((e) => TrashEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _writeTrash(List<TrashEntry> entries) => atomicWrite(
      p.join(trashPath, 'index.json'),
      jsonEncode(entries.map((e) => e.toJson()).toList()));

  Future<void> delete(String path) async {
    _check(path);
    if (path == root) throw ArgumentError('Cannot delete library root');
    final entries = await trash();
    final entry = TrashEntry(
        '${DateTime.now().microsecondsSinceEpoch}-${_serial++}',
        path,
        await FileSystemEntity.isDirectory(path),
        DateTime.now());
    // Persist intent first: a crash never leaves a moved file without its origin.
    await _writeTrash([...entries, entry]);
    try {
      await _rename(path, p.join(trashPath, entry.id), entry.isFolder);
    } catch (_) {
      await _writeTrash(entries);
      rethrow;
    }
  }

  void _checkTrash(TrashEntry entry) {
    _check(entry.originalPath);
    if (!RegExp(r'^\d+-\d+$').hasMatch(entry.id)) {
      throw ArgumentError('Invalid trash item');
    }
  }

  Future<String> restore(TrashEntry entry) async {
    _checkTrash(entry);
    final parent = p.dirname(entry.originalPath);
    await Directory(parent).create(recursive: true);
    final target =
        await _unique(parent, p.basename(entry.originalPath), entry.isFolder);
    await _rename(p.join(trashPath, entry.id), target, entry.isFolder);
    await _writeTrash((await trash()).where((e) => e.id != entry.id).toList());
    return target;
  }

  Future<void> purge(TrashEntry entry) async {
    _checkTrash(entry);
    final target = p.join(trashPath, entry.id);
    if (await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
      if (entry.isFolder) {
        await Directory(target).delete(recursive: true);
      } else {
        await File(target).delete();
      }
    }
    await _writeTrash((await trash()).where((e) => e.id != entry.id).toList());
  }
}
