import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'library/library_model.dart';
import 'library/library_service.dart';
import 'library/library_location.dart';
import 'widgets/sidebar.dart';
import 'widgets/document_switcher.dart';
import 'export/export_model.dart';
import 'export/pdf_exporter.dart';
import 'export/docx_exporter.dart';
import 'markdown_io.dart';
import 'actions.dart';
import 'code_block.dart';
import 'doc_tab.dart';
import 'paste.dart';
import 'clipboard_writer.dart';
import 'file_manager.dart';
import 'library/atomic_file.dart';
import 'theme.dart';
import 'toolbar.dart';

const kLegacyLoadDirtyReset =
    bool.fromEnvironment('CHAI_LEGACY_LOAD_DIRTY_RESET', defaultValue: false);

class EditorPage extends StatefulWidget {
  const EditorPage(
      {super.key,
      this.enableLibrary = true,
      this.libraryService,
      this.libraryLocation});
  final bool enableLibrary;
  final LibraryService? libraryService;
  final LibraryLocation? libraryLocation;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage>
    with SingleTickerProviderStateMixin {
  late final _sidebarAnimation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  Object? _lastLibrarySignature;
  final List<DocTab> _tabs = [];
  final _openFolders = <String>[];
  final _openingFiles = <String>{};
  int _current = 0;
  bool _editing = true;
  bool _external = false;
  LibraryModel? _library;
  Future<void>? _initialization;
  AppLifecycleListener? _lifecycle;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _storageLoading = false;
  String? _storageError;
  late final LibraryLocation _location = widget.libraryLocation ??
      LibraryLocation(
        documentsDirectory: getApplicationDocumentsDirectory,
        supportDirectory: getApplicationSupportDirectory,
      );

  Future<void> _initializeLibrary({bool useAppStorage = false}) async {
    if (_storageLoading) return;
    _storageLoading = true;
    _storageError = null;
    LibraryModel? candidate;
    try {
      final service = useAppStorage
          ? await _location.appStorage()
          : widget.libraryService ?? await _location.resolve();
      if (!mounted) return;
      candidate = LibraryModel(service);
      await candidate.initialize();
      await service.verifyWritable();
      if (!mounted) return;
      if (useAppStorage) await _location.rememberAppStorage();
      // The temporary first tab is only a fallback for a library-less editor.
      // Once the saved library has opened a note, it must not appear as a
      // spurious unsaved external document in the sidebar or document menu.
      if (candidate.current != null &&
          _tabs.length == 1 &&
          _tabs.single.filePath == null &&
          !_tabs.single.dirty) {
        final draft = _tabs.removeAt(0);
        WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
      }
      _library = candidate;
      candidate = null;
      _library!.addListener(_libraryChanged);
      _library!.focusEditor.addListener(_focusDocument);
      _libraryChanged();
    } catch (error, stack) {
      debugPrint('Library setup failed: $error\n$stack');
      if (mounted) {
        _storageError = 'Chai Editor couldn’t open its notes folder. '
            'Retry, or create a library in this app’s local storage. '
            'Existing notes won’t be moved or deleted.';
      }
    } finally {
      candidate?.dispose();
      _storageLoading = false;
      if (mounted) setState(() {});
    }
  }

  void _retryStorage({bool useAppStorage = false}) {
    _initialization = _initializeLibrary(useAppStorage: useAppStorage);
    setState(() {});
  }

  Widget _storageSetup() => Scaffold(
          body: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Set up your note library',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Text(_storageError ?? 'Preparing your notes…',
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (_storageLoading)
                const CircularProgressIndicator()
              else
                Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                          onPressed: _retryStorage, child: const Text('Retry')),
                      FilledButton(
                          onPressed: () => _retryStorage(useAppStorage: true),
                          child: const Text('Use app storage')),
                    ]),
            ])),
      )));

  void _focusDocument() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _library?.current != null) {
        final tab = _library!.current!;
        tab.editorState.selection ??=
            tab.rememberedSelection ?? Selection.collapsed(Position(path: [0]));
        tab.focusNode.requestFocus();
      }
    });
  }

  void _libraryChanged() {
    if (!mounted) return;
    final signature = (
      _library?.current,
      _library?.openNote,
      _library?.hidden,
      _library?.width,
      _library?.error,
      _library?.current?.revision,
      _library?.current?.dirty,
    );
    if (_lastLibrarySignature != signature) {
      _lastLibrarySignature = signature;
      _sidebarAnimation.animateTo(_library?.hidden == true ? 0 : 1,
          curve: Curves.easeInOutCubic);
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _library?.collect();
    });
  }

  Future<void> _flushLibrary() async {
    await _initialization;
    final library = _library;
    if (library != null) {
      await library.idle;
      await library.flush();
      await library.saveState();
    }
  }

  void _saveInBackground() {
    unawaited(_flushLibrary().catchError((Object error) {
      if (mounted) {
        debugPrint('Background note save: $error');
        _library?.error =
            'Your recent changes couldn’t be saved. Keep this window open and try saving again.';
        _libraryChanged();
      }
    }));
  }

  Future<void> _newNote({bool folder = false}) async {
    final library = _library;
    if (library == null) {
      _addTab(markdown: '');
      return;
    }
    await library.run(() => library.create(folder: folder));
    if (mounted) {
      setState(() => _external = false);
      if (MediaQuery.sizeOf(context).width < 760) {
        _scaffoldKey.currentState?.openDrawer();
      }
    }
  }

  Future<void> _openLibrary(String path) async {
    final library = _library;
    if (library == null) return;
    try {
      await library.open(path);
    } catch (error) {
      debugPrint('Open library note: $error');
      if (mounted) {
        _toast(
            'Couldn’t open this note. It may have moved. Refresh the library and try again.');
      }
      return;
    }
    if (mounted) {
      setState(() => _external = false);
      _scaffoldKey.currentState?.closeDrawer();
      _focusTab(_tab);
    }
  }

  Future<void> _importNote() async {
    final library = _library;
    if (library == null) return;
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['md']);
    final path = result?.files.single.path;
    if (path != null) {
      await library.run(() => library.importNote(path));
      if (mounted) setState(() => _external = false);
    }
  }

  void _toggleSidebar() {
    if (MediaQuery.sizeOf(context).width < 760) {
      if (_scaffoldKey.currentState?.isDrawerOpen == true) {
        _scaffoldKey.currentState?.closeDrawer();
      } else {
        _scaffoldKey.currentState?.openDrawer();
      }
    } else {
      _library?.toggle();
    }
  }

  late final EditorStyle _editorStyle = buildEditorStyle();
  late final Map<String, BlockComponentBuilder> _blockBuilders =
      buildBlockBuilders();

  late final List<CommandShortcutEvent> _commandShortcuts = [
    ...standardCommandShortcutEvents
        .where(
          (event) =>
              (!enableRichPaste || event != pasteCommand) &&
              (!enableRichCopy ||
                  (event != copyCommand && event != cutCommand)),
        )
        .map((event) =>
            enableRichPaste && event == pasteTextWithoutFormattingCommand
                ? chaiPastePlainTextCommand
                : event),
    if (enableRichPaste) richPasteCommand,
    pasteAsMarkdownCommand,
    pasteAsCodeBlockCommand,
    if (enableRichCopy) ...[richCopyCommand, richCutCommand],
  ];

  late final List<CharacterShortcutEvent> _characterShortcuts = [
    codeBlockEnter,
    ...standardCharacterShortcutEvents.where((e) => e != slashCommand),
    customSlashCommand(
      [...standardSelectionMenuItems, codeBlockMenuItem],
      style: kMonochromeEditorMenus
          ? monochromeSelectionMenu
          : SelectionMenuStyle.dark,
    ),
  ];

  DocTab get _tab => !_external && _library?.current != null
      ? _library!.current!
      : _tabs[_current];

  List<DocTab> get _documentTabs => [
        ...?_library?.openTabs,
        ..._tabs,
      ];

  void _focusTab(DocTab tab) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_tab, tab)) {
        tab.editorState.selection ??=
            tab.rememberedSelection ?? Selection.collapsed(Position(path: [0]));
        tab.focusNode.requestFocus();
      }
    });
  }

  void _selectTab(DocTab tab) {
    if (tab.libraryManaged) {
      unawaited(_openLibrary(tab.filePath!));
    } else {
      setState(() {
        _current = _tabs.indexOf(tab);
        _external = true;
      });
      _focusTab(tab);
    }
  }

  void _history({bool redo = false}) {
    if (!_editing || ModalRoute.of(context)?.isCurrent != true) return;
    final tab = _tab;
    if (redo) {
      tab.editorState.undoManager.redo();
    } else {
      tab.editorState.undoManager.undo();
    }
    _focusTab(tab);
  }

  @override
  void initState() {
    super.initState();
    _addTab(markdown: '');
    if (widget.enableLibrary) {
      _initialization = _initializeLibrary();
      _lifecycle = AppLifecycleListener(
        onInactive: _saveInBackground,
        onHide: _saveInBackground,
        onResume: () => _library?.run(() async {
          await _library?.flush();
          await _library?.saveState();
          await _library?.reload();
        }),
        onExitRequested: () async {
          try {
            if (!await _confirmExit()) return AppExitResponse.cancel;
            await _flushLibrary();
            return AppExitResponse.exit;
          } catch (error) {
            debugPrint('Exit save: $error');
            _toast(
                'Your recent changes couldn’t be saved. Please try saving again before closing.');
            return AppExitResponse.cancel;
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _sidebarAnimation.dispose();
    _lifecycle?.dispose();
    _library?.removeListener(_libraryChanged);
    _library?.dispose();
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  // ---- Tabs ---------------------------------------------------------------

  void _addTab({required String markdown, String? filePath}) {
    final tab = DocTab(
      markdown: markdown,
      filePath: filePath,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    // Loading a file is not an edit, so clear the dirty flag it may have set.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kLegacyLoadDirtyReset &&
          mounted &&
          tab.dirty &&
          markdown.isNotEmpty) {
        setState(() => tab.dirty = false);
      }
    });
    setState(() {
      _tabs.add(tab);
      _current = _tabs.length - 1;
    });
  }

  Future<void> _closeCurrentTab() => _closeDocument(_tab);

  Future<List<DocTab>?> _confirmDocuments(Iterable<DocTab> tabs) async {
    final discarded = <DocTab>[];
    for (final tab in tabs) {
      if (!tab.needsSave) continue;
      final choice = await _askAboutUnsaved(tab);
      if (!mounted || choice == _Unsaved.cancel) return null;
      if (choice == _Unsaved.save) {
        if (!await _saveDocument(tab) || tab.needsSave) return null;
      } else {
        discarded.add(tab);
      }
    }
    return discarded;
  }

  void _detachExternal(Iterable<DocTab> tabs) {
    final old = tabs.toList();
    final active = _tab;
    setState(() {
      _tabs.removeWhere(old.contains);
      if (_tabs.isEmpty) {
        _addTab(markdown: '');
      }
      _current = _tabs.contains(active)
          ? _tabs.indexOf(active)
          : _current.clamp(0, _tabs.length - 1);
      if (old.contains(active)) _external = _library?.current == null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final tab in old) {
        tab.dispose();
      }
    });
  }

  Future<void> _closeDocument(DocTab tab) async {
    final library = _library;
    final held = tab.libraryManaged ? [tab] : <DocTab>[];
    library?.holdAutosaves(held);
    try {
      final result = await _confirmDocuments([tab]);
      if (result == null || !mounted) return;
      for (final item in result) {
        item.discardPendingChanges();
      }
      if (tab.libraryManaged) {
        await library!.closeDocuments([tab]);
      } else {
        _detachExternal([tab]);
      }
      if (mounted) {
        setState(() {});
        _focusTab(_tab);
      }
    } finally {
      library?.resumeAutosaves(held);
    }
  }

  Future<void> _removeLibraryEntry(String path) async {
    final library = _library!;
    final held = library.documentsUnder(path);
    final external = _tabs
        .where((tab) =>
            tab.filePath != null &&
            (tab.filePath == path || p.isWithin(path, tab.filePath!)))
        .toList();
    library.holdAutosaves(held);
    try {
      final result = await _confirmDocuments([...held, ...external]);
      if (result == null || !mounted) return;
      for (final item in result) {
        item.discardPendingChanges();
      }
      if (external.isNotEmpty) _detachExternal(external);
      await library.removeFromEditor(path);
      if (mounted) {
        setState(() {});
        _focusTab(_tab);
      }
    } catch (error) {
      debugPrint('Remove from editor: $error');
      _toast('Couldn’t remove this item. Its files have been kept.');
    } finally {
      library.resumeAutosaves(held);
    }
  }

  Future<bool> _confirmExit() async {
    final held = _library?.openTabs ?? <DocTab>[];
    _library?.holdAutosaves(held);
    try {
      final result = await _confirmDocuments(_documentTabs
          .where((tab) => !tab.libraryManaged || tab.savePath != null));
      if (result == null) return false;
      for (final item in result) {
        item.discardPendingChanges();
      }
      return true;
    } finally {
      _library?.resumeAutosaves(held);
    }
  }

  Future<_Unsaved> _askAboutUnsaved(DocTab tab) async {
    final result = await showDialog<_Unsaved>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Save changes to ${tab.title}?'),
        content: const Text('Your changes will be lost if you do not save.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _Unsaved.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _Unsaved.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _Unsaved.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result ?? _Unsaved.cancel;
  }

  // ---- Files --------------------------------------------------------------

  Future<void> _open() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Open document',
        type: FileType.custom,
        allowedExtensions: markdownFileExtensions,
      );
      final path = result?.files.single.path;
      if (path != null && mounted) await _openPath(path);
    } catch (error) {
      _reportOpenError(error);
    }
  }

  Future<void> _openPath(String path) async {
    if (!_openingFiles.add(path)) return;
    try {
      final existing = _tabs.where((tab) => tab.filePath == path).firstOrNull;
      if (existing != null) {
        _scaffoldKey.currentState?.closeDrawer();
        _selectTab(existing);
        return;
      }

      if (_library != null &&
          p.isWithin(_library!.service.root, path) &&
          p.extension(path).toLowerCase() == '.md') {
        await _openLibrary(path);
        return;
      }
      final text = await File(path).readAsString();
      if (!mounted) return;
      _external = true;
      _addTab(markdown: text, filePath: path);
      _scaffoldKey.currentState?.closeDrawer();
      _focusTab(_tab);
    } catch (error) {
      _reportOpenError(error);
    } finally {
      _openingFiles.remove(path);
    }
  }

  void _reportOpenError(Object error) {
    debugPrint('Open file: $error');
    _toast(
        'Couldn’t open this file. It may have moved or no longer be accessible.');
  }

  Future<void> _openFolder() async {
    try {
      final path = await FilePicker.platform
          .getDirectoryPath(dialogTitle: 'Open folder');
      if (path == null || !mounted) return;
      final folder = p.normalize(path);
      setState(() {
        if (!_openFolders.contains(folder)) _openFolders.insert(0, folder);
        _library?.showingTrash = false;
      });
    } catch (error) {
      debugPrint('Open folder: $error');
      _toast('Couldn’t open this folder. Try selecting it again.');
    }
  }

  Future<bool> _save({bool saveAs = false}) =>
      _saveDocument(_tab, saveAs: saveAs);

  Future<bool> _saveDocument(DocTab tab, {bool saveAs = false}) async {
    try {
      var path = tab.savePath;
      if (path == null || saveAs) {
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save document',
          fileName: tab.filePath == null ? 'Untitled.md' : tab.title,
          type: FileType.custom,
          allowedExtensions: ['md'],
        );
        if (path == null || !mounted) return false;
        final lower = path.toLowerCase();
        if (!lower.endsWith('.md') && !lower.endsWith('.markdown')) {
          path = '$path.md';
        }
      }
      final markdown = tab.toMarkdown();
      await writeFileAtomic(path, markdown);
      if (tab.libraryManaged) await _library!.saveNote(tab);
      if (!mounted) return false;
      setState(() => tab.rememberSavedDestination(path!, markdown));
      _toast('Saved ${p.basename(path)}');
      return true;
    } catch (error) {
      debugPrint('Save file: $error');
      _toast(
          'Couldn’t save this file. Try Save As and choose a writable folder.');
      return false;
    }
  }

  Future<void> _export(String format, {String? path}) async {
    try {
      await _library?.flush();
      final Document document;
      if (path == null || path == _tab.filePath) {
        document = Document.fromJson(_tab.editorState.document.toJson());
      } else {
        document = markdownToEditorDocument(await File(path).readAsString());
      }
      final name =
          p.basenameWithoutExtension(path ?? _tab.filePath ?? 'Untitled');
      final target = await FilePicker.platform.saveFile(
          dialogTitle: 'Export $name',
          fileName: '$name.$format',
          type: FileType.custom,
          allowedExtensions: [format]);
      if (target == null) return;
      final destination = target.toLowerCase().endsWith('.$format')
          ? target
          : '$target.$format';
      final model = ExportModel.fromDocument(document);
      final bytes = switch (format) {
        'pdf' => await PdfExporter().export(model),
        'docx' => DocxExporter().export(model),
        _ => utf8.encode(editorDocumentToMarkdown(document)),
      };
      await Directory(p.dirname(destination)).create(recursive: true);
      final temp =
          File('$destination.${DateTime.now().microsecondsSinceEpoch}.tmp');
      try {
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(destination);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Exported'),
          action: SnackBarAction(
              label: fileManagerLabel(),
              onPressed: () => unawaited(revealFileLocation(destination)
                  .catchError((Object error) =>
                      _toast('Couldn’t open this file location.'))))));
    } catch (e) {
      _toast('Couldn’t export this note. Check the destination and try again.');
      debugPrint('Export: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Insert image',
        type: FileType.image,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await insertImage(_tab.editorState, path);
    } catch (e) {
      debugPrint('Insert image: $e');
      _toast('Couldn’t open this image. Try selecting it again.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          width: MediaQuery.sizeOf(context).width < 480 ? null : 420,
        ),
      );
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.enableLibrary && _library == null) return _storageSetup();
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyZ,
            meta: Platform.isMacOS, control: !Platform.isMacOS): _history,
        SingleActivator(LogicalKeyboardKey.keyZ,
            shift: true,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS): () => _history(redo: true),
        if (!Platform.isMacOS)
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
              _history(redo: true),
        SingleActivator(LogicalKeyboardKey.keyS,
            meta: Platform.isMacOS, control: !Platform.isMacOS): _save,
        SingleActivator(LogicalKeyboardKey.keyS,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
            shift: true): () => _save(saveAs: true),
        SingleActivator(LogicalKeyboardKey.keyO,
            meta: Platform.isMacOS, control: !Platform.isMacOS): _open,
        SingleActivator(LogicalKeyboardKey.keyN,
            meta: Platform.isMacOS, control: !Platform.isMacOS): _newNote,
        SingleActivator(LogicalKeyboardKey.keyN,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
            shift: true): () => _newNote(folder: true),
        SingleActivator(LogicalKeyboardKey.keyS,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
            alt: true): _toggleSidebar,
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _library == null || MediaQuery.sizeOf(context).width >= 760
            ? null
            : Drawer(width: _library!.width, child: _sidebar()),
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final documentWidth = (wide && _library != null
                  ? constraints.maxWidth - _library!.width - 5
                  : constraints.maxWidth)
              .clamp(0.0, 860.0);
          final editor = Column(
            children: [
              RepaintBoundary(
                  child: AnimatedBuilder(
                      animation: _sidebarAnimation,
                      builder: (context, child) => Padding(
                          padding: EdgeInsets.only(
                              left: Platform.isMacOS && widget.enableLibrary
                                  ? (wide
                                      ? 80 * (1 - _sidebarAnimation.value)
                                      : 80)
                                  : 0),
                          child: child),
                      child: EditorToolbar(
                        activeTab: _tab,
                        breadcrumb: _library == null || _external
                            ? null
                            : ValueListenableBuilder<String>(
                                valueListenable: _library!.status,
                                builder: (context, status, child) => Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          _library!.openNote == null
                                              ? 'No note selected'
                                              : p
                                                  .withoutExtension(p.relative(
                                                      _library!.openNote!,
                                                      from: _library!
                                                          .service.root))
                                                  .split(p.separator)
                                                  .join(' / '),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.text)),
                                      Text(status,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textMuted)),
                                    ]),
                              ),
                        tabs: _documentTabs,
                        currentIndex: _documentTabs.indexOf(_tab),
                        editing: _editing,
                        onSelectTab: (i) => _selectTab(_documentTabs[i]),
                        onUndo: () => _history(),
                        onRedo: () => _history(redo: true),
                        onNew: _newNote,
                        onToggleSidebar: widget.enableLibrary &&
                                (!wide || _library?.hidden != false)
                            ? _toggleSidebar
                            : null,
                        onImport: widget.enableLibrary ? _importNote : null,
                        onOpen: _open,
                        onExport: _export,
                        onSave: _save,
                        onSaveAs: () => _save(saveAs: true),
                        onCloseTab: _closeCurrentTab,
                        onPickImage: _pickImage,
                        onEditingChanged: (value) =>
                            setState(() => _editing = value),
                      ))),
              if (_library?.error != null)
                MaterialBanner(content: Text(_library!.error!), actions: [
                  TextButton(
                      onPressed: () {
                        _library!.error = null;
                        setState(() {});
                      },
                      child: const Text('Dismiss'))
                ]),
              Expanded(
                  child: _library != null &&
                          !_external &&
                          _library!.current == null
                      ? Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('No note selected'),
                          const SizedBox(height: 12),
                          TextButton.icon(
                              onPressed: _newNote,
                              icon: const Icon(Icons.note_add_outlined),
                              label: const Text('New Note'))
                        ]))
                      : RepaintBoundary(
                          child: DocumentSwitcher(
                              identity: _tab,
                              child: Center(
                                  child: SizedBox(
                                      width: documentWidth,
                                      child: _buildEditor(_tab,
                                          compact: documentWidth < 600)))))),
            ],
          );
          if (!wide || _library == null) {
            // Reserve only horizontal space for traffic lights; the row stays 52 pt.
            return editor;
          }
          final sidebar = SizedBox(
              width: _library!.width,
              child: RepaintBoundary(child: _sidebar()));
          final handle = MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      _library!.resize(_library!.width + details.delta.dx),
                  child: const SizedBox(
                      width: 5,
                      height: double.infinity,
                      child: VerticalDivider(
                          width: 1, thickness: 1, color: AppColors.border))));
          return AnimatedBuilder(
              animation: _sidebarAnimation,
              child: editor,
              builder: (context, child) {
                final progress = _sidebarAnimation.value;
                return Row(children: [
                  IgnorePointer(
                      ignoring: _sidebarAnimation.isAnimating || progress == 0,
                      child: ClipRect(
                          child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress,
                              child: SizedBox(
                                  width: _library!.width + 5,
                                  child: Row(children: [
                                    Expanded(
                                        child: FadeTransition(
                                            opacity: _sidebarAnimation,
                                            child: sidebar)),
                                    handle
                                  ]))))),
                  Expanded(child: child!),
                ]);
              });
        })),
      ),
    );
  }

  Widget _sidebar() => ChangeNotifierProvider.value(
      value: _library!,
      child: LibrarySidebar(
        onOpen: _openPath,
        onOpenFile: _open,
        onOpenFolder: _openFolder,
        openFolders: List.of(_openFolders),
        onCloseFolder: (path) => setState(() => _openFolders.remove(path)),
        onRemove: _removeLibraryEntry,
        externalTabs: _tabs,
        onOpenExternal: _selectTab,
        onCloseExternal: _closeDocument,
        onExport: (path, format) => _export(format, path: path),
        onHide: () {
          if (_scaffoldKey.currentState?.isDrawerOpen == true) {
            _scaffoldKey.currentState?.closeDrawer();
          } else {
            _library!.toggle();
          }
        },
      ));

  Widget _buildEditor(DocTab tab, {bool compact = false}) {
    final state = tab.editorState;
    final key = ValueKey('${identityHashCode(tab)}-$_editing');

    return FloatingToolbar(
      style: kMonochromeEditorMenus
          ? monochromeFloatingToolbar
          : const FloatingToolbarStyle(),
      key: key,
      items: [
        paragraphItem,
        ...headingItems,
        ...markdownFormatItems,
        quoteItem,
        bulletedListItem,
        numberedListItem,
        linkItem,
        buildTextColorItem(),
        buildHighlightColorItem(),
      ],
      editorState: state,
      textDirection: TextDirection.ltr,
      editorScrollController: tab.scrollController,
      child: AppFlowyEditor(
        focusNode: tab.focusNode,
        editorState: state,
        editorScrollController: tab.scrollController,
        editorStyle: compact ? buildEditorStyle(compact: true) : _editorStyle,
        blockComponentBuilders: _blockBuilders,
        commandShortcutEvents: _commandShortcuts,
        characterShortcutEvents: _characterShortcuts,
        editable: _editing,
        autoFocus: _editing && (!widget.enableLibrary || _external),
        header: const SizedBox(height: 40),
        footer: _EndOfDocument(state: state),
      ),
    );
  }
}

enum _Unsaved { save, discard, cancel }

/// Click the empty space under the document to start typing at the end.
class _EndOfDocument extends StatelessWidget {
  const _EndOfDocument({required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final children = state.document.root.children;
        final last = children.isEmpty ? null : children.last;

        // Add an empty paragraph unless the document already ends with one.
        if (last == null ||
            last.type != ParagraphBlockKeys.type ||
            !(last.delta?.isEmpty ?? true)) {
          final transaction = state.transaction
            ..insertNode([children.length], paragraphNode());
          await state.apply(transaction);
        }

        final count = state.document.root.children.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          state.selection = Selection.collapsed(
            Position(path: [count - 1]),
          );
        });
      },
      child: const SizedBox(height: 240, width: double.infinity),
    );
  }
}
