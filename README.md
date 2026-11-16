<p align="center">
  <img src="assets/branding/chai-logo.png" width="128" alt="Chai Editor logo">
</p>

# Chai Editor

Chai Editor is a free, clean Markdown document editor. It is primarily focused
on a simple, distraction-free writing experience: a dark editor, a compact
formatting toolbar, and a sidebar for notes and folders. The app name is **Chai
Editor**; `chai_editor` is only the internal Flutter package name.

It opens Markdown files, lets you edit them visually, and saves Markdown back
to disk. It supports headings, lists, tables, quotes, code blocks, images,
links, rich paste, Markdown paste, undo/redo, and PDF or Word export.

## Before you start

You need basic Flutter knowledge: how to use Terminal, install Flutter, run
`flutter doctor`, and resolve the toolchain issues it reports. Read the
[Flutter installation guide](https://docs.flutter.dev/install) before building.

The repository is verified on macOS. Windows, Android, and iOS runners can be
generated and built too; use a device or emulator to check their smaller-screen
layout before shipping. macOS has the richest clipboard support.

## Download and run on macOS

Install Git, Flutter, full Xcode, and CocoaPods. Then enable the macOS desktop
toolchain and confirm it is ready:

```bash
flutter config --enable-macos-desktop
flutter doctor -v
```

Download the project and install its dependencies:

```bash
git clone https://github.com/PahadiBlood/chai-editor.git
cd chai-editor
./setup.sh
flutter pub get
```

Launch the editor for development:

```bash
flutter run -d macos
```

If you see `No macOS desktop project configured`, make sure you are inside the
downloaded project folder and run `./setup.sh` again. If Terminal reports
`getcwd: Operation not permitted`, leave and re-enter the project folder:

```bash
cd ..
cd chai-editor
```

## Build the macOS app

```bash
flutter build macos --release
open "build/macos/Build/Products/Release/Chai Editor.app"
```

The release application is at `build/macos/Build/Products/Release/Chai
Editor.app`. Quit an older copy before opening a new build.

## Use the editor

- Press **⌘O** to open a Markdown, text, or `.markdown` file. Every opened file
  stays open as its own document; opening another file does not replace it.
- Press **⌘S** to save. New documents ask where to save; later saves use that
  location. Press **⇧⌘S** to choose a different location.
- Press **⌘Z** and **⇧⌘Z** for undo and redo.
- Paste rich content with **⌘V**, plain text with **⌘⇧V**, or force Markdown
  parsing with **⌘⌥⇧V**. Pasting inside a code block always inserts raw text.
- Use the sidebar **×** button to remove a note or folder from Chai Editor
  without deleting its files. Unsaved work asks whether to Save, Discard, or
  Cancel. Right-click a sidebar item and choose **Open in Finder** (or **Open
  in File Explorer** on Windows) to view its real location.

Library notes are stored in the current user's Documents area. Chai Editor does
not depend on the developer's path or username. If the Documents folder is not
available, the app offers a safe app-storage location instead.

## Run and build other platforms

These commands generate only the requested platform runner; they keep the
existing macOS runner. Run them from the project root after installing the
Flutter toolchain for that platform.

### Windows

On Windows, install Flutter and Visual Studio with **Desktop development with
C++**, then run in PowerShell:

```powershell
flutter config --enable-windows-desktop
flutter create --platforms=windows --project-name chai_editor --org in.chaisociety .
flutter pub get
flutter run -d windows
flutter build windows --release
```

Keep all files in `build/windows/x64/runner/Release/` together when moving the
release build.

### Android

Install the Android SDK and use an emulator or connected device:

```bash
flutter create --platforms=android --project-name chai_editor --org in.chaisociety .
flutter pub get
flutter run -d <android-device-id>
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

### iOS

On a Mac with Xcode and CocoaPods installed:

```bash
flutter create --platforms=ios --project-name chai_editor --org in.chaisociety .
flutter pub get
flutter run -d <ios-device-id>
flutter build ios --release --no-codesign
```

To install on an iPhone or publish, configure your signing team and bundle ID
in Xcode first.

## Check your changes

```bash
flutter analyze
flutter test
flutter build macos --release
```

More technical details are in [docs](docs), including the editor guide,
clipboard verification, storage notes, and compatibility patches.

## Free to use

Chai Editor's original code and artwork are released under the
[Unlicense](LICENSE). Anyone may use, copy, change, share, or sell them without
paying or asking permission. Third-party packages keep their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
