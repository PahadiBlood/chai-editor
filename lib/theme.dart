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
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const transparent = Color(0x00000000);
  static const sidebar = Color(0xFF101012);
  static const hover = Color(0xFF17171A);
  static const selected = Color(0xFF242428);
  static const textFaint = Color(0xFF6B6B70);
  static const accent = white;
  static const codeBackground = Color(0xFF151517);
  static const codeText = Color(0xFFE6E6E6);
  static const inlineCodeBackground = Color(0xFF1E1E21);
  static const inlineCode = codeText;
  static const link = white;
  static const selection = Color(0x33FFFFFF);
}

const String serifFont = 'Georgia';
const String monoFont = 'Menlo';

/// The only chromatic UI colours belong to code tokens. Printing uses the same
/// token categories on paper; inline code continues to use AppColors.inlineCode.
class CodeSyntaxColors {
  const CodeSyntaxColors(
      {required this.keyword,
      required this.string,
      required this.number,
      required this.comment,
      required this.function,
      required this.type,
      required this.tag,
      required this.attribute,
      required this.variable,
      required this.plain});

  final Color keyword,
      string,
      number,
      comment,
      function,
      type,
      tag,
      attribute,
      variable,
      plain;

  static const dark = CodeSyntaxColors(
      keyword: Color(0xFFFF7B72),
      string: Color(0xFFA5D6FF),
      number: Color(0xFF79C0FF),
      comment: Color(0xFF8B949E),
      function: Color(0xFFD2A8FF),
      type: Color(0xFFFFA657),
      tag: Color(0xFF7EE787),
      attribute: Color(0xFF79C0FF),
      variable: Color(0xFFFFA657),
      plain: AppColors.codeText);
  static const light = CodeSyntaxColors(
      keyword: Color(0xFFCF222E),
      string: Color(0xFF0A3069),
      number: Color(0xFF0550AE),
      comment: Color(0xFF6E7781),
      function: Color(0xFF8250DF),
      type: Color(0xFF953800),
      tag: Color(0xFF116329),
      attribute: Color(0xFF0550AE),
      variable: Color(0xFF953800),
      plain: Color(0xFF1F2328));

  Color forScope(String scope) {
    final parts = scope.split(RegExp(r'[. ]'));
    if (parts.contains('comment') || parts.contains('doctag')) return comment;
    if (parts.contains('keyword')) return keyword;
    if (parts.contains('string') || parts.contains('regexp')) return string;
    if (parts.contains('number') || parts.contains('literal')) return number;
    if (parts.contains('class') || parts.contains('type')) return type;
    if (parts.contains('title') || parts.contains('function')) return function;
    if (parts.contains('attr') || parts.contains('attribute')) return attribute;
    if (parts.contains('tag') || parts.contains('name')) return tag;
    if (parts.contains('variable') || parts.contains('built_in')) {
      return variable;
    }
    return plain;
  }
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.white,
      onPrimary: AppColors.black,
      secondary: AppColors.textMuted,
      onSecondary: AppColors.black,
      tertiary: AppColors.textMuted,
      onTertiary: AppColors.black,
      error: AppColors.white,
      onError: AppColors.black,
      surface: AppColors.background,
      onSurface: AppColors.text,
      surfaceTint: AppColors.transparent,
      outline: AppColors.border,
    ),
    focusColor: AppColors.selected,
    hoverColor: AppColors.hover,
    highlightColor: AppColors.selected,
    splashColor: AppColors.selection,
    textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.white,
        selectionColor: AppColors.selection,
        selectionHandleColor: AppColors.white),
    iconTheme: const IconThemeData(color: AppColors.textMuted, size: 19),
    inputDecorationTheme: const InputDecorationTheme(
        focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.textMuted))),
    snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.selected,
        contentTextStyle: TextStyle(color: AppColors.text)),
    dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.sidebar,
        surfaceTintColor: AppColors.transparent),
    dividerColor: AppColors.border,
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.sidebar,
      surfaceTintColor: AppColors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 13),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

EditorStyle buildEditorStyle({bool compact = false}) {
  return EditorStyle.desktop(
    padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 48, vertical: 8),
    maxWidth: 860,
    cursorColor: AppColors.accent,
    selectionColor: AppColors.selection,
    textStyleConfiguration: TextStyleConfiguration(
      text: const TextStyle(
        fontSize: 16.5,
        letterSpacing: -0.2,
        wordSpacing: -0.4,
        color: AppColors.text,
      ),
      bold: const TextStyle(fontWeight: FontWeight.w700),
      code: const TextStyle(
        fontFamily: monoFont,
        fontSize: 14,
        letterSpacing: 0,
        wordSpacing: 0,
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

const kMonochromeEditorMenus =
    bool.fromEnvironment('CHAI_MONOCHROME_MENUS', defaultValue: true);
const monochromeSelectionMenu = SelectionMenuStyle(
  selectionMenuBackgroundColor: AppColors.sidebar,
  selectionMenuItemTextColor: AppColors.text,
  selectionMenuItemIconColor: AppColors.textMuted,
  selectionMenuItemSelectedTextColor: AppColors.white,
  selectionMenuItemSelectedIconColor: AppColors.white,
  selectionMenuItemSelectedColor: AppColors.selected,
  selectionMenuUnselectedLabelColor: AppColors.textMuted,
  selectionMenuDividerColor: AppColors.border,
  selectionMenuLinkBorderColor: AppColors.border,
  selectionMenuInvalidLinkColor: AppColors.textMuted,
  selectionMenuButtonColor: AppColors.selected,
  selectionMenuButtonTextColor: AppColors.white,
  selectionMenuButtonIconColor: AppColors.white,
  selectionMenuButtonBorderColor: AppColors.border,
  selectionMenuTabIndicatorColor: AppColors.white,
);
const monochromeFloatingToolbar = FloatingToolbarStyle(
  toolbarActiveColor: AppColors.white,
  backgroundColor: AppColors.sidebar,
);

String syntaxColorHex(Color color) => (color.toARGB32() & 0xFFFFFF)
    .toRadixString(16)
    .padLeft(6, '0')
    .toUpperCase();
