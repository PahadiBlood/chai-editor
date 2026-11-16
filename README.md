<p align="center">
  <img src="assets/branding/chai-logo.png" width="128" alt="Chai Editor logo">
</p>

# Chai Editor

**A clean UI editor for Markdown documents on macOS.**

Chai Editor primarily focuses on a clean, distraction-free editing experience:
a dark workspace, readable typography, a compact formatting toolbar, and documents
in a persistent folder-and-note sidebar. Open a Markdown file, edit it visually,
and save it back as Markdown.

This repository contains the source code. Follow the steps below to download,
build, and launch the app on your Mac; a prebuilt installer is not included.

## 1. Install Flutter and the macOS build tools

You need macOS 12 or newer, Git, Flutter, full Xcode, and CocoaPods. The project
requires Flutter 3.32 or newer; the app has been checked with Flutter 3.47.8.
Android Studio and Android/iOS SDK setup are not needed for this macOS-only app.

If Git is missing, install Apple's command-line tools first and wait for the
installation to finish:

```bash
xcode-select --install
```

Download the tested Flutter 3.47.8 SDK into your home directory. Skip the clone if you
already have Flutter installed:

```bash
mkdir -p "$HOME/develop"
git clone https://github.com/flutter/flutter.git --branch 3.47.8 --depth 1 "$HOME/develop/flutter"
export PATH="$HOME/develop/flutter/bin:$PATH"
flutter --version
```

To keep Flutter available in new Terminal windows using macOS's default zsh:

```bash
echo 'export PATH="$HOME/develop/flutter/bin:$PATH"' >> "$HOME/.zprofile"
source "$HOME/.zprofile"
```

