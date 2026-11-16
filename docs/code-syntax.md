# Code syntax colours

## Dependency choice

Evaluated [re_highlight 0.0.3](https://pub.dev/packages/re_highlight) first, then
[highlight 0.7.0](https://pub.dev/packages/highlight/versions). `re_highlight` is
Reqable's MIT-licensed Dart port of highlight.js 11.9.0; it exposes nested token
scopes and subset auto-detection. Its published SDK constraints are Dart
`>=2.17.0 <4.0.0`, Flutter `>=1.17.0`, compatible with this project. Its latest
pub.dev release is two years old; `highlight` last published five years ago.
Neither is described here as having frequent recent releases. The former was
selected for its newer grammar generation, scopes and existing downstream use.
Only the common grammars are registered/imported. The appflowy_editor pin stays
at 6.1.0. No vendored editor changes are required for this feature.

## Implementation

- `lib/code_syntax.dart` tokenizes once for the editor, clipboard HTML, PDF and
  DOCX. It normalizes aliases and uses a bounded 64-entry LRU keyed by the exact
  text and normalized language. Over 20,000 UTF-16 code units skips tokenization.
- Token text must concatenate to the exact original string. Otherwise the whole
  block falls back to grey. The textSpanDecorator reconstructs only the complete
  block span, avoiding duplicate text when appflowy decorates individual leaves.
- Initial highlighting is immediate; typing uses a 150 ms debounce. Pending
  text renders in grey at its current offsets until its own tokens are ready.
  Highlighting has no document transaction, saved attributes or undo entry.
- Auto-detection is restricted to the language menu's common grammars (HTML uses
  the XML grammar). The label needs relevance >=5 and a lead of at least 2 and
  15% over the second result. Ambiguous snippets keep the label `auto`.
- `CodeSyntaxColors` in `lib/theme.dart` owns both palettes. Inline code remains
  grey. PDF uses coloured spans; Word uses per-run `w:color` and italic comments.
  Code is tokenized before splitting into lines, keeping multiline token context.
  Very long PDF lines wrap into bounded chunks without adding or deleting text.
- HTML paste recognizes pre, block code, pre/pre-wrap styles, common monospace
  families and GitHub/highlight.js line tables. It discards known gutter nodes,
  source colours and executable/browser metadata. External preformatted text keeps
  its trailing newlines; `CHAI_TRIM_EXTERNAL_PRE_NEWLINE=true` retains the former
  one-layout-newline trimming behaviour for older clipboard producers. Indentation,
  tabs and NBSP spaces are kept. Ordinary inline code in a paragraph stays inline.
- Native `setClipboard` writes both NSPasteboard string and HTML flavours as one
  pasteboard item. Missing/older runners fall back to plain Markdown. Cut checks
  the document and selection after the async write and only then deletes.
- The original copy/cut shortcuts remain available with
  `--dart-define=CHAI_RICH_COPY=false`; this also restores the old raw-text code
  copy button. Existing `CHAI_RICH_PASTE=false` retains upstream paste behaviour.

## Verification

Run `flutter analyze`, `flutter test`, and `flutter build macos --release`.
Automated tests cover text/offset preservation across all common grammars,
aliases, confidence labels, limits, caches, fence reopening, HTML code fixtures,
selection replacement, one-step undo, native-channel payloads/fallbacks, cut
races/failure, widget rendering/debounce and both export formats.

The HTML fixtures simulate source formats; they are not captures from live apps.
These manual checks still require the named applications:

1. Restart the rebuilt app so the Swift channel is loaded. Open a fresh note.
2. Copy coloured code from VS Code, Xcode, IntelliJ, GitHub in Chrome/Safari, and
   Claude documents. Confirm one code block, indentation, language and Chai's
   colours; check that line numbers do not become code.
3. Paste raw multiline terminal text using **⌘⌥V**. Paste over a selection and
   inside an existing code block; check one undo restores the original.
4. Select part/all of a code block and copy or cut with **⌘C/⌘X**. Also try the
   block Copy button. Paste into Word, Pages, Google Docs and Notion and check
   colours when those destinations accept HTML. Plain-text apps receive fences.
5. Paste that clipboard back into Chai and confirm the code, language, tabs and
   trailing lines survive. Try ordinary formatted prose and tables too.
6. Export a note with multiline comments and long code lines to PDF and Word.
   Inspect wrapping, light token colours, grey boxes and italic comments.
