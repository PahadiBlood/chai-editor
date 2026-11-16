import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../library/library_model.dart';
import '../library/library_service.dart';

const _yellow = Color(0xFFFFD60A);

class LibrarySidebar extends StatefulWidget {
  const LibrarySidebar({super.key, required this.onOpen, required this.onHide});
  final ValueChanged<String> onOpen;
  final VoidCallback onHide;
  @override
  State<LibrarySidebar> createState() => _LibrarySidebarState();
}

class _LibrarySidebarState extends State<LibrarySidebar> {
  final _focus = FocusNode(debugLabel: 'library sidebar');
  DateTime _lastClick = DateTime(2000);
  @override
  void dispose() {
    _focus.dispose();
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

  Future<void> _menu(
      LibraryModel model, Offset position, LibraryEntry? entry) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final location = RelativeRect.fromRect(
        position & const Size(1, 1), Offset.zero & overlay.size);
    final action =
        await showMenu<String>(context: context, position: location, items: [
      if (entry == null || entry.isFolder) ...[
        const PopupMenuItem(value: 'new', child: Text('New Note')),
        PopupMenuItem(
            value: 'folder',
            child: Text(entry == null ? 'New Folder' : 'New Sub-folder')),
      ],
      if (entry != null) ...[
        if (!entry.isFolder)
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (!entry.isFolder)
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
                      value: model.service.root,
                      child: const Text('On My Mac')),
                  for (final folder in model.flatten().where((e) => e.isFolder))
                    PopupMenuItem(
                        value: folder.path,
                        child: Text(
                            '${'  ' * (p.split(p.relative(folder.path, from: model.service.root)).length - 1)}${folder.name}')),
                ],
                child: const ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Move to'),
                    trailing: Icon(Icons.chevron_right)),
              )),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
        const PopupMenuItem(value: 'reveal', child: Text('Show in Finder')),
      ],
    ]);
    if (action == null) return;
    await model.run(() async {
      switch (action) {
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
          final uri = Uri.directory(
              entry!.isFolder ? entry.path : p.dirname(entry.path));
          if (!await launchUrl(uri)) {
            throw StateError('Could not open the file manager');
          }
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
              color: candidates.isEmpty ? null : _yellow.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(6)),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final model = context.watch<LibraryModel>();
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) => _key(model, event),
      child: GestureDetector(
        onTap: _focus.requestFocus,
        onSecondaryTapUp: (details) =>
            _menu(model, details.globalPosition, null),
        child: Material(
            color: const Color(0xFF1C1C1E),
            child: Column(children: [
              SizedBox(
                  height: 52,
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    IconButton(
                        tooltip: 'New folder',
                        icon: const Icon(Icons.create_new_folder_outlined,
                            size: 20),
                        onPressed: () =>
                            model.run(() => model.create(folder: true))),
                    IconButton(
                        tooltip: 'Hide sidebar',
                        icon: const Icon(Icons.view_sidebar_outlined, size: 20),
                        onPressed: widget.onHide),
                  ])),
              _drop(
                  model,
                  model.service.root,
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
                        child: Text('On My Mac',
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ))),
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
                              ListTile(
                                  dense: true,
                                  title: Text(entry.name,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle:
                                      Text(entry.isFolder ? 'Folder' : 'Note'),
                                  trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                            tooltip: 'Restore',
                                            icon: const Icon(Icons.restore,
                                                size: 18),
                                            onPressed: () => model.run(
                                                () => model.restore(entry))),
                                        IconButton(
                                            tooltip: 'Delete Permanently',
                                            icon: const Icon(
                                                Icons.delete_forever_outlined,
                                                size: 18),
                                            onPressed: () =>
                                                _confirmPurge(model, entry)),
                                      ])),
                          ])),
                        ])
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                              for (final entry in model.visible)
                                _row(model, entry),
                              const SizedBox(height: 80),
                            ])),
              ListTile(
                  dense: true,
                  selected: model.showingTrash,
                  selectedColor: _yellow,
                  leading: const Icon(Icons.delete_outline, size: 20),
                  title: const Text('Recently Deleted'),
                  onTap: () {
                    _focus.requestFocus();
                    model.showingTrash = !model.showingTrash;
                    setState(() {});
                  }),
            ])),
      ),
    );
  }

  Widget _row(LibraryModel model, LibraryEntry entry) {
    final selected = model.selected == entry.path;
    final depth =
        p.split(p.relative(entry.path, from: model.service.root)).length - 1;
    final row = GestureDetector(
      onSecondaryTapUp: (event) => _menu(model, event.globalPosition, entry),
      onDoubleTap: () => model.startRename(entry.path),
      onTap: () {
        _focus.requestFocus();
        final slow = DateTime.now().difference(_lastClick).inMilliseconds > 550;
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
              color: selected ? const Color(0xFF333335) : null,
              borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            SizedBox(
                width: 20,
                child: entry.isFolder
                    ? AnimatedRotation(
                        turns: model.expanded.contains(entry.path) ? .25 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: Icon(Icons.chevron_right,
                            size: 16, color: selected ? _yellow : Colors.grey))
                    : null),
            Icon(
                entry.isFolder
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
                size: 18,
                color: selected ? _yellow : Colors.grey.shade400),
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
                            color: selected ? _yellow : Colors.white70,
                            fontSize: 13),
                        overflow: TextOverflow.ellipsis)),
            if (entry.isFolder)
              Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('${entry.noteCount}',
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12))),
          ])),
    );
    final draggable = LongPressDraggable<String>(
        data: entry.path,
        delay: const Duration(milliseconds: 200),
        feedback: Material(
            color: const Color(0xFF333335),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
                padding: const EdgeInsets.all(8), child: Text(entry.name))),
        child: row);
    return entry.isFolder ? _drop(model, entry.path, draggable) : draggable;
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
