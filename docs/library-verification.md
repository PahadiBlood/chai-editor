# Library verification

Automated tests use temporary directories, never the user's real library.

- `library_service_test.dart`: first launch, nested folders, sort/count rules,
  note/folder rename, sanitized names and clashes, move/duplicate, cycle refusal,
  trash/restore, permanent delete, 30-day purge, hidden entries/symlink rejection,
  atomic writes, and persisted state.
- `library_model_test.dart`: edit followed immediately by flush and restart,
  restored document/state, and save paths after parent rename/move.
- `library_ui_test.dart`: the real app layout with a temporary library at 320,
  390, 600, 800 and 1100 px, plus a request through Flutter's application-exit
  callback that verifies disk content before accepting exit.

The automated exit test exercises the awaited lifecycle callback. A physical
Cmd+Q/relaunch test and visual inspection on Windows, Android and iOS are not
covered by those tests.

Manual macOS acceptance check:

1. Run `./setup.sh` and `flutter run -d macos`.
2. Create a folder, sub-folder and note. Type into the note, then press Cmd+Q
   immediately, before the autosave debounce expires.
3. Relaunch. Check text, open note, selected row, expansion and sidebar dimensions.
4. Rename the parent folder while its note is open, edit again, quit and reopen.
5. Try all rename triggers, Esc cancellation, blank names and duplicate names.
6. Drag a folder onto its own child (must be refused), move a note, trash it and
   restore it. Permanent deletion and Empty must request confirmation.
7. Open an external file, save and export it, and import a copy into the library.
8. Resize the window to a narrow width; open the sidebar drawer and format text.
