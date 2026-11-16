<p align="center">
  <img src="assets/branding/chai-logo.png" width="128" alt="Chai Editor logo">
</p>

# Chai Editor

**A clean UI editor for Markdown documents on macOS.**

Chai Editor primarily focuses on a clean, distraction-free editing experience:
a dark workspace, readable typography, a compact formatting toolbar, and documents
in tabs. Open a Markdown file, edit it visually, and save it back as Markdown.

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

- Clean dark interface with document tabs, serif headings, and a compact toolbar.
- Bold, italic, underline, strikethrough, inline code, links, and text/highlight colours.
- Headings, lists, checklists, quotes, language-labelled code blocks, tables, images, and dividers.
- Rich HTML paste, automatic block Markdown detection, and explicit paste modes.
- Editing and read-only viewing modes, undo/redo, and unsaved-change indicators.

| Shortcut | Action |
|---|---|
| ⌘N | New document tab |
| ⌘O | Open a file |
| ⌘S / ⇧⌘S | Save / Save as |
| ⌘B / ⌘I / ⌘U | Bold / Italic / Underline |
| ⌘K | Add a link |
| ⌘V | Paste HTML, Markdown, or plain text |
| ⌘⇧V | Paste as plain text |
| ⌘⌥⇧V | Paste as Markdown |
| ⌘Z / ⇧⌘Z | Undo / Redo |
| / | Open the block menu |

Both explicit paste modes are also available in the toolbar's **+** menu.
Pasting inside a code block always inserts raw text.

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
  refer to files on your Mac. Code blocks currently have no syntax colouring.

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
