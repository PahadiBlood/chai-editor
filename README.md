# Chai Editor (macOS)

A document editor in Flutter for macOS. It opens, edits and saves Markdown
files, in a dark layout with a toolbar across the top.

## Run it

You need Flutter 3.32 or newer and Xcode (for the macOS build).

```bash
cd chai_editor
./setup.sh
flutter run -d macos
```

`setup.sh` prepares the native runner and can be rerun after updates:

1. Creates the `macos/` runner with `flutter create --platforms=macos`.
2. Copies in the two `.entitlements` files from `macos_overrides/`. Without
   them macOS blocks opening and saving files.
3. Installs the native HTML clipboard bridge and Chai app icon, retaining the
   original Flutter icon (`CHAI_USE_CUSTOM_ICON=0 ./setup.sh` selects it).
4. Runs `flutter pub get`.

If you prefer to do it by hand:

```bash
flutter create --platforms=macos --project-name chai_editor --org in.chaisociety .
rm -f test/widget_test.dart
cp macos_overrides/*.entitlements macos/Runner/
cp macos_overrides/MainFlutterWindow.swift macos/Runner/
flutter pub get
flutter run -d macos
```

To try it, press `⌘O` and open `samples/kafka-minimum-setup.md`.

After updating the clipboard bridge, fully restart the app; hot reload does not
reload Swift code. Clipboard behavior and the live-source verification checklist
are documented in [docs/paste-verification.md](docs/paste-verification.md).
The logo source and PNG are in [assets/branding](assets/branding/README.md).

## What it does

| Area | Features |
|---|---|
| Documents | Open `.md`, `.markdown`, `.txt`. Save, Save as. Several documents in tabs. A dot marks unsaved changes. |
| Text | Bold, italic, underline, strikethrough, inline code, links (`⌘K`), text and highlight colour. |
| Blocks | Paragraph, Heading 1 to 3, bulleted list, numbered list, checklist, quote, code block, table, image, divider. |
| Code blocks | Monospaced, language label, copy button. Enter adds a line, Enter on an empty last line leaves the block. |
| Menus | Toolbar buttons, a bubble toolbar on selected text, and a `/` menu in the document. |
| Mode | Editing or Viewing (read only), from the menu at the top right. |
| Paste | Cmd+V preserves HTML formatting and detects block Markdown. Explicit Markdown and plain-text paste are in the **+** menu. All modes paste raw text in code blocks. |

## Shortcuts

| Keys | Action |
|---|---|
| `⌘O` | Open |
| `⌘S` | Save |
| `⇧⌘S` | Save as |
| `⌘N` | New tab |
| `⌘B` `⌘I` `⌘U` | Bold, italic, underline |
| `⌘K` | Add a link |
| `⌘V` | Paste HTML, Markdown, or plain text |
| `⌘⇧V` | Paste as plain text |
| `⌘⌥⇧V` | Paste as Markdown |
| `/` | Open the block menu |
| `⌘Z` `⇧⌘Z` | Undo, redo |

## Files

```
lib/main.dart          App, dark theme, localisation
lib/editor_page.dart   Tabs, open and save, the editor itself
lib/toolbar.dart       The top toolbar
lib/actions.dart       Bold, headings, lists, tables, images ...
lib/code_block.dart    Code block (the editor package has none)
lib/markdown_io.dart   Markdown in and out
lib/doc_tab.dart       One open document
lib/theme.dart         Colours, fonts, heading sizes
macos_overrides/       Permissions for opening and saving files
samples/               A document to open
test/                  Markdown round-trip tests: flutter test
```

## Good to know

- **Built on `appflowy_editor` 6.1.0**, kept in `third_party/appflowy_editor`
  with a Flutter text-input compatibility fix documented in
  `third_party/appflowy_editor/PATCHES.md`. It is dual licensed (AGPL-3.0 and MPL-2.0).
  You may use it under MPL-2.0, which allows closed-source apps, but you must
  keep its licence notices and share changes to its own files.
- **Images** are stored in the Markdown as the full path on your Mac, so a
  document with local images works only on that machine.
- **No syntax colouring** in code blocks yet.
- **Saving rewrites the Markdown** in a tidy form: blank line between blocks,
  `-` for bullets. Round-trip tests are in `test/`.
- If CocoaPods complains about the macOS version, open `macos/Podfile` and set
  `platform :osx, '12.0'` (the generated runner's minimum).
- If `flutter run -d macos` reports no macOS desktop project, run `./setup.sh`
  to generate the runner and install its file-access permissions.
- If the shell reports `getcwd: Operation not permitted`, leave and re-enter
  the project directory (`cd ..` then `cd chai_editor`), as in the reported
  recovery, before retrying Flutter.
