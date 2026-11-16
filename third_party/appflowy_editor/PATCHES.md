# Local compatibility patch

Source: appflowy_editor 6.1.0 from https://pub.dev/packages/appflowy_editor/versions/6.1.0
Upstream: https://github.com/AppFlowy-IO/appflowy-editor

The runtime sources, assets, package metadata and licence are preserved here.
The upstream examples, tests and documentation are omitted.

`lib/src/editor/editor_component/service/ime/delta_input_service.dart` adds
`bool onFocusReceived() => false` to `DeltaTextInputService`. Flutter 3.47.8
requires this TextInputClient callback; returning false matches Flutter's
default implementation and preserves the existing focus behavior.

`lib/src/flutter/scrollable_helpers.dart` yields to the end of the frame after
each zero-duration auto-scroll jump and checks whether the scrollable is still
mounted. This prevents synchronous recursion and lets layout and cancellation
run between jumps.

`lib/src/editor/editor_component/service/shortcuts/command/paste_command.dart`
exposes `pastePlainTextContent`, a wrapper around the existing private plain-text
paste extension. Chai calls it on a detached document to preserve the upstream
plain-text behavior while combining replacement and insertion into one undoable
transaction. The standard paste commands remain available without changes.

The application uses this local package so a clean dependency install keeps the
fix without modifying the shared pub cache. Remove the local dependency when
an upstream release includes the callback and passes the app's build and tests.
