import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'editor_page.dart';
import 'library/library_service.dart';
import 'theme.dart';

void main() {
  runApp(const ChaiEditorApp());
}

class ChaiEditorApp extends StatelessWidget {
  const ChaiEditorApp(
      {super.key, this.enableLibrary = true, this.libraryService});
  final bool enableLibrary;
  final LibraryService? libraryService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chai Editor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.dark,
      darkTheme: buildTheme(),
      // appflowy_editor needs its own localisation delegate.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        AppFlowyEditorLocalizations.delegate,
      ],
      supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
      home: EditorPage(
          enableLibrary: enableLibrary, libraryService: libraryService),
    );
  }
}
