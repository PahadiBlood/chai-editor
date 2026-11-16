# Seven-phase verification

1. All note and metadata writes use a helper that creates the parent first.
   Internal state/trash failures retry once and log. Note-save banners clear in
   five seconds; missing-parent startup is regression-tested.
2. UI colours are centralized greys. Code-block, Markdown and paste source files
   are unchanged; existing editor colour pickers remain.
3. Header/folder plus menus share creation. Legacy tabs and toolbar New Note
   remain behind CHAI_SHOW_TABS and CHAI_SHOW_TOOLBAR_NEW_NOTE, both false.
4. openNote follows the active library document; rename updates the breadcrumb,
   save status has its own notifier, and active-note deletion shows empty state.
5. Secondary-pointer handlers wrap draggable rows. Tests secondary-click notes,
   folders, empty space, trash items and Recently Deleted. Ctrl-click uses the
   same pointer route. Move targets disable self and descendants.
6. Eight-entry LRU retains editor, cursor and scroll state. Dirty/writing notes
   stay resident; writes queue per file. Switching does not re-list folders or
   await saves. Selectors isolate rows; save status does not notify the tree.
   One 220 ms controller reveals a full-width clipped sidebar and changes the
   horizontal toolbar inset. Document-only AnimatedSwitcher cross-fades a texture-backed snapshot of
   the outgoing page and the live incoming editor, avoiding duplicate GlobalKeys
   during rapid returns to cached notes. An unpainted page uses a short incoming
   fade as a fallback. The document width is held fixed during
   sidebar visibility changes and centred in the available editor pane.
7. Toolbar/note menus export PDF, DOCX and Markdown with Show in Finder. DOCX
   images use filename placeholders. See export-design.md for visual checks.

Native profile command:

```bash
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/switching_test.dart -d macos
```

The isolated test switched five cached notes 20 times, verified all 100 inserted
edits on disk, and toggled the sidebar ten times. output/profile/timings.json:

- Cached switch including a pumped frame: median 16.415 ms, p95 16.924 ms,
  maximum 50.483 ms.
- Switching build: mean 1.577 ms, worst 2.272 ms, 94 frames, zero missed budgets.
- Sidebar build: mean 1.709 ms, worst 5.947 ms, 39 frames, zero missed budgets.

These are automated native profile FrameTiming readings, not manual DevTools
GUI inspection. The runner could not foreground the app; near-zero raster times
make GPU/visible-smoothness conclusions invalid. A cold 96.8 KB note took 53.758 ms including parsing on a worker isolate and
a pumped frame. A physical Cmd+Q/relaunch remains unverified. Automated exit-save/restart tests pass.
