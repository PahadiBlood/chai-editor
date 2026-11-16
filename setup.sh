#!/usr/bin/env bash
# One-time setup: adds the macOS runner, installs the file-access permissions
# and downloads packages. Run it from this folder:  ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed or not on your PATH."
  echo "Install it from https://docs.flutter.dev/get-started/install/macos"
  exit 1
fi

flutter config --enable-macos-desktop >/dev/null 2>&1 || true

if [ ! -d macos ]; then
  echo "Creating the macOS runner..."
  flutter create --platforms=macos --project-name chai_editor --org in.chaisociety .
fi

# flutter create adds a counter-app test that does not match this app.
rm -f test/widget_test.dart

echo "Installing permissions (open and save files, load images)..."
cp macos_overrides/DebugProfile.entitlements macos/Runner/DebugProfile.entitlements
cp macos_overrides/Release.entitlements macos/Runner/Release.entitlements
cp macos_overrides/MainFlutterWindow.swift macos/Runner/MainFlutterWindow.swift
cp macos_overrides/AppDelegate.swift macos/Runner/AppDelegate.swift

# Keep the original Flutter icon available: CHAI_USE_CUSTOM_ICON=0 ./setup.sh
cp -R assets/branding/ChaiIcon.appiconset macos/Runner/Assets.xcassets/
icon_name=ChaiIcon
if [ "${CHAI_USE_CUSTOM_ICON:-1}" = "0" ]; then
  icon_name=AppIcon
fi
sed -i '' -E "s/ASSETCATALOG_COMPILER_APPICON_NAME = (AppIcon|ChaiIcon);/ASSETCATALOG_COMPILER_APPICON_NAME = $icon_name;/g" macos/Runner.xcodeproj/project.pbxproj

flutter pub get

echo
echo "Done. Start the app with:"
echo "  flutter run -d macos"
