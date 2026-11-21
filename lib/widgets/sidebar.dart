import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../theme.dart';
import '../doc_tab.dart';
import '../file_manager.dart';
import '../library/library_model.dart';
import '../library/library_service.dart';
import 'open_folder_row.dart';

const kLegacyHoverPreload =
    bool.fromEnvironment('CHAI_LEGACY_HOVER_PRELOAD', defaultValue: false);
const _sidebarAccent = AppColors.white;

enum _AddAction { newNote, newFolder, openFile, openFolder }

class LibrarySidebar extends StatefulWidget {
  const LibrarySidebar(
      {super.key,
      required this.onOpen,
      required this.onOpenFile,
      required this.onOpenFolder,
      required this.onHide,
      this.onExport,
      this.onRemove,
      this.externalTabs = const [],
      this.openFolders = const [],
      this.onCloseFolder,
      this.onOpenExternal,
      this.onCloseExternal});
  final ValueChanged<String> onOpen;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onHide;
  final Future<void> Function(String path)? onRemove;
  final List<DocTab> externalTabs;
  final List<String> openFolders;
  final ValueChanged<String>? onCloseFolder;
  final ValueChanged<DocTab>? onOpenExternal;
  final ValueChanged<DocTab>? onCloseExternal;
  final void Function(String path, String format)? onExport;
  @override
  State<LibrarySidebar> createState() => _LibrarySidebarState();
}

class _LibrarySidebarState extends State<LibrarySidebar> {
  final _focus = FocusNode(debugLabel: 'library sidebar');
  final _folderScroll = ScrollController();
  String? _contextTarget;
  bool _menuShowing = false;
  DateTime _lastClick = DateTime(2000);

