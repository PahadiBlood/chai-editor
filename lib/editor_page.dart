import 'dart:async';
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
import 'widgets/sidebar.dart';
import 'actions.dart';
import 'code_block.dart';
import 'doc_tab.dart';
import 'paste.dart';
import 'theme.dart';
import 'toolbar.dart';

const _markdownExtensions = ['md', 'markdown', 'txt'];

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.enableLibrary = true, this.libraryService});
  final bool enableLibrary;
  final LibraryService? libraryService;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final List<DocTab> _tabs = [];
  int _current = 0;
  bool _editing = true;
  bool _external = false;
  LibraryModel? _library;
  Future<void>? _initialization;
  AppLifecycleListener? _lifecycle;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<void> _initializeLibrary() async {
    try {
      final directory = widget.libraryService == null
          ? await getApplicationDocumentsDirectory()
          : null;
      if (!mounted) return;
      final model = LibraryModel(widget.libraryService ??
          LibraryService(Directory(p.join(directory!.path, 'ChaiEditor'))));
      _library = model;
      model.addListener(_libraryChanged);
      await model.initialize();
      if (!mounted) return;
      _libraryChanged();
    } catch (error) {
      if (mounted) _toast('Could not open note library: $error');
    }
  }

  void _libraryChanged() {
    if (!mounted) return;
    setState(() {});
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
        _library?.error = 'Could not save notes: $error';
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
    if (_external && _tab.dirty) {
      final choice = await _askAboutUnsaved(_tab);
      if (choice == _Unsaved.cancel) return;
      if (choice == _Unsaved.save && !await _save()) return;
    }
    await library.run(() => library.open(path));
    if (mounted) {
      setState(() => _external = false);
      _scaffoldKey.currentState?.closeDrawer();
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
          (event) => !enableRichPaste || event != pasteCommand,
        )
        .map((event) =>
            enableRichPaste && event == pasteTextWithoutFormattingCommand
                ? chaiPastePlainTextCommand
                : event),
    if (enableRichPaste) richPasteCommand,
    pasteAsMarkdownCommand,
  ];

  late final List<CharacterShortcutEvent> _characterShortcuts = [
    codeBlockEnter,
    ...standardCharacterShortcutEvents.where((e) => e != slashCommand),
    customSlashCommand(
      [...standardSelectionMenuItems, codeBlockMenuItem],
      style: SelectionMenuStyle.dark,
    ),
  ];

  DocTab get _tab => !_external && _library?.current != null
      ? _library!.current!
      : _tabs[_current];

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
            await _flushLibrary();
            return AppExitResponse.exit;
          } catch (error) {
            _toast('Could not save notes: $error');
            return AppExitResponse.cancel;
          }
        },
      );
    }
  }

  @override
  void dispose() {
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
      if (mounted && tab.dirty && markdown.isNotEmpty) {
        setState(() => tab.dirty = false);
      }
    });
    setState(() {
      _tabs.add(tab);
      _current = _tabs.length - 1;
    });
  }

  Future<void> _closeCurrentTab() async {
    final tab = _tab;
    if (tab.dirty) {
      final choice = await _askAboutUnsaved(tab);
      if (choice == _Unsaved.cancel) return;
      if (choice == _Unsaved.save) {
        final saved = await _save();
        if (!saved) return;
      }
    }

    setState(() {
      _tabs.remove(tab);
      if (_tabs.isEmpty) {
        _current = 0;
      } else if (_current >= _tabs.length) {
        _current = _tabs.length - 1;
      }
    });
    // Dispose after the frame so the editor widget is gone first.
    WidgetsBinding.instance.addPostFrameCallback((_) => tab.dispose());

    if (_tabs.isEmpty) {
      _addTab(markdown: '');
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
            child: const Text("Don't save"),
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
        allowedExtensions: _markdownExtensions,
      );
      final path = result?.files.single.path;
      if (path == null) return;

      final existing = _tabs.indexWhere((t) => t.filePath == path);
      if (existing >= 0) {
        setState(() => _current = existing);
        return;
      }

      await _library?.flush();
      final text = await File(path).readAsString();
      _external = true;
      _addTab(markdown: text, filePath: path);
    } catch (e) {
      _toast('Could not open the file: $e');
    }
  }

  Future<bool> _save({bool saveAs = false}) async {
    final tab = _tab;
    try {
      if (tab.libraryManaged && !saveAs) {
        await _library?.flush();
        return true;
      }
      var path = tab.filePath;

      if (path == null || saveAs) {
        final suggested = tab.filePath == null ? 'Untitled.md' : tab.title;
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save document',
          fileName: suggested,
          type: FileType.custom,
          allowedExtensions: ['md'],
        );
        if (path == null) return false;

        final lower = path.toLowerCase();
        if (!lower.endsWith('.md') && !lower.endsWith('.markdown')) {
          path = '$path.md';
        }
      }

      await File(path).writeAsString(tab.toMarkdown());
      if (tab.libraryManaged) {
        _toast('Exported ${p.basename(path)}');
        return true;
      }
      setState(() {
        tab.filePath = path;
        tab.dirty = false;
      });
      _toast('Saved ${tab.title}');
      return true;
    } catch (e) {
      _toast('Could not save the file: $e');
      return false;
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
      _toast('Could not insert the image: $e');
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
    return CallbackShortcuts(
      bindings: {
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
          final editor = Column(
            children: [
              EditorToolbar(
                activeTab: _tab,
                tabs: _tabs,
                currentIndex: _current,
                editing: _editing,
                onSelectTab: (i) => setState(() => _current = i),
                onNew: _newNote,
                onToggleSidebar: widget.enableLibrary ? _toggleSidebar : null,
                onImport: widget.enableLibrary ? _importNote : null,
                onOpen: _open,
                onSave: _save,
                onSaveAs: () => _save(saveAs: true),
                onCloseTab: _closeCurrentTab,
                onPickImage: _pickImage,
                onEditingChanged: (value) => setState(() => _editing = value),
              ),
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
                          child: TextButton.icon(
                              onPressed: _newNote,
                              icon: const Icon(Icons.note_add_outlined),
                              label: const Text('Create a note')))
                      : _buildEditor(_tab,
                          compact: constraints.maxWidth -
                                  (wide && _library?.hidden == false
                                      ? _library!.width
                                      : 0) <
                              600)),
            ],
          );
          if (!wide || _library == null || _library!.hidden) {
            return Padding(
                padding: EdgeInsets.only(
                    top: Platform.isMacOS && widget.enableLibrary ? 52 : 0),
                child: editor);
          }
          return Row(children: [
            SizedBox(width: _library!.width, child: _sidebar()),
            MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) =>
                        _library!.resize(_library!.width + details.delta.dx),
                    child: const SizedBox(width: 5, height: double.infinity))),
            Expanded(child: editor)
          ]);
        })),
      ),
    );
  }

  Widget _sidebar() => ChangeNotifierProvider.value(
      value: _library!,
      child: LibrarySidebar(
        onOpen: _openLibrary,
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
