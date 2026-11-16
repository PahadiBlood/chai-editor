import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../doc_tab.dart';
import '../markdown_io.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'library_service.dart';

Map<String, dynamic> _parseNote(String markdown) =>
    markdownToEditorDocument(markdown).toJson();
const kCacheNotes = true;
const kRestoreFolderSelection = false;
const kSelectNextAfterDelete = false;

class LibraryModel extends ChangeNotifier {
  LibraryModel(this.service);
  final LibraryService service;
  List<LibraryEntry> entries = [];
  List<TrashEntry> deleted = [];
  Set<String> expanded = {};
  String? selected;
  String? renamePath;
  DocTab? current;
  String? get openNote => current?.filePath;
  final _cache = <String, DocTab>{};
  final _loading = <String, Future<DocTab>>{};
  final _fileWrites = <String, Future<void>>{};
  final _revisionByTab = <DocTab, int>{};
  final _timers = <DocTab, Timer>{};
  int _request = 0;
  final documentChanged = ValueNotifier<int>(0);
  final focusEditor = ValueNotifier<int>(0);
  final status = ValueNotifier<String>('Saved');
  double width = 260;
  bool hidden = false;
  bool showingTrash = false;
  String? error;
  Timer? _autosave;
  Timer? _stateTimer;
  Timer? _errorTimer;
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
    if (kRestoreFolderSelection &&
        savedSelected != null &&
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
      _cache.remove(old?.filePath);
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

  Future<DocTab> _load(String path) async {
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached;
      return cached;
    }
    return _loading.putIfAbsent(path, () async {
      final markdown = await service.readNote(path);
      if (_disposed) throw StateError('Library closed during preload');
      final parsed = await compute(_parseNote, markdown);
      late final DocTab tab;
      tab = DocTab(
          document: Document.fromJson(parsed),
          markdown: markdown,
          filePath: path,
          libraryManaged: true,
          onChanged: () {
            _revisionByTab[tab] = (_revisionByTab[tab] ?? 0) + 1;
            if (identical(tab, current)) status.value = 'Saving…';
            _timers.remove(tab)?.cancel();
            _timers[tab] = Timer(
                const Duration(milliseconds: 700),
                () => _saveTab(tab)
                    .catchError((Object e) => debugPrint('Note save: $e')));
          });
      _cache[path] = tab;
      _loading.remove(path);
      return tab;
    }).whenComplete(() => _loading.remove(path));
  }

  Future<void> preload(String path) async {
    if (!kCacheNotes || _disposed) return;
    try {
      await _load(path);
      _evict();
    } catch (e) {
      debugPrint('Preload: $e');
    }
  }

  void _evict() {
    for (final entry in _cache.entries.toList()) {
      if (_cache.length <= 8) break;
      if (identical(entry.value, current) ||
          entry.value.dirty ||
          _fileWrites.containsKey(entry.key)) {
        continue;
      }
      _cache.remove(entry.key);
      // Give outgoing fade widgets time to unmount before collecting their state.
      Timer(const Duration(milliseconds: 300), () {
        if (_disposed) {
          entry.value.dispose();
        } else {
          _retire(entry.value);
          notifyListeners();
        }
      });
    }
  }

  Future<void> open(String path) async {
    if (!kCacheNotes) return _openUncached(path);
    final request = ++_request;
    selected = path;
    showingTrash = false;
    notifyListeners(); // Highlight before doing filesystem work.
    final previous = current;
    if (previous != null && previous.dirty) {
      unawaited(_saveTab(previous)
          .catchError((Object e) => debugPrint('Background save: $e')));
    }
    final cached = _cache[path];
    final tab = cached ?? await _load(path);
    if (_disposed || request != _request) return;
    _cache.remove(path);
    _cache[path] = tab;
    current = tab;
    tab.editorState.selection ??= tab.rememberedSelection;
    status.value = tab.dirty ? 'Saving…' : 'Saved';
    var parent = p.dirname(path);
    while (p.isWithin(service.root, parent)) {
      expanded.add(parent);
      parent = p.dirname(parent);
    }
    documentChanged.value++;
    persist();
    notifyListeners();
    _evict();
  }

