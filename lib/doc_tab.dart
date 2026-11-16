import 'dart:async';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

import 'markdown_io.dart';

/// One open document: its editor state, its file (if saved) and a dirty flag.
class DocTab {
  DocTab({
    required String markdown,
    Document? document,
    this.filePath,
    this.libraryManaged = false,
    required VoidCallback onChanged,
  }) : editorState = EditorState(
            document: document ?? markdownToEditorDocument(markdown)) {
    savePath = libraryManaged ? null : filePath;
    _savedDestinationMarkdown = savePath == null ? null : toMarkdown();
    scrollController = EditorScrollController(
      editorState: editorState,
      shrinkWrap: false,
    );
    editorState.selectionNotifier.addListener(_rememberSelection);
    _subscription = editorState.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after) {
        revision++;
        dirty = true;
        onChanged();
      }
    });
  }

  final EditorState editorState;
  final focusNode = FocusNode(debugLabel: 'document body');
  Selection? rememberedSelection;
  late final EditorScrollController scrollController;
  late final StreamSubscription<dynamic> _subscription;

  String? filePath;
  bool dirty = false;
  int revision = 0;
  String? savePath;
  String? _savedDestinationMarkdown;
  bool get needsSave =>
      dirty || (savePath != null && _savedDestinationMarkdown != toMarkdown());

  void rememberSavedDestination(String path, String markdown) {
    savePath = path;
    _savedDestinationMarkdown = markdown;
    if (!libraryManaged) {
      filePath = path;
      dirty = toMarkdown() != markdown;
    }
  }

  void discardPendingChanges() => dirty = false;

  final bool libraryManaged;

  String get title {
    final path = filePath;
    if (path == null) return 'Untitled';
    return path.split(Platform.pathSeparator).last;
  }

  String toMarkdown() => editorDocumentToMarkdown(editorState.document);

  void _rememberSelection() {
    if (editorState.selection != null) {
      rememberedSelection = editorState.selection;
    }
  }

  void dispose() {
    focusNode.dispose();
    editorState.selectionNotifier.removeListener(_rememberSelection);
    _subscription.cancel();
    scrollController.dispose();
    editorState.dispose();
  }
}
