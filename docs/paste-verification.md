# Clipboard paste verification

Restart the app after rebuilding: the native `chai/clipboard` channel requires a
full restart, not hot reload. `./setup.sh` installs the channel implementation
from `macos_overrides/MainFlutterWindow.swift` and the custom app icon.

## Behavior and implementation

- Cmd+V tries native HTML, then block-level Markdown, then the existing editor
  plain-text implementation. Single rich paragraphs paste inline. Structured
  blocks follow the cursor block; an empty paragraph is replaced.
- Cmd+Option+Shift+V (or **+ → Paste as Markdown**) always parses Markdown.
- Cmd+Shift+V (or **+ → Paste as plain text**) skips rich parsing.
- Every mode pastes raw text inside a code block. Selection deletion and paste
  are combined into one transaction with a separate undo item. A final table or
  image gets a trailing paragraph for the cursor.
- Browser metadata, scripts, styles, and fragment wrapper comments are excluded.
- `package:html` converts DOM directly to editor nodes. This preserves pre/code
  whitespace and language, nested inline deltas and table cells without an
  HTML-to-Markdown round trip or another dependency. The upstream HTML importer
  and standard paste commands remain intact. No editor version upgrade.
- To restore the original shortcut behavior temporarily, use
  `flutter run -d macos --dart-define=CHAI_RICH_PASTE=false`.

## Automated coverage

`flutter test` covers Markdown detection, HTML structures, nested inline styles,
Apple-style spans, fragment wrappers, native-channel fallback, selection
replacement, cursor placement, plain text, raw code blocks, one-step undo/redo,
and the raw `samples/kafka-minimum-setup.md` document. These are synthetic HTML
fixtures, not clipboard captures from the named applications.

## Manual source matrix

The following live application checks require interactive access to those
applications and documents. They have not been performed by the automated tests.

| Copy source | What to copy | Expected |
|---|---|---|
| Chrome | A rendered article containing headings, bold, lists, pre/code and a table | Rich blocks and cell formatting survive |
| Safari | The same rendered article | Same result as Chrome |
| Claude document editor | A document containing headings, a list, fenced code and a table | Semantic HTML survives; raw Markdown uses the fallback |
| Apple Notes | A heading, styled text, bullets, numbered items and a checklist | Text styles and available semantic list/check states survive |
| Raw Kafka sample | Select all raw text of `samples/kafka-minimum-setup.md` | Headings, lists, language-labelled code and table survive |

For each source, paste into a new note, over a selection and into a code block.
Check that one Cmd+Z restores the original content and selection. Separately
copy a single unformatted sentence and paste in the middle of a paragraph:
it must stay inline. Try both explicit paste modes from the + menu and via
keyboard. HTML can preserve only semantics actually provided by its source;
for example, an image-only representation of a checklist is not editable text.
