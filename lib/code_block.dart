import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import 'theme.dart';
import 'code_syntax.dart';
import 'clipboard_writer.dart';

/// appflowy_editor has no code block, so this file adds one:
///  - the block itself (CodeBlockComponentBuilder)
///  - a Markdown reader for ```fences``` (MarkdownCodeBlockParser)
///  - an Enter key rule so Enter adds a new line inside the block
///    (press Enter twice at the end to leave it)

class CodeBlockKeys {
  const CodeBlockKeys._();

  static const String type = 'code';
  static const String delta = blockComponentDelta;
  static const String language = 'language';
}

const List<String> codeLanguages = ['', ...commonCodeLanguages];

Node codeBlockNode({String text = '', String language = ''}) {
  return Node(
    type: CodeBlockKeys.type,
    attributes: {
      CodeBlockKeys.delta: (Delta()..insert(text)).toJson(),
      CodeBlockKeys.language: normalizeCodeLanguage(language),
    },
  );
}

class CodeBlockComponentBuilder extends BlockComponentBuilder {
  CodeBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;

    return CodeBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.delta != null;
}

class CodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const CodeBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CodeBlockComponentWidget> createState() =>
      _CodeBlockComponentWidgetState();
}

class _CodeBlockComponentWidgetState extends State<CodeBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'flowy_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: CodeBlockKeys.type,
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  late final editorState = Provider.of<EditorState>(context, listen: false);

  static const TextStyle _codeStyle = TextStyle(
    fontFamily: monoFont,
    fontSize: 13.5,
    height: 1.55,
    color: AppColors.codeText,
  );

  String get _language =>
      (widget.node.attributes[CodeBlockKeys.language] as String?) ?? '';

  Timer? _highlightDebounce;
  late HighlightedCode _highlighted;
  (String, String)? _pending;

  @override
  void initState() {
    super.initState();
    _highlighted = CodeHighlighter.shared
        .highlight(node.delta?.toPlainText() ?? '', _language);
    _pending = (_highlighted.text, normalizeCodeLanguage(_language));
  }

  @override
  void dispose() {
    _highlightDebounce?.cancel();
    super.dispose();
  }

  TextSpan _decorateCode(TextSpan original) {
    final text = node.delta?.toPlainText() ?? '';
    final language = normalizeCodeLanguage(_language);
    // appflowy also decorates individual delta leaves. Only reconstruct the
    // complete span; a partial leaf must never duplicate the whole block.
    if (original.toPlainText() != text) {
      return original.updateTextStyle(_codeStyle);
    }
    final key = (text, language);
    if (_pending != key) {
      _pending = key;
      _highlightDebounce?.cancel();
      _highlightDebounce = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() {
          _highlighted = CodeHighlighter.shared.highlight(text, language);
        });
      });
    }
    if (_highlighted.text != text) {
      // Keep fresh characters at their correct offsets while awaiting tokens.
      return TextSpan(text: text, style: _codeStyle);
    }
    return _highlighted.toTextSpan(_codeStyle);
  }

  Future<void> _setLanguage(String language) async {
    final transaction = editorState.transaction
      ..updateNode(widget.node, {CodeBlockKeys.language: language});
    await editorState.apply(transaction);
    _highlightDebounce?.cancel();
    _pending = null;
    if (mounted) {
      setState(() {
        _highlighted = CodeHighlighter.shared
            .highlight(node.delta?.toPlainText() ?? '', language);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );

    Widget child = Container(
      width: double.infinity,
      alignment: alignment,
      decoration: BoxDecoration(
        color: AppColors.codeBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LanguageMenu(
            language: _language,
            detectedLanguage: _highlighted.text == node.delta?.toPlainText()
                ? _highlighted.detectedLanguage
                : null,
            onSelected: _setLanguage,
            onCopy: () => unawaited((enableRichCopy
                    ? writeDocumentClipboard(Document(
                        root: Node(type: 'page', children: [node.copyWith()]),
                      ))
                    : Clipboard.setData(
                        ClipboardData(text: node.delta?.toPlainText() ?? '')))
                .catchError((Object error, StackTrace stack) {
              FlutterError.reportError(FlutterErrorDetails(
                  exception: error, stack: stack, library: 'Chai code copy'));
            })),
          ),
          const SizedBox(height: 4),
          AppFlowyRichText(
            key: forwardKey,
            delegate: this,
            node: widget.node,
            editorState: editorState,
            placeholderText: ' ',
            textSpanDecorator: _decorateCode,
            placeholderTextSpanDecorator: (textSpan) =>
                textSpan.updateTextStyle(_codeStyle),
            textDirection: textDirection,
            cursorColor: editorState.editorStyle.cursorColor,
            selectionColor: editorState.editorStyle.selectionColor,
            cursorWidth: editorState.editorStyle.cursorWidth,
          ),
        ],
      ),
    );

    child = Container(
      key: blockComponentKey,
      padding: padding,
      child: child,
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
      ],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({
    required this.language,
    required this.onSelected,
    required this.onCopy,
    this.detectedLanguage,
  });

  final String language;
  final String? detectedLanguage;
  final ValueChanged<String> onSelected;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: 12,
      color: AppColors.textMuted,
      fontFamily: monoFont,
    );

    return Row(
      children: [
        PopupMenuButton<String>(
          tooltip: 'Language',
          padding: EdgeInsets.zero,
          onSelected: onSelected,
          itemBuilder: (_) => [
            for (final lang in codeLanguages)
              PopupMenuItem<String>(
                value: lang,
                height: 32,
                child: Text(lang.isEmpty ? 'auto' : lang),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  normalizeCodeLanguage(language).isEmpty
                      ? (detectedLanguage == null
                          ? 'auto'
                          : 'auto: $detectedLanguage')
                      : language,
                  style: labelStyle),
              const Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
            padding: EdgeInsets.all(2),
            child: Icon(
              Icons.copy_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Reads ```fenced``` code from Markdown into code blocks.
class MarkdownCodeBlockParser extends CustomMarkdownParser {
  const MarkdownCodeBlockParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'pre') {
      return [];
    }

    var language = '';
    var text = element.textContent;

    final children = element.children;
    if (children != null &&
        children.isNotEmpty &&
        children.first is md.Element) {
      final code = children.first as md.Element;
      final cls = code.attributes['class'] ?? '';
      if (cls.startsWith('language-')) {
        language = cls.substring('language-'.length);
      }
      text = code.textContent;
    }

    if (text.endsWith('\n')) {
      text = text.substring(0, text.length - 1);
    }

    return [codeBlockNode(text: text, language: language)];
  }
}

/// Enter inside a code block adds a new line instead of a new block.
/// Pressing Enter on an empty last line leaves the block.
final CharacterShortcutEvent codeBlockEnter = CharacterShortcutEvent(
  key: 'new line inside a code block',
  character: '\n',
  handler: (editorState) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return false;
    }

    final node = editorState.getNodeAtPath(selection.end.path);
    if (node == null || node.type != CodeBlockKeys.type) {
      return false;
    }

    final text = node.delta?.toPlainText() ?? '';
    final offset = selection.end.offset;
    final transaction = editorState.transaction;

    if (offset == text.length && text.endsWith('\n')) {
      transaction
        ..deleteText(node, offset - 1, 1)
        ..insertNode(node.path.next, paragraphNode());
      transaction.afterSelection = Selection.collapsed(
        Position(path: node.path.next),
      );
    } else {
      transaction.insertText(node, offset, '\n');
      transaction.afterSelection = Selection.collapsed(
        Position(path: node.path, offset: offset + 1),
      );
    }

    await editorState.apply(transaction);
    return true;
  },
);

/// The "Code block" entry for the "/" menu.
final SelectionMenuItem codeBlockMenuItem = SelectionMenuItem.node(
  getName: () => 'Code block',
  keywords: ['code', 'codeblock', 'snippet', 'fence'],
  iconData: Icons.code,
  nodeBuilder: (editorState, context) => codeBlockNode(),
  replace: (editorState, node) => node.delta?.isEmpty ?? false,
  updateSelection: (editorState, path, replaced, insertedBefore) {
    return Selection.collapsed(Position(path: path));
  },
);
