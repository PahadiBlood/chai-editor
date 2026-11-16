import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'atomic_file.dart' as atomic;

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
    final marker = p.join(root, '.chai', 'initialized');
    final first = !await File(marker).exists();
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
    await _writeInternal(marker, '1');
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
      await writeFileAtomic(target, '');
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
    await writeFileAtomic(target, await File(path).readAsString());
    return target;
  }

  Future<String> importNote(String from, String parent) async {
    final target =
        await _unique(parent, p.basenameWithoutExtension(from), false);
    await writeFileAtomic(target, await File(from).readAsString());
    return target;
  }

  Future<String> readNote(String path) {
    _check(path);
    return File(path).readAsString();
  }

  Future<void> writeNote(String path, String text) async {
    _check(path);
    await writeFileAtomic(path, text);
  }

  Future<void> atomicWrite(String path, String text) =>
      writeFileAtomic(path, text);

  /// Check actual write access without modifying any existing note or setting.
  Future<void> verifyWritable() async {
    final probe = File(p.join(root,
        '.storage-check-${DateTime.now().microsecondsSinceEpoch}-${_serial++}'));
    try {
      await writeFileAtomic(probe.path, '');
    } finally {
      if (await probe.exists()) await probe.delete();
    }
  }

  Future<void> writeFileAtomic(String path, String text) =>
      atomic.writeFileAtomic(path, text);

  // Values in state/trash are portable, slash-separated paths relative to root.
  String? _encodePath(Object? value) {
    if (value is! String) return null;
    final normalized = p.normalize(p.absolute(value));
    if (normalized != root && !p.isWithin(root, normalized)) return null;
    return p.relative(normalized, from: root).split(p.separator).join('/');
  }

  String? _decodePath(Object? value) {
    if (value is! String || value.isEmpty) return null;
    if (p.isAbsolute(value)) {
      // Compatibility with earlier installations; never import another user's root.
      final path = p.normalize(value);
      return path == root || p.isWithin(root, path) ? path : null;
    }
    // Reject drive/UNC paths from a different platform and traversal outside root.
    if (p.windows.isAbsolute(value) ||
        value.contains(p.windows.separator) ||
        RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      return null;
    }
    final path = p.normalize(p.joinAll([root, ...value.split('/')]));
    if (path != root && !p.isWithin(root, path)) return null;
    return path;
  }

  Future<Map<String, dynamic>> readState() async {
    try {
      final file = File(statePath);
      if (!await file.exists()) return {};
      final value = jsonDecode(await file.readAsString());
      if (value is! Map) return {};
      final state = Map<String, dynamic>.from(value);
      final expanded = state['expanded'];
      final width = state['width'];
      return {
        'open': _decodePath(state['open']),
        'selected': _decodePath(state['selected']),
        'expanded': expanded is List
            ? expanded.map(_decodePath).whereType<String>().toList()
            : <String>[],
        'width': width is num && width.isFinite ? width.clamp(200, 380) : 260,
        'hidden': state['hidden'] == true,
      };
    } on FileSystemException catch (error) {
      stderr.writeln(
          'Chai sidebar state unavailable: ${error.osError?.message ?? 'unavailable'}');
      return {};
    } on FormatException {
      stderr.writeln('Chai sidebar state is invalid; using defaults.');
      return {};
    }
  }

  Future<void> writeState(Map<String, dynamic> state) => _writeInternal(
      statePath,
      jsonEncode({
        'version': 2,
        'open': _encodePath(state['open']),
        'selected': _encodePath(state['selected']),
        'expanded': (state['expanded'] is List ? state['expanded'] as List : [])
            .map(_encodePath)
            .whereType<String>()
            .toList(),
        'width': state['width'],
        'hidden': state['hidden'] == true,
      }));

  Future<void> _writeInternal(String path, String text) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await writeFileAtomic(path, text);
        return;
      } catch (error) {
        stderr.writeln('Chai internal write failed ($path): $error');
      }
    }
    // State is best effort; a failed trash index must stop the destructive move.
    if (path == p.join(trashPath, 'index.json')) {
      throw FileSystemException('Could not update trash index', path);
    }
  }

  Future<List<TrashEntry>> trash() async {
    final index = File(p.join(trashPath, 'index.json'));
    if (!await index.exists()) return [];
    final data = jsonDecode(await index.readAsString()) as List;
    return data.map((e) {
      final json = Map<String, dynamic>.from(e as Map);
      final path = _decodePath(json['path']);
      if (path == null) {
        throw const FormatException(
            'Trash item belongs to an unavailable library');
      }
      return TrashEntry.fromJson({...json, 'path': path});
    }).toList();
  }

  Future<void> _writeTrash(List<TrashEntry> entries) => _writeInternal(
      p.join(trashPath, 'index.json'),
      jsonEncode(entries
          .map((e) => {...e.toJson(), 'path': _encodePath(e.originalPath)})
          .toList()));

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
