import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../markdown_io.dart';
import '../theme.dart';

/// Browses a picked directory in place with no library file operations.
class OpenFolderRow extends StatefulWidget {
  const OpenFolderRow({
    super.key,
    required this.path,
    required this.onOpenFile,
    this.onClose,
    this.depth = 0,
  });

  final String path;
  final ValueChanged<String> onOpenFile;
  final VoidCallback? onClose;
  final int depth;

  @override
  State<OpenFolderRow> createState() => _OpenFolderRowState();
}

class _OpenFolderRowState extends State<OpenFolderRow> {
  Future<List<FileSystemEntity>?>? _contents;

  @override
  void initState() {
    super.initState();
    if (widget.depth == 0) _contents = _listContents();
  }

  Future<List<FileSystemEntity>?> _listContents() async {
    final List<FileSystemEntity> entries;
    try {
      entries =
          await Directory(widget.path).list(followLinks: false).where((entry) {
        if (p.basename(entry.path).startsWith('.')) return false;
        if (entry is Directory) return true;
        final extension = p.extension(entry.path).toLowerCase();
        return entry is File &&
            markdownFileExtensions.any((suffix) => extension == '.$suffix');
      }).toList();
    } on FileSystemException catch (error) {
      debugPrint('Read open folder: $error');
      return null;
    }
    entries.sort((a, b) {
      if ((a is Directory) != (b is Directory)) return a is Directory ? -1 : 1;
      return p.basename(a.path).toLowerCase().compareTo(
            p.basename(b.path).toLowerCase(),
          );
    });
    return entries;
  }

  EdgeInsets _padding(int depth) =>
      EdgeInsets.only(left: 8 + 14.0 * depth.clamp(0, 5), right: 4);

  @override
  Widget build(BuildContext context) {
    final contents = _contents;
    final name = p.basename(widget.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: _padding(widget.depth),
          minLeadingWidth: 18,
          horizontalTitleGap: 6,
          leading: Icon(
              contents == null ? Icons.chevron_right : Icons.expand_more,
              size: 18),
          title: Tooltip(
            message: widget.path,
            child: Text(name.isEmpty ? widget.path : name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          onTap: () {
            final next = contents == null ? _listContents() : null;
            setState(() {
              _contents = next;
            });
          },
          trailing: widget.onClose == null
              ? null
              : IconButton(
                  tooltip: 'Close folder',
                  icon: const Icon(Icons.close, size: 15),
                  onPressed: widget.onClose),
        ),
        if (contents != null)
          FutureBuilder<List<FileSystemEntity>?>(
            future: contents,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator(minHeight: 1);
              }
              final entries = snapshot.data;
              if (entries == null || entries.isEmpty) {
                return Padding(
                  padding: _padding(widget.depth + 1),
                  child: Text(
                    entries == null ? 'Couldn’t read folder' : 'No documents',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                  ),
                );
              }
              return Column(
                children: [
                  for (final entry in entries)
                    if (entry is Directory)
                      OpenFolderRow(
                        key: ValueKey(entry.path),
                        path: entry.path,
                        depth: widget.depth + 1,
                        onOpenFile: widget.onOpenFile,
                      )
                    else
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: _padding(widget.depth + 1),
                        minLeadingWidth: 18,
                        horizontalTitleGap: 6,
                        leading:
                            const Icon(Icons.description_outlined, size: 18),
                        title: Text(p.basename(entry.path),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => widget.onOpenFile(entry.path),
                      ),
                ],
              );
            },
          ),
      ],
    );
  }
}
