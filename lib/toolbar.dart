import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'actions.dart';
import 'doc_tab.dart';
import 'paste.dart';
import 'theme.dart';

enum _TabAction { newTab, open, save, saveAs, closeTab }

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.editing,
    required this.onSelectTab,
    required this.onNew,
    required this.onOpen,
    required this.onSave,
    required this.onSaveAs,
    required this.onCloseTab,
    required this.onPickImage,
    required this.onEditingChanged,
  });

  final List<DocTab> tabs;
  final int currentIndex;
  final bool editing;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onCloseTab;
  final VoidCallback onPickImage;
  final ValueChanged<bool> onEditingChanged;

  DocTab get _tab => tabs[currentIndex];
  EditorState get _state => _tab.editorState;

  @override
  Widget build(BuildContext context) {
    // ExcludeFocus keeps the cursor in the document when a button is clicked.
    return ExcludeFocus(
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: AppColors.toolbar,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabMenu(),
                    const _Divider(),
                    _buildTextStyleMenu(),
                    _buildInlineButtons(),
                    const _Divider(),
                    _buildBlockButtons(),
                    const _Divider(),
                    _buildInsertButtons(),
                  ],
                ),
              ),
            ),
            _ToolButton(
              icon: Icons.folder_open_rounded,
              tooltip: 'Open  ⌘O',
              onPressed: onOpen,
            ),
            _ToolButton(
              icon: Icons.save_outlined,
              tooltip: 'Save  ⌘S',
              onPressed: onSave,
            ),
            const SizedBox(width: 6),
            _buildModeMenu(),
          ],
        ),
      ),
    );
  }

  // ---- Tabs and file menu -------------------------------------------------

  Widget _buildTabMenu() {
    return PopupMenuButton<Object>(
      tooltip: 'Tabs and file',
      onSelected: (value) {
        if (value is int) {
          onSelectTab(value);
          return;
        }
        switch (value as _TabAction) {
          case _TabAction.newTab:
            onNew();
          case _TabAction.open:
            onOpen();
          case _TabAction.save:
            onSave();
          case _TabAction.saveAs:
            onSaveAs();
          case _TabAction.closeTab:
            onCloseTab();
        }
      },
      itemBuilder: (_) => [
        for (var i = 0; i < tabs.length; i++)
          PopupMenuItem<Object>(
            value: i,
            height: 34,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: i == currentIndex
                      ? const Icon(Icons.check, size: 14)
                      : null,
                ),
                Flexible(
                  child: Text(
                    tabs[i].title + (tabs[i].dirty ? '  •' : ''),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: _TabAction.newTab,
          height: 34,
          child: Text('New tab        ⌘N'),
        ),
        const PopupMenuItem<Object>(
          value: _TabAction.open,
          height: 34,
          child: Text('Open…        ⌘O'),
        ),
        const PopupMenuItem<Object>(
          value: _TabAction.save,
          height: 34,
          child: Text('Save        ⌘S'),
        ),
        const PopupMenuItem<Object>(
          value: _TabAction.saveAs,
          height: 34,
          child: Text('Save as…        ⇧⌘S'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: _TabAction.closeTab,
          height: 34,
          child: Text('Close tab'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _tab.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (_tab.dirty)
                const Padding(
                  padding: EdgeInsets.only(left: 5),
                  child: Icon(Icons.circle, size: 7, color: AppColors.accent),
                ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Text style (paragraph / headings) ---------------------------------

  Widget _buildTextStyleMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Text style',
      enabled: editing,
      onSelected: (value) {
        switch (value) {
          case 'p':
            toParagraph(_state);
          case 'h1':
            toHeading(_state, 1);
          case 'h2':
            toHeading(_state, 2);
          case 'h3':
            toHeading(_state, 3);
          case 'quote':
            toQuote(_state);
          case 'code':
            toCodeBlock(_state);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'p', height: 34, child: Text('Paragraph')),
        PopupMenuItem(
          value: 'h1',
          height: 38,
          child: Text(
            'Heading 1',
            style: TextStyle(fontFamily: serifFont, fontSize: 20),
          ),
        ),
        PopupMenuItem(
          value: 'h2',
          height: 36,
          child: Text(
            'Heading 2',
            style: TextStyle(fontFamily: serifFont, fontSize: 17),
          ),
        ),
        PopupMenuItem(
          value: 'h3',
          height: 34,
          child: Text(
            'Heading 3',
            style: TextStyle(fontFamily: serifFont, fontSize: 15),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(value: 'quote', height: 34, child: Text('Quote')),
        PopupMenuItem(value: 'code', height: 34, child: Text('Code block')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.text_fields_rounded,
              size: 20,
              color: editing ? AppColors.text : AppColors.textMuted,
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  // ---- Inline formatting --------------------------------------------------

  Widget _buildInlineButtons() {
    return ValueListenableBuilder<Selection?>(
      key: ValueKey(('inline', _state)),
      valueListenable: _state.selectionNotifier,
      builder: (context, selection, _) {
        Widget button(IconData icon, String tooltip, String key) {
          return _ToolButton(
            icon: icon,
            tooltip: tooltip,
            active: isInlineActive(_state, selection, key),
            onPressed: editing ? () => toggleInline(_state, key) : null,
          );
        }

        return Row(
          children: [
            button(Icons.format_bold, 'Bold  ⌘B', AppFlowyRichTextKeys.bold),
            button(
                Icons.format_italic, 'Italic  ⌘I', AppFlowyRichTextKeys.italic),
            button(
              Icons.format_underlined,
              'Underline  ⌘U',
              AppFlowyRichTextKeys.underline,
            ),
            button(
              Icons.format_strikethrough,
              'Strikethrough',
              AppFlowyRichTextKeys.strikethrough,
            ),
            button(Icons.code, 'Inline code  ⌘E', AppFlowyRichTextKeys.code),
          ],
        );
      },
    );
  }

  // ---- Lists --------------------------------------------------------------

  Widget _buildBlockButtons() {
    return ValueListenableBuilder<Selection?>(
      key: ValueKey(('block', _state)),
      valueListenable: _state.selectionNotifier,
      builder: (context, selection, _) {
        return Row(
          children: [
            _ToolButton(
              icon: Icons.format_list_bulleted_rounded,
              tooltip: 'Bulleted list',
              active: isBlockActive(
                _state,
                selection,
                BulletedListBlockKeys.type,
              ),
              onPressed: editing ? () => toBulletedList(_state) : null,
            ),
            _ToolButton(
              icon: Icons.format_list_numbered_rounded,
              tooltip: 'Numbered list',
              active: isBlockActive(
                _state,
                selection,
                NumberedListBlockKeys.type,
              ),
              onPressed: editing ? () => toNumberedList(_state) : null,
            ),
            _ToolButton(
              icon: Icons.checklist_rounded,
              tooltip: 'Checklist',
              active: isBlockActive(_state, selection, TodoListBlockKeys.type),
              onPressed: editing ? () => toChecklist(_state) : null,
            ),
            _ToolButton(
              icon: Icons.format_quote_rounded,
              tooltip: 'Quote',
              active: isBlockActive(_state, selection, QuoteBlockKeys.type),
              onPressed: editing ? () => toQuote(_state) : null,
            ),
          ],
        );
      },
    );
  }

  // ---- Insert -------------------------------------------------------------

  Widget _buildInsertButtons() {
    return Row(
      children: [
        _ToolButton(
          icon: Icons.table_chart_outlined,
          tooltip: 'Insert table',
          onPressed: editing ? () => insertTable(_state) : null,
        ),
        _ToolButton(
          icon: Icons.image_outlined,
          tooltip: 'Insert image',
          onPressed: editing ? onPickImage : null,
        ),
        PopupMenuButton<String>(
          tooltip: 'Insert',
          requestFocus: false,
          enabled: editing,
          onSelected: (value) {
            switch (value) {
              case 'pasteMarkdown':
                pasteAsMarkdownCommand.handler(_state);
              case 'pastePlain':
                (enableRichPaste
                        ? chaiPastePlainTextCommand
                        : pasteTextWithoutFormattingCommand)
                    .handler(_state);
              case 'code':
                insertCodeBlock(_state);
              case 'table':
                insertTable(_state);
              case 'image':
                onPickImage();
              case 'divider':
                insertDivider(_state);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'pasteMarkdown',
                height: 34,
                child: Text('Paste as Markdown    ⌘⌥⇧V')),
            PopupMenuItem(
                value: 'pastePlain',
                height: 34,
                child: Text('Paste as plain text    ⌘⇧V')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'code', height: 34, child: Text('Code block')),
            PopupMenuItem(value: 'table', height: 34, child: Text('Table')),
            PopupMenuItem(value: 'image', height: 34, child: Text('Image…')),
            PopupMenuItem(value: 'divider', height: 34, child: Text('Divider')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: editing ? AppColors.text : AppColors.textMuted,
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Editing / Viewing --------------------------------------------------

  Widget _buildModeMenu() {
    return PopupMenuButton<bool>(
      tooltip: 'Mode',
      onSelected: onEditingChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: true, height: 34, child: Text('Editing')),
        PopupMenuItem(value: false, height: 34, child: Text('Viewing')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              editing ? Icons.edit_outlined : Icons.visibility_outlined,
              size: 18,
              color: AppColors.text,
            ),
            const SizedBox(width: 6),
            Text(
              editing ? 'Editing' : 'Viewing',
              style: const TextStyle(fontSize: 14, color: AppColors.text),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF26262A) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 19,
            color: !enabled
                ? AppColors.textMuted.withValues(alpha: 0.5)
                : active
                    ? AppColors.accent
                    : AppColors.text,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.border,
    );
  }
}
