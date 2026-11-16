import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../doc_tab.dart';
import 'library_service.dart';

class LibraryModel extends ChangeNotifier {
  LibraryModel(this.service);
  final LibraryService service;
  List<LibraryEntry> entries = [];
  List<TrashEntry> deleted = [];
  Set<String> expanded = {};
  String? selected;
  String? renamePath;
  DocTab? current;
  double width = 260;
  bool hidden = false;
  bool showingTrash = false;
  String? error;
  Timer? _autosave;
  Timer? _stateTimer;
  Future<void> _writes = Future.value();
  Future<void> _actions = Future.value();
  Future<void> get idle => _actions;
  bool _disposed = false;
  int _revision = 0;

  Iterable<LibraryEntry> flatten([List<LibraryEntry>? items]) sync* {
    for (final item in items ?? entries) {
      yield item;
      yield* flatten(item.children);
    }
  }

  List<LibraryEntry> get visible {
    final result = <LibraryEntry>[];
    void visit(List<LibraryEntry> list) {
      for (final e in list) {
        result.add(e);
        if (expanded.contains(e.path)) visit(e.children);
      }
    }

    visit(entries);
    return result;
  }

  String get destination {
    final item = flatten().where((e) => e.path == selected).firstOrNull;
    return item == null
        ? service.root
        : item.isFolder
            ? item.path
            : p.dirname(item.path);
  }

  Future<void> initialize() async {
    await service.initialize();
    final state = await service.readState();
    expanded = (state['expanded'] as List? ?? []).cast<String>().toSet();
    width = (state['width'] as num? ?? 260).toDouble().clamp(200, 380);
    hidden = state['hidden'] == true;
    selected = state['selected'] as String?;
    await reload();
    final notes = flatten().where((e) => !e.isFolder).toList();
    final remembered = state['open'] as String?;
    final savedExpanded = Set<String>.of(expanded);
    final savedSelected = selected;
    if (notes.isNotEmpty) {
      await open(notes.any((e) => e.path == remembered)
          ? remembered!
          : notes.first.path);
    }
    if (savedSelected != null &&
        flatten().any((e) => e.path == savedSelected)) {
      selected = savedSelected;
      expanded = savedExpanded;
    }
    notifyListeners();
  }

  Future<void> reload() async {
    entries = await service.tree();
    deleted = await service.trash();
    if (current != null && !await File(current!.filePath!).exists()) {
      _autosave?.cancel();
      final old = current;
      current = null;
      _retire(old);
      final first = flatten().where((e) => !e.isFolder).firstOrNull;
      if (first != null) await open(first.path);
    }
    if (!_disposed) notifyListeners();
  }

  void _retire(DocTab? tab) {
    // Widgets detach their listeners at the next frame; the page calls collect.
    if (tab != null) retired.add(tab);
  }

  final List<DocTab> retired = [];
  void collect() {
    for (final tab in retired) {
      tab.dispose();
    }
    retired.clear();
  }

  Future<void> open(String path) async {
    await flush();
    final markdown = await service.readNote(path);
    final old = current;
    current = DocTab(
        markdown: markdown,
        filePath: path,
        libraryManaged: true,
        onChanged: () {
          _revision++;
          _autosave?.cancel();
          _autosave =
              Timer(const Duration(milliseconds: 700), () => run(flush));
        });
    _retire(old);
    selected = path;
    showingTrash = false;
    var parent = p.dirname(path);
    while (p.isWithin(service.root, parent)) {
      expanded.add(parent);
      parent = p.dirname(parent);
    }
    persist();
    notifyListeners();
  }

  Future<void> flush() async {
    _autosave?.cancel();
    final tab = current;
    if (tab == null || !tab.dirty) {
      await _writes;
      return;
    }
    final revision = _revision;
    final path = tab.filePath!;
    final text = tab.toMarkdown();
    final write = _writes.then((_) => service.writeNote(path, text));
    _writes = write.catchError((Object e) {
      error = 'Could not save note: $e';
    });
    await write;
    if (identical(tab, current) && revision == _revision) tab.dirty = false;
  }

  Map<String, dynamic> get state => {
        'open': current?.filePath,
        'selected': selected,
        'expanded': expanded.toList(),
        'width': width,
        'hidden': hidden
      };
  void persist() {
    _stateTimer?.cancel();
    _stateTimer =
        Timer(const Duration(milliseconds: 250), () => run(saveState));
  }

  Future<void> saveState() async {
    _stateTimer?.cancel();
    final snapshot = state;
    final write = _writes.then((_) => service.writeState(snapshot));
    _writes = write.catchError((Object e) {
      error = 'Could not save library state: $e';
    });
    await write;
  }

  Future<void> run(Future<void> Function() action) {
    final operation = _actions.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (e) {
        error = '$e';
      }
      if (!_disposed) notifyListeners();
    });
    _actions = operation;
    return operation;
  }

  void toggle() {
    hidden = !hidden;
    persist();
    notifyListeners();
  }

  void resize(double value) {
    width = value.clamp(200, 380);
    persist();
    notifyListeners();
  }

  void selectFolder(LibraryEntry entry) {
    selected = entry.path;
    showingTrash = false;
    if (!expanded.remove(entry.path)) expanded.add(entry.path);
    persist();
    notifyListeners();
  }

  Future<void> create({bool folder = false, String? parent}) async {
    hidden = false;
    await flush();
    final destinationPath = parent ?? destination;
    final path = await service.create(destinationPath, folder: folder);
    if (destinationPath != service.root) expanded.add(destinationPath);
    await reload();
    if (!folder) await open(path);
    selected = path;
    renamePath = path;
    persist();
    notifyListeners();
  }

  void startRename(String path) {
    renamePath = path;
    notifyListeners();
  }

  void cancelRename() {
    renamePath = null;
    notifyListeners();
  }

  void _remap(String from, String to) {
    String? map(String? value) => value == from
        ? to
        : value != null && p.isWithin(from, value)
            ? p.join(to, p.relative(value, from: from))
            : value;
    current?.filePath = map(current?.filePath);
    selected = map(selected);
    expanded = expanded.map((e) => map(e)!).toSet();
  }

  Future<void> rename(String path, String name) async {
    await flush();
    renamePath = null;
    final target = await service.rename(path, name);
    _remap(path, target);
    await reload();
    await saveState();
  }

  Future<void> move(String path, String parent) async {
    await flush();
    final target = await service.move(path, parent);
    _remap(path, target);
    expanded.add(parent);
    await reload();
    await saveState();
  }

  Future<void> duplicate(String path) async {
    await flush();
    final target = await service.duplicate(path);
    await reload();
    await open(target);
  }

  Future<void> delete(String path) async {
    await flush();
    await service.delete(path);
    if (current?.filePath == path ||
        (current != null && p.isWithin(path, current!.filePath!))) {
      _retire(current);
      current = null;
    }
    selected = null;
    await reload();
    if (current == null) {
      final first = flatten().where((e) => !e.isFolder).firstOrNull;
      if (first != null) await open(first.path);
    }
    await saveState();
  }

  Future<void> restore(TrashEntry entry) async {
    final path = await service.restore(entry);
    await reload();
    if (!entry.isFolder) await open(path);
  }

  Future<void> importNote(String path) async {
    await flush();
    final target = await service.importNote(path, destination);
    await reload();
    await open(target);
  }

  @override
  void dispose() {
    _disposed = true;
    _autosave?.cancel();
    _stateTimer?.cancel();
    current?.dispose();
    collect();
    super.dispose();
  }
}
