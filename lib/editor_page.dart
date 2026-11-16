import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'actions.dart';
import 'code_block.dart';
import 'doc_tab.dart';
import 'paste.dart';
import 'theme.dart';
import 'toolbar.dart';

const _markdownExtensions = ['md', 'markdown', 'txt'];

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final List<DocTab> _tabs = [];
  int _current = 0;
  bool _editing = true;

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

  DocTab get _tab => _tabs[_current];

  @override
  void initState() {
    super.initState();
    _addTab(markdown: '');
  }

  @override
  void dispose() {
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

      final text = await File(path).readAsString();
      _addTab(markdown: text, filePath: path);
    } catch (e) {
      _toast('Could not open the file: $e');
    }
  }

  Future<bool> _save({bool saveAs = false}) async {
    final tab = _tab;
    try {
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
          width: 420,
        ),
      );
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
            () => _save(saveAs: true),
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _open,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            _addTab(markdown: ''),
      },
      child: Scaffold(
        body: Column(
          children: [
            EditorToolbar(
              tabs: _tabs,
              currentIndex: _current,
              editing: _editing,
              onSelectTab: (i) => setState(() => _current = i),
              onNew: () => _addTab(markdown: ''),
              onOpen: _open,
              onSave: _save,
              onSaveAs: () => _save(saveAs: true),
              onCloseTab: _closeCurrentTab,
              onPickImage: _pickImage,
              onEditingChanged: (value) => setState(() => _editing = value),
            ),
            Expanded(child: _buildEditor(_tab)),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(DocTab tab) {
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
        editorStyle: _editorStyle,
        blockComponentBuilders: _blockBuilders,
        commandShortcutEvents: _commandShortcuts,
        characterShortcutEvents: _characterShortcuts,
        editable: _editing,
        autoFocus: _editing,
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
