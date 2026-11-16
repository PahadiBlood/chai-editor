import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'atomic_file.dart';
import 'library_service.dart';

/// Persist a storage mode, never a username or absolute path. Each launch asks
/// the OS for that account's directories. App storage is opt-in recovery only.
class LibraryLocation {
  LibraryLocation(
      {required this.documentsDirectory, required this.supportDirectory});
  final Future<Directory> Function() documentsDirectory;
  final Future<Directory> Function() supportDirectory;

  Future<LibraryService> resolve() async {
    var useSupport = false;
    try {
      final directory = await supportDirectory();
      final preference = File(p.join(directory.path, 'library-location.json'));
      if (await preference.exists()) {
        final value = jsonDecode(await preference.readAsString());
        useSupport = value is Map && value['storage'] == 'application-support';
      }
    } on FileSystemException catch (error) {
      stderr.writeln(
          'Chai storage preference unavailable: ${error.osError?.message ?? 'unavailable'}');
    } on FormatException {
      stderr.writeln(
          'Chai storage preference is invalid; using the default location.');
    } catch (error) {
      stderr.writeln('Chai storage preference lookup failed: $error');
    }
    final directory =
        useSupport ? await supportDirectory() : await documentsDirectory();
    return LibraryService(Directory(p.join(directory.path, 'ChaiEditor')));
  }

  Future<LibraryService> appStorage() async => LibraryService(
      Directory(p.join((await supportDirectory()).path, 'ChaiEditor')));

  Future<void> rememberAppStorage() async {
    final directory = await supportDirectory();
    await writeFileAtomic(p.join(directory.path, 'library-location.json'),
        jsonEncode({'storage': 'application-support'}));
  }
}
