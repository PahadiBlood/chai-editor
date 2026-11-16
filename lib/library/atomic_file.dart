import 'dart:io';
import 'package:path/path.dart' as p;

final _writer = AtomicFileWriter();

/// Same-directory replacement, serialized per destination across service instances.
Future<void> writeFileAtomic(String path, String text) =>
    _writer.write(path, text);

class AtomicFileWriter {
  AtomicFileWriter({this.afterParentCreated});

  // Allows deterministic simulation of a folder disappearing during a write.
  final Future<void> Function(Directory parent, int attempt)?
      afterParentCreated;
  final _pending = <String, Future<void>>{};
  int _serial = 0;

  Future<void> write(String path, String text) {
    path = p.normalize(p.absolute(path));
    final previous = _pending[path] ?? Future<void>.value();
    final operation = previous.then((_) => _replace(path, text));
    final settled = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    _pending[path] = settled;
    settled.then((_) {
      if (identical(_pending[path], settled)) _pending.remove(path);
    });
    return operation;
  }

  Future<void> _replace(String path, String text) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final parent = Directory(p.dirname(path));
      File? temporary;
      try {
        await parent.create(recursive: true);
        await afterParentCreated?.call(parent, attempt);
        temporary = File(p.join(parent.path,
            '.${p.basename(path)}.${DateTime.now().microsecondsSinceEpoch}.${_serial++}.tmp'));
        await temporary.writeAsString(text, flush: true);
        await temporary.rename(path);
        return;
      } on FileSystemException catch (error) {
        // The parent can be removed between mkdir and opening/renaming the temp.
        // Recreate it once. Permission/read-only failures require user recovery.
        if (attempt != 0 || ![2, 3].contains(error.osError?.errorCode)) rethrow;
      } finally {
        try {
          if (temporary != null && await temporary.exists()) {
            await temporary.delete();
          }
        } on FileSystemException catch (error) {
          stderr.writeln(
              'Chai temporary-file cleanup: ${error.osError?.message ?? 'unavailable'}');
        }
      }
    }
  }
}