  Future<void> _saveTab(DocTab tab) async {
    _timers.remove(tab)?.cancel();
    if (!tab.dirty) return;
    final path = tab.filePath!;
    final revision = _revisionByTab[tab] ?? 0;
    final text = tab.toMarkdown();
    final prior = _fileWrites[path] ?? Future<void>.value();
    final write = prior.catchError((Object e) {}).then((_) async {
      try {
        await service.writeNote(path, text);
      } catch (e) {
        error = 'Couldn’t save “${tab.title}”. Retrying…';
        if (!_disposed) notifyListeners();
        _errorTimer?.cancel();
        _errorTimer = Timer(const Duration(seconds: 5), () {
          error = null;
          if (!_disposed) notifyListeners();
        });
        await service.writeNote(path, text);
      }
      if ((_revisionByTab[tab] ?? 0) == revision) tab.dirty = false;
      if (!_disposed && identical(tab, current)) {
        status.value = tab.dirty ? 'Saving…' : 'Saved';
      }
    });
    _fileWrites[path] = write;
    try {
      await write;
    } finally {
      if (identical(_fileWrites[path], write)) _fileWrites.remove(path);
    }
  }

  Future<void> _openUncached(String path) async {
    await flush();
    final markdown = await service.readNote(path);
    final old = current;
    current = DocTab(
        markdown: markdown,
        filePath: path,
        libraryManaged: true,
        onChanged: () {
          _revision++;
          status.value = 'Saving…';
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
    if (!kCacheNotes) return _flushUncached();
    final tabs = {..._cache.values, if (current != null) current!};
    await Future.wait(tabs.where((e) => e.dirty).map(_saveTab));
    await Future.wait(_fileWrites.values.toList());
    await _writes;
  }

  Future<void> _flushUncached() async {
    _autosave?.cancel();
    final tab = current;
    if (tab == null || !tab.dirty) {
      await _writes;
      return;
    }
    status.value = 'Saving…';
    final revision = _revision;
    final path = tab.filePath!;
    final text = tab.toMarkdown();
    final write = _writes.then((_) => service.writeNote(path, text));
    _writes = write.catchError((Object e) {
      error = 'Couldn’t save “${tab.title}”. Retrying…';
      _errorTimer?.cancel();
      _errorTimer = Timer(const Duration(seconds: 5), () {
        error = null;
        if (!_disposed) notifyListeners();
      });
      if (!_disposed) notifyListeners();
      _autosave = Timer(const Duration(seconds: 1), () => run(flush));
    });
    await write;
    if (identical(tab, current) && revision == _revision) {
      tab.dirty = false;
      status.value = 'Saved';
    }
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
      debugPrint('Chai state write failed: $e');
    });
    await write;
  }

  Future<void> run(Future<void> Function() action) {
    final operation = _actions.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } catch (e) {
        debugPrint('Chai library action failed: $e');
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
    final focusBody = renamePath == current?.filePath;
    renamePath = null;
    if (focusBody) focusEditor.value++;
    notifyListeners();
  }

  void _remap(String from, String to) {
    String? map(String? value) => value == from
        ? to
        : value != null && p.isWithin(from, value)
            ? p.join(to, p.relative(value, from: from))
            : value;
    current?.filePath = map(current?.filePath);
    final cached = _cache.entries.toList();
    _cache.clear();
    for (final entry in cached) {
      entry.value.filePath = map(entry.value.filePath);
      _cache[map(entry.key)!] = entry.value;
    }
    documentChanged.value++;
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
    if (current?.filePath == target) focusEditor.value++;
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
    ++_request;
    for (final entry in _cache.entries.toList()) {
      if (entry.key == path || p.isWithin(path, entry.key)) {
        _cache.remove(entry.key);
        _retire(entry.value);
      }
    }
    if (current?.filePath == path ||
        (current != null && p.isWithin(path, current!.filePath!))) {
      if (!retired.contains(current)) _retire(current);
      current = null;
      documentChanged.value++;
    }
    selected = null;
    await reload();
    if (kSelectNextAfterDelete && current == null) {
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
    _errorTimer?.cancel();
    _autosave?.cancel();
    _stateTimer?.cancel();
    for (final timer in _timers.values) {
      timer.cancel();
    }
    final tabs = {..._cache.values, if (current != null) current!};
    for (final tab in tabs) {
      tab.dispose();
    }
    documentChanged.dispose();
    focusEditor.dispose();
    collect();
    status.dispose();
    super.dispose();
  }
}
