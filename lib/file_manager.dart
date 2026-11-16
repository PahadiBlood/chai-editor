import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

String fileManagerLabel([TargetPlatform? platform]) =>
    switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.macOS => 'Open in Finder',
      TargetPlatform.windows => 'Open in File Explorer',
      _ => 'Open file location',
    };

/// Use native file selection on macOS and Windows. No shell interpolation: file
/// names (including spaces and punctuation) are passed as arguments or channel data.
Future<void> revealFileLocation(String path, {bool isDirectory = false}) async {
  if (Platform.isMacOS) {
    try {
      final opened = await const MethodChannel('chai/files').invokeMethod<bool>(
          'reveal', {'path': path, 'directory': isDirectory});
      if (opened == true) return;
    } on MissingPluginException {
      // Older runners can still open the containing folder.
    }
  } else if (Platform.isWindows) {
    await Process.run('explorer.exe',
        [isDirectory ? path : '/select,${p.windows.normalize(path)}']);
    return;
  }
  if (!await launchUrl(Uri.directory(isDirectory ? path : p.dirname(path)))) {
    throw const FileSystemException('Could not open file location');
  }
}
