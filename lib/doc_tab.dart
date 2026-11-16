import 'dart:async';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';

import 'markdown_io.dart';

/// One open document: its editor state, its file (if saved) and a dirty flag.
class DocTab {
  DocTab({
    required String markdown,
    this.filePath,
    required VoidCallback onChanged,
  }) : editorState = EditorState(document: markdownToEditorDocument(markdown)) {
    scrollController = EditorScrollController(
      editorState: editorState,
      shrinkWrap: false,
    );
    _subscription = editorState.transactionStream.listen((_) {
      if (!dirty) {
        dirty = true;
        onChanged();
      }
    });
  }

  final EditorState editorState;
  late final EditorScrollController scrollController;
  late final StreamSubscription<dynamic> _subscription;

  String? filePath;
  bool dirty = false;

  String get title {
    final path = filePath;
    if (path == null) return 'Untitled';
    return path.split(Platform.pathSeparator).last;
  }

  String toMarkdown() => editorDocumentToMarkdown(editorState.document);

  void dispose() {
    _subscription.cancel();
    scrollController.dispose();
    editorState.dispose();
  }
}