Install **Xcode** from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835),
open it once, and finish its requested component installation. Then configure
its command-line tools:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license
```

Install CocoaPods. If you use [Homebrew](https://brew.sh/):

```bash
brew install cocoapods
```

Otherwise, use the [CocoaPods installation guide](https://guides.cocoapods.org/using/getting-started.html#installation).
Validate the macOS toolchain:

```bash
flutter config --enable-macos-desktop
flutter doctor -v
flutter devices
```

Resolve any issues in the **Flutter** and **Xcode** sections. `flutter devices`
should list **macOS**. Warnings about Android tooling do not prevent this app
from building for macOS.

Official references: [Flutter installation](https://docs.flutter.dev/install/manual)
and [macOS development setup](https://docs.flutter.dev/platform-integration/macos/setup).

## 2. Download Chai Editor

```bash
git clone https://github.com/PahadiBlood/chai-editor.git
cd chai-editor
./setup.sh
```

The setup script downloads Dart dependencies, installs the native HTML clipboard
bridge and file-access permissions, and selects the Chai logo. It can be rerun
after updates. Keep `third_party/appflowy_editor` in the checkout: this is the
pinned **6.1.0** editor with the project's documented compatibility patches.

## 3. Launch during development

From the downloaded `chai-editor` folder:

```bash
flutter run -d macos
```

The window and application name are **Chai Editor**. The internal Dart package
name remains `chai_editor`.

Press **⌘O** to open a `.md`, `.markdown`, or `.txt` file. Try
[`samples/kafka-minimum-setup.md`](samples/kafka-minimum-setup.md).
Edit visually, then press **⌘S** to save or **⇧⌘S** to save as a new file.

## 4. Build a standalone app

Build the release app to run it without a development terminal:

```bash
flutter build macos --release
open "build/macos/Build/Products/Release/Chai Editor.app"
```

The output is **Chai Editor.app**, with the custom document-and-chai logo.
For Flutter's native build details, see
[Building macOS apps](https://docs.flutter.dev/platform-integration/macos/building).

To keep your locally built app in your user's Applications folder, first save
and quit any running copy, then run:

```bash
mkdir -p "$HOME/Applications"
ditto "build/macos/Build/Products/Release/Chai Editor.app" "$HOME/Applications/Chai Editor.app"
open "$HOME/Applications/Chai Editor.app"
```

You can then launch **Chai Editor** from Finder, Spotlight, or the Dock.
These commands build and install on your own Mac; they do not create a notarized
installer for distribution to other users.

## Editing features

- Clean dark interface with a folder-and-note tree, serif headings, and a compact toolbar.
- Bold, italic, underline, strikethrough, links, and grey inline code.
- Headings, lists, checklists, quotes, language-labelled code blocks, tables, images, and dividers.
- Rich HTML paste, automatic block Markdown detection, and explicit paste modes.
- Syntax-coloured code, coloured HTML copy/cut, and light-palette PDF/Word export.
- Editing and read-only viewing modes, undo/redo, and unsaved-change indicators.

| Shortcut | Action |
|---|---|
| ⌘N | New library note |
| ⌘O | Open a file |
| ⌘S / ⇧⌘S | Save / Save as |
| ⌘B / ⌘I / ⌘U | Bold / Italic / Underline |
| ⌘K | Add a link |
| ⌘V | Paste HTML, Markdown, or plain text |
| ⌘⇧V | Paste as plain text |
| ⌘⌥⇧V | Paste as Markdown |
| ⌘⌥V | Paste as Code Block |
| ⌘C / ⌘X | Copy / Cut with Markdown and rich HTML |
| ⌘Z / ⇧⌘Z | Undo / Redo |
| / | Open the block menu |

All three explicit paste modes are also available in the toolbar's **+** menu.
Pasting inside a code block always inserts raw text.

## Syntax colours and copying code

Choose a code block's language from its label, or leave it on **auto**. Common
languages are detected automatically; a muted **auto: python** label appears only
when detection is confident. Detection never changes the saved Markdown fence.
Aliases such as `js`, `ts`, `sh`, `zsh`, and `yml` are normalized.

Code uses GitHub Dark-style colours while the rest of the interface stays
black, white, and grey. Highlighting waits 150 ms after typing; blocks over
20,000 characters stay plain grey. Inline code remains grey.

**⌘V** recognizes HTML code copied as pre/code blocks or styled monospace/pre-wrap
containers, keeping indentation and removing line-number gutters. For raw terminal
text, use **⌘⌥V → Paste as Code Block**. Every paste mode inserts raw text when the
cursor is already inside a code block.

**⌘C**, **⌘X**, and the code block's copy button put fenced Markdown and HTML with
inline token colours on the clipboard. A receiving app chooses which flavour to
use; plain text destinations show Markdown fences. PDF and Word exports use the
same tokenization with a light printing palette and grey code boxes.

See [syntax-colour implementation and verification](docs/code-syntax.md) for
coverage, dependency evaluation, and live-application checks.

## Update and check the project

From your checkout, with local changes committed or saved:

```bash
git pull --ff-only
./setup.sh
flutter analyze
flutter test
flutter build macos --release
```

Quit the old app and reopen the new build. If you installed a copy in
`~/Applications`, repeat the `ditto` command above after quitting that copy.

## Troubleshooting and details

- **Flutter is not found:** open a new Terminal window or run
  `source "$HOME/.zprofile"` after configuring PATH.
- **No macOS desktop project configured:** run `./setup.sh` from the repository root.
- **Clipboard changes or the new logo do not appear:** fully quit and relaunch
  the newly built app. Hot reload does not reload Swift code or native assets.
- **`getcwd: Operation not permitted`:** leave and re-enter the checkout using
  `cd ..` and `cd chai-editor`, then retry.
- **Markdown output:** saving normalizes Markdown formatting. Local image paths
  refer to files on your Mac. Code colours are regenerated from the fence language
  when opening a note; source clipboard colours are not saved.

More information:
[editor guide](docs/editor-guide.md),
[clipboard behavior and manual verification](docs/paste-verification.md),
[logo source](assets/branding/README.md), and
[editor compatibility patches and upstream attribution](third_party/appflowy_editor/PATCHES.md).
The upstream editor's [licence notices](third_party/appflowy_editor/LICENSE)
are included with its source.

## Other platforms: run and build

macOS is the verified platform. Flutter also supports Windows, Android and iOS;
the commands below generate the additional native runners. These targets are
not yet verified here. The native HTML clipboard bridge is macOS-specific;
other targets fall back to plain-text/Markdown clipboard input.

Keep the existing macOS runner; use only the requested platform in `flutter create`.
Do not run the macOS-only `setup.sh` on Windows.

### Windows (build on Windows)

Install Flutter and Visual Studio with **Desktop development with C++**, then
run these commands in PowerShell from the checkout:

```powershell
flutter config --enable-windows-desktop
flutter create --platforms=windows --project-name chai_editor --org in.chaisociety .
flutter pub get
flutter run -d windows
flutter build windows --release
```

The executable and its accompanying DLL/data files are under
`build/windows/x64/runner/Release/`. Keep the entire folder together.
See [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).

### Android

Install the Android SDK and an emulator (or connect a phone with USB debugging).
Run `flutter doctor --android-licenses` and resolve Android toolchain issues.

```bash
flutter create --platforms=android --project-name chai_editor --org in.chaisociety .
flutter pub get
flutter devices
flutter run -d <android-device-id>
flutter build apk --release
flutter build appbundle --release
```

The APK is `build/app/outputs/flutter-apk/app-release.apk`; the bundle is
`build/app/outputs/bundle/release/app-release.aab`. Configure your own release
signing before distributing through Google Play. See
[Flutter Android builds](https://docs.flutter.dev/deployment/android).

### iOS (build on a Mac)

Install Xcode and CocoaPods, then use a simulator or a provisioned iPhone:

```bash
flutter create --platforms=ios --project-name chai_editor --org in.chaisociety .
flutter pub get
flutter devices
flutter run -d <ios-device-id>
flutter build ios --release --no-codesign
```

The unsigned build is under `build/ios/iphoneos/`. To install on a real iPhone or
publish, open `ios/Runner.xcworkspace`, configure a signing team and bundle ID,
then use `flutter build ipa --release` with your provisioning set up. See
[Flutter iOS builds](https://docs.flutter.dev/deployment/ios).

## Free use and commercial reuse

Original Chai Editor code and artwork are released under the [Unlicense](LICENSE).
Everyone may use, copy, modify, redistribute, or sell them, including commercially,
without paying the author or asking permission. No warranty is provided.
This dedication does not remove the existing terms of dependencies; see
[third-party notices](THIRD_PARTY_NOTICES.md).

## Your note library

The sidebar stores real folders and `.md` notes under the platform's application
Documents directory in `ChaiEditor/` (inside the application container on a
sandboxed Mac). The first launch creates **Notes → Welcome**.

- Notes save automatically 700 ms after editing, on note switches, and before an
  accepted app exit. There is no Save prompt or unsaved dot for library notes.
- Create notes and folders using the toolbar, sidebar buttons or context menus.
  Rename with a slow second click, double-click, Return, or the context menu.
- Drag items into folders; drop on **On My Mac** to move them to the root.
- **Recently Deleted** keeps deleted notes/folders for 30 days. Restore them, or
  permanently delete after confirmation. **Empty** also asks for confirmation.
- Resize the sidebar between 200–380 px. At widths below 760 px it becomes a
  drawer, opened with the sidebar button. The formatting toolbar scrolls on
  narrow screens and editor margins shrink.
- **⌘⇧N** creates a folder; **⌘⌥S** toggles the sidebar. With sidebar focus,
  arrows navigate/expand/collapse and **⌘Backspace** moves an item to trash.
  Use Ctrl instead of Cmd for file/library keyboard shortcuts on Windows.
- Open and Save As continue to work for external files. **+ → Import Markdown**
  copies a file into the selected library folder. Save As on a library note
  exports a copy without changing its library location.

The app remembers the open note, selected row, expanded folders, sidebar width
and visibility in `.chai/state.json`. Hidden files are excluded from the tree.
It reloads the tree when activated so external file-manager changes appear.

The former tab dropdown remains available using
`--dart-define=CHAI_SHOW_TABS=true`; it is hidden by default. The pinned editor
remains at 6.1.0. See [library verification](docs/library-verification.md).

## PDF and Word export

Use the **Export** button next to Open/Save, or right-click a note and choose
**Export → PDF / Word / Markdown**. PDF uses a white A4 page, embedded Noto fonts,
wrapped code and bordered tables. Word exports real styles, lists and tables;
images currently appear by file name. The save dialog uses the note name, and
an **Exported → Show in Finder** action opens the output folder.

The sidebar and Material theme now use greys and white. Header and folder-row
**+** menus create notes/folders; the toolbar New Note icon is hidden by default
(`--dart-define=CHAI_SHOW_TOOLBAR_NEW_NOTE=true` restores it).

See [phase verification and profile measurements](docs/phase-verification.md)
and [export format details](docs/export-design.md) for test coverage and limits.

## Storage setup and portability

Chai Editor asks the operating system for the current user's Documents folder;
it does not use the developer's username or home directory. On a sandboxed Mac,
macOS places this inside that user's application container. This is normal.
You do not need to create `.chai` or `.trash` yourself.

Startup creates and checks storage before enabling the editor. Writes recreate
missing parent folders, retry a disappeared-parent race once, and replace files
atomically. Sidebar state and trash records now store relative paths, so new
libraries can be copied to another location without retaining someone else's
home-directory paths. Older state from the same library is accepted.

If the default library cannot be opened or written, the app offers **Retry** or
**Use app storage**. The latter creates a separate library in the OS-provided
application-support directory and remembers the choice. It never moves or
deletes existing notes. No automatic fallback to temporary storage is used.
Internal errors are logged for diagnosis; the UI uses plain explanations rather
than raw exceptions or private filesystem paths.

After pulling an update, save and fully quit the old app, rebuild, and reopen
`build/macos/Build/Products/Release/Chai Editor.app`. If you keep a copy in
`~/Applications`, replace that copy using the installation commands above;
building a new app does not update an older installed or running copy.
