import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'code_block.dart';

/// Colours and fonts. Dark theme, serif headings, monospaced code.
/// Georgia and Menlo ship with macOS, so no font assets are needed.
class AppColors {
  static const background = Color(0xFF0B0B0C);
  static const toolbar = Color(0xFF0B0B0C);
  static const border = Color(0xFF26262A);
  static const text = Color(0xFFF2F2F2);
  static const textMuted = Color(0xFF9A9AA0);
  static const accent = Color(0xFF7AA2F7);
  static const codeBackground = Color(0xFF151517);
  static const codeText = Color(0xFFE6E6E6);
  static const inlineCodeBackground = Color(0xFF1E1E21);
  static const inlineCode = Color(0xFFF0A868);
  static const link = Color(0xFF7AA2F7);
  static const selection = Color(0x553B82F6);
}

const String serifFont = 'Georgia';
const String monoFont = 'Menlo';

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      surface: AppColors.background,
    ),
    dividerColor: AppColors.border,
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF1B1B1E),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 13),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

EditorStyle buildEditorStyle() {
  return EditorStyle.desktop(
    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
    maxWidth: 860,
    cursorColor: AppColors.accent,
    selectionColor: AppColors.selection,
    textStyleConfiguration: TextStyleConfiguration(
      text: const TextStyle(fontSize: 16.5, color: AppColors.text),
      bold: const TextStyle(fontWeight: FontWeight.w700),
      code: const TextStyle(
        fontFamily: monoFont,
        fontSize: 14,
        color: AppColors.inlineCode,
        backgroundColor: AppColors.inlineCodeBackground,
      ),
      href: const TextStyle(
        color: AppColors.link,
        decoration: TextDecoration.underline,
      ),
      lineHeight: 1.6,
    ),
  );
}

Map<String, BlockComponentBuilder> buildBlockBuilders() {
  const headingSizes = [38.0, 28.0, 22.0, 19.0, 17.0, 16.0];
  const headingTop = [28.0, 22.0, 18.0, 14.0, 12.0, 10.0];

  int levelOf(Node node) =>
      (node.attributes[HeadingBlockKeys.level] as int?) ?? 1;

  return {
    ...standardBlockComponentBuilderMap,
    HeadingBlockKeys.type: HeadingBlockComponentBuilder(
      configuration: standardBlockComponentConfiguration.copyWith(
        placeholderText: (node) => 'Heading ${levelOf(node)}',
        padding: (node) => EdgeInsets.only(
          top: headingTop[(levelOf(node) - 1).clamp(0, 5).toInt()],
          bottom: 6,
        ),
      ),
      textStyleBuilder: (level) => TextStyle(
        fontFamily: serifFont,
        fontSize: headingSizes[(level - 1).clamp(0, 5).toInt()],
        fontWeight: FontWeight.w400,
        height: 1.25,
        color: AppColors.text,
      ),
    ),
    CodeBlockKeys.type: CodeBlockComponentBuilder(
      configuration: standardBlockComponentConfiguration.copyWith(
        placeholderText: (_) => ' ',
        padding: (_) => const EdgeInsets.symmetric(vertical: 8),
      ),
    ),
  };
}