  @override
  void didUpdateWidget(LibrarySidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openFolders.length <= oldWidget.openFolders.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _folderScroll.hasClients) _folderScroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _folderScroll.dispose();
    super.dispose();
  }

  KeyEventResult _key(LibraryModel model, KeyEvent event) {
    if (event is! KeyDownEvent || model.renamePath != null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final command = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (command && key == LogicalKeyboardKey.keyN) {
      model.run(
          () => model.create(folder: HardwareKeyboard.instance.isShiftPressed));
    } else if (command &&
        key == LogicalKeyboardKey.backspace &&
        model.selected != null) {
      model.run(() => model.delete(model.selected!));
    } else if (key == LogicalKeyboardKey.enter && model.selected != null) {
      model.startRename(model.selected!);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final rows = model.visible;
      if (rows.isNotEmpty) {
        final index = rows.indexWhere((e) => e.path == model.selected);
        final next = (index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1))
            .clamp(0, rows.length - 1);
        model.selected = rows[next].path;
        model.persist();
        setState(() {});
      }
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (model.selected != null) {
        if (key == LogicalKeyboardKey.arrowLeft) {
          model.expanded.remove(model.selected);
        } else {
          model.expanded.add(model.selected!);
        }
        model.persist();
        setState(() {});
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _confirmPurge(LibraryModel model, [TrashEntry? entry]) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Delete permanently?'),
              content: Text(entry == null
                  ? 'All recently deleted items will be removed. This cannot be undone.'
                  : '“${entry.name}” will be removed. This cannot be undone.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete Permanently'))
              ],
            ));
    if (yes == true) {
      await model.run(() async {
        for (final item in entry == null ? List.of(model.deleted) : [entry]) {
          await model.service.purge(item);
        }
        await model.reload();
      });
    }
  }

  Widget _secondary(void Function(Offset) action, Widget child) => Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton ||
            (event.buttons == kPrimaryMouseButton &&
                HardwareKeyboard.instance.isControlPressed)) {
          action(event.position);
        }
      },
      child: child);

  Future<void> _trashMenu(LibraryModel model, Offset position,
      [TrashEntry? entry]) async {
    if (_menuShowing) return;
    _menuShowing = true;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
            position & const Size(1, 1), Offset.zero & overlay.size),
        items: entry == null
            ? const [
                PopupMenuItem(height: 30, value: 'empty', child: Text('Empty'))
              ]
            : const [
                PopupMenuItem(
                    height: 30, value: 'restore', child: Text('Restore')),
                PopupMenuItem(
                    height: 30,
                    value: 'purge',
                    child: Text('Delete Permanently'))
              ]);
    _menuShowing = false;
    if (action == 'restore') await model.run(() => model.restore(entry!));
    if (action == 'purge') await _confirmPurge(model, entry);
    if (action == 'empty') await _confirmPurge(model);
  }

  Future<void> _menu(
      LibraryModel model, Offset position, LibraryEntry? entry) async {
    if (entry == null && model.showingTrash) return _trashMenu(model, position);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final location = RelativeRect.fromRect(
        position & const Size(1, 1), Offset.zero & overlay.size);
    if (_menuShowing) return;
    _menuShowing = true;
    setState(() => _contextTarget = entry?.path);
    final action =
        await showMenu<String>(context: context, position: location, items: [
      if (entry == null || entry.isFolder) ...[
        const PopupMenuItem(height: 30, value: 'new', child: Text('New Note')),
        const PopupMenuItem(
            height: 30, value: 'folder', child: Text('New Folder')),
        const PopupMenuDivider(),
      ],
      if (entry != null) ...[
        if (!entry.isFolder)
          const PopupMenuItem(height: 30, value: 'open', child: Text('Open')),
        const PopupMenuItem(height: 30, value: 'rename', child: Text('Rename')),
        if (!entry.isFolder)
          const PopupMenuItem(
              height: 30, value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(
            enabled: false,
            child: PopupMenuButton<String>(
              tooltip: 'Move to',
              onSelected: (parent) {
                Navigator.pop(context);
                model.run(() => model.move(entry.path, parent));
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: model.service.root, child: const Text('On My Mac')),
                for (final folder in model.flatten().where((e) => e.isFolder))
                  PopupMenuItem(
                      value: folder.path,
                      enabled: folder.path != entry.path &&
                          !p.isWithin(entry.path, folder.path),
                      child: Text(
                          '${'  ' * (p.split(p.relative(folder.path, from: model.service.root)).length - 1)}${folder.name}')),
              ],
              child: const Row(children: [
                Expanded(child: Text('Move to')),
                Icon(Icons.chevron_right, size: 16)
              ]),
            )),
        if (!entry.isFolder)
          PopupMenuItem(
              enabled: false,
              child: PopupMenuButton<String>(
                tooltip: 'Export',
                onSelected: (format) {
                  Navigator.pop(context);
                  widget.onExport?.call(entry.path, format);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pdf', child: Text('PDF…')),
                  PopupMenuItem(value: 'docx', child: Text('Word (.docx)…')),
                  PopupMenuItem(value: 'md', child: Text('Markdown (.md)…'))
                ],
                child: const Row(children: [
                  Expanded(child: Text('Export')),
                  Icon(Icons.chevron_right, size: 16)
                ]),
              )),
        const PopupMenuDivider(),
        PopupMenuItem(
            height: 30, value: 'reveal', child: Text(fileManagerLabel())),
        if (widget.onRemove != null)
          const PopupMenuItem(
              height: 30, value: 'remove', child: Text('Remove from editor')),
        const PopupMenuDivider(),
        const PopupMenuItem(height: 30, value: 'delete', child: Text('Delete')),
      ],
      if (entry == null && model.removedPaths.isNotEmpty)
        const PopupMenuItem(
            value: 'showRemoved', child: Text('Show removed items')),
    ]);
    _menuShowing = false;
    if (mounted) setState(() => _contextTarget = null);
    if (action == null) return;
    if (action == 'remove') {
      await widget.onRemove?.call(entry!.path);
      return;
    }
    await model.run(() async {
      switch (action) {
        case 'open':
          widget.onOpen(entry!.path);
        case 'new':
          await model.create(parent: entry?.path ?? model.service.root);
        case 'folder':
          await model.create(
              folder: true, parent: entry?.path ?? model.service.root);
        case 'rename':
          model.startRename(entry!.path);
        case 'duplicate':
          await model.duplicate(entry!.path);
        case 'delete':
          await model.delete(entry!.path);
        case 'reveal':
          await revealFileLocation(entry!.path, isDirectory: entry.isFolder);
        case 'showRemoved':
          await model.showRemovedItems();
      }
    });
  }

  Widget _drop(LibraryModel model, String parent, Widget child) =>
      DragTarget<String>(
        onWillAcceptWithDetails: (details) =>
            details.data != parent && !p.isWithin(details.data, parent),
        onAcceptWithDetails: (details) =>
            model.run(() => model.move(details.data, parent)),
        builder: (context, candidates, rejected) => DecoratedBox(
          decoration: BoxDecoration(
              color: candidates.isEmpty
                  ? null
                  : _sidebarAccent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(6)),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    context.select<LibraryModel, Object>((m) => (
          m.entries,
          m.expanded.join('|'),
          m.renamePath,
          m.showingTrash,
          m.deleted,
          m.removedPaths.join('|'),
        ));
    final model = context.read<LibraryModel>();
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) => _key(model, event),
      child: _secondary(
          (position) => _menu(model, position, null),
          GestureDetector(
            onTap: () {
              if (!_menuShowing) _focus.requestFocus();
            },
            onSecondaryTapUp: (details) =>
                _menu(model, details.globalPosition, null),
            child: Material(
                color: AppColors.sidebar,
                child: Column(children: [
                  SizedBox(
                      height: 52,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Expanded(
                                child: Padding(
                              padding: EdgeInsets.only(left: 18),
                              child: Text('Chai Editor',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            )),
                            _addMenu(model, model.destination),
                            IconButton(
                                tooltip: 'Hide sidebar',
                                icon: const Icon(Icons.view_sidebar_outlined,
                                    size: 20),
                                onPressed: widget.onHide),
                          ])),
                  if (widget.externalTabs.isNotEmpty) ...[
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                            padding: EdgeInsets.fromLTRB(18, 8, 12, 4),
                            child: Text('Open files',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12)))),
                    ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * .25),
                        child: ListView(shrinkWrap: true, children: [
                          for (final tab in widget.externalTabs)
                            _externalRow(tab),
                        ])),
                  ],
                  Expanded(
                      child: model.showingTrash
                          ? Column(children: [
                              Row(children: [
                                const SizedBox(width: 16),
                                const Expanded(child: Text('Recently Deleted')),
                                TextButton(
                                    onPressed: model.deleted.isEmpty
                                        ? null
                                        : () => _confirmPurge(model),
                                    child: const Text('Empty'))
                              ]),
                              Expanded(
                                  child: ListView(children: [
                                for (final entry in model.deleted)
                                  _secondary(
                                      (position) =>
                                          _trashMenu(model, position, entry),
                                      ListTile(
                                          dense: true,
                                          title: Text(entry.name,
                                              overflow: TextOverflow.ellipsis),
                                          subtitle: Text(entry.isFolder
                                              ? 'Folder'
                                              : 'Note'),
                                          trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                    tooltip: 'Restore',
                                                    icon: const Icon(
                                                        Icons.restore,
                                                        size: 18),
                                                    onPressed: () => model.run(
                                                        () => model
                                                            .restore(entry))),
                                                IconButton(
                                                    tooltip:
                                                        'Delete Permanently',
                                                    icon: const Icon(
                                                        Icons
                                                            .delete_forever_outlined,
                                                        size: 18),
                                                    onPressed: () =>
                                                        _confirmPurge(
                                                            model, entry)),
                                              ]))),
                              ])),
                            ])
                          : ListView(
                              controller: _folderScroll,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              children: [
                                  if (widget.openFolders.isNotEmpty)
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(10, 8, 4, 4),
                                      child: Text('Open folders',
                                          style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12)),
                                    ),
                                  for (final path in widget.openFolders)
                                    OpenFolderRow(
                                      key: ValueKey(('open folder', path)),
                                      path: path,
                                      onOpenFile: widget.onOpen,
                                      onClose: widget.onCloseFolder == null
                                          ? null
                                          : () => widget.onCloseFolder!(path),
                                    ),
                                  _drop(
                                    model,
                                    model.service.root,
                                    const Padding(
                                      padding:
                                          EdgeInsets.fromLTRB(10, 12, 4, 8),
                                      child: Text('On My Mac',
                                          style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)),
                                    ),
                                  ),
                                  for (final entry in model.visible)
                                    _row(model, entry),
                                  const SizedBox(height: 80),
                                ])),
                  _secondary(
                      (position) => _trashMenu(model, position),
                      ListTile(
                          dense: true,
                          selected: model.showingTrash,
                          selectedColor: _sidebarAccent,
                          leading: const Icon(Icons.delete_outline, size: 20),
                          title: const Text('Recently Deleted'),
                          onTap: () {
                            _focus.requestFocus();
                            model.showingTrash = !model.showingTrash;
                            setState(() {});
                          })),
                ])),
          )),
    );
  }

  Future<void> _externalMenu(DocTab tab, Offset position) async {
    if (_menuShowing) return;
    _menuShowing = true;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
            position & const Size(1, 1), Offset.zero & overlay.size),
        items: [
          if (tab.filePath != null)
            PopupMenuItem(value: 'reveal', child: Text(fileManagerLabel())),
          const PopupMenuItem(
              value: 'close', child: Text('Remove from editor')),
        ]);
    _menuShowing = false;
    if (action == 'close') widget.onCloseExternal?.call(tab);
    if (action == 'reveal') {
      try {
        await revealFileLocation(tab.filePath!);
      } catch (error) {
        debugPrint('Reveal file: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Couldn’t open this file location.')));
        }
      }
    }
  }

  Widget _externalRow(DocTab tab) => _secondary(
        (position) => _externalMenu(tab, position),
        ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.description_outlined, size: 18),
            title: Text('${tab.title}${tab.needsSave ? ' •' : ''}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            onTap: () => widget.onOpenExternal?.call(tab),
            trailing: IconButton(
                tooltip: 'Remove from editor',
                icon: const Icon(Icons.close, size: 15),
                onPressed: () => widget.onCloseExternal?.call(tab))),
      );

  Widget _addMenu(LibraryModel model, String parent) =>
      PopupMenuButton<_AddAction>(
        tooltip: 'Add or open',
        requestFocus: false,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.add, size: 18),
        onSelected: (action) {
          switch (action) {
            case _AddAction.newNote:
              model.run(() => model.create(parent: parent));
            case _AddAction.newFolder:
              model.run(() => model.create(folder: true, parent: parent));
            case _AddAction.openFile:
              widget.onOpenFile();
            case _AddAction.openFolder:
              widget.onOpenFolder();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
              value: _AddAction.newNote, height: 30, child: Text('New Note')),
          PopupMenuItem(
              value: _AddAction.newFolder,
              height: 30,
              child: Text('New Folder')),
          PopupMenuDivider(),
          PopupMenuItem(
              value: _AddAction.openFile,
              height: 30,
              child: Text('Open File…')),
          PopupMenuItem(
              value: _AddAction.openFolder,
              height: 30,
              child: Text('Open Folder…')),
        ],
      );

  Widget _row(LibraryModel model, LibraryEntry entry) =>
      Selector<LibraryModel, (bool, bool, bool, bool)>(
        key: ValueKey(entry.path),
        selector: (_, m) => (
          m.selected == entry.path,
          m.renamePath == entry.path,
          m.expanded.contains(entry.path),
          _contextTarget == entry.path,
        ),
        builder: (_, value, child) => _HoverRow(
            onRest: entry.isFolder ? null : () => model.preload(entry.path),
            builder: (hover) => _rowContent(model, entry, hover)),
      );

  Widget _rowContent(LibraryModel model, LibraryEntry entry, bool hover) {
    final selected = model.selected == entry.path;
    final depth =
        p.split(p.relative(entry.path, from: model.service.root)).length - 1;
    final row = MouseRegion(
        onEnter: (_) {
          Future<void>.delayed(const Duration(milliseconds: 150), () {
            if (kLegacyHoverPreload && mounted && !entry.isFolder) {
              model.preload(entry.path);
            }
          });
        },
        child: GestureDetector(
          onSecondaryTapUp: (event) =>
              _menu(model, event.globalPosition, entry),
          onDoubleTap: () => model.startRename(entry.path),
          onTap: () {
            if (_menuShowing || HardwareKeyboard.instance.isControlPressed) {
              return;
            }
            _focus.requestFocus();
            final slow =
                DateTime.now().difference(_lastClick).inMilliseconds > 550;
            _lastClick = DateTime.now();
            if (selected && slow) {
              model.startRename(entry.path);
            } else if (entry.isFolder) {
              model.selectFolder(entry);
            } else {
              widget.onOpen(entry.path);
            }
          },
          child: Container(
              height: 32,
              margin: const EdgeInsets.symmetric(vertical: 1),
              padding: EdgeInsets.only(left: 4 + depth * 18, right: 8),
              decoration: BoxDecoration(
                  color: selected ? AppColors.selected : null,
                  border: _contextTarget == entry.path
                      ? Border.all(color: AppColors.textFaint)
                      : null,
                  borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                SizedBox(
                    width: 20,
                    child: entry.isFolder
                        ? AnimatedRotation(
                            turns:
                                model.expanded.contains(entry.path) ? .25 : 0,
                            duration: const Duration(milliseconds: 120),
                            child: Icon(Icons.chevron_right,
                                size: 16,
                                color: selected
                                    ? _sidebarAccent
                                    : AppColors.textFaint))
                        : null),
                Icon(
                    entry.isFolder
                        ? Icons.folder_outlined
                        : Icons.description_outlined,
                    size: 18,
                    color: selected ? _sidebarAccent : AppColors.textMuted),
                const SizedBox(width: 7),
                Expanded(
                    child: model.renamePath == entry.path
                        ? _RenameField(
                            key: ValueKey(entry.path),
                            name: entry.name,
                            onSave: (name) =>
                                model.run(() => model.rename(entry.path, name)),
                            onCancel: model.cancelRename)
                        : Text(entry.name,
                            style: TextStyle(
                                color:
                                    selected ? _sidebarAccent : AppColors.text,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis)),
                if (entry.isFolder)
                  SizedBox(
                      width: 28,
                      child: selected || hover
                          ? _addMenu(model, entry.path)
                          : Text('${entry.noteCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 12))),
                if (widget.onRemove != null)
                  IconButton(
                    tooltip: 'Remove from editor',
                    constraints:
                        const BoxConstraints.tightFor(width: 28, height: 28),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close, size: 15),
                    onPressed: () => widget.onRemove!(entry.path),
                  ),
              ])),
        ));
    final draggable = LongPressDraggable<String>(
        data: entry.path,
        delay: const Duration(milliseconds: 200),
        feedback: Material(
            color: AppColors.selected,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
                padding: const EdgeInsets.all(8), child: Text(entry.name))),
        child: row);
    return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton ||
              (event.buttons == kPrimaryMouseButton &&
                  HardwareKeyboard.instance.isControlPressed)) {
            _menu(model, event.position, entry);
          }
        },
        child:
            entry.isFolder ? _drop(model, entry.path, draggable) : draggable);
  }
}

class _RenameField extends StatefulWidget {
  const _RenameField(
      {super.key,
      required this.name,
      required this.onSave,
      required this.onCancel});
  final String name;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;
  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final _controller = TextEditingController(text: widget.name)
    ..selection =
        TextSelection(baseOffset: 0, extentOffset: widget.name.length);
  final _focus = FocusNode();
  bool _finished = false;
  void _save() {
    if (!_finished) {
      _finished = true;
      widget.onSave(_controller.text);
    }
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void dispose() {
    _finished = true;
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _finished = true;
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
          autofocus: true,
          focusNode: _focus,
          controller: _controller,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none),
          onSubmitted: (_) => _save(),
          onTapOutside: (_) => _save()));
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.builder, this.onRest});
  final VoidCallback? onRest;
  final Widget Function(bool hover) builder;
  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool hover = false;
  Timer? timer;
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
      onEnter: (_) {
        timer?.cancel();
        timer = Timer(
            const Duration(milliseconds: 150), () => widget.onRest?.call());
        setState(() => hover = true);
      },
      onExit: (_) {
        timer?.cancel();
        setState(() => hover = false);
      },
      child: widget.builder(hover));
}
