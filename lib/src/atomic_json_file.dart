import 'dart:convert';
import 'dart:io';

Future<void> writeAtomicJsonFile(
  File file,
  Object value, {
  Future<void> Function(File temporary, File target)? atomicReplace,
}) async {
  await file.parent.create(recursive: true);
  final temporaryFile = File(
    '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temporaryFile.writeAsString(jsonEncode(value), flush: true);
    if (atomicReplace == null) {
      await temporaryFile.rename(file.path);
    } else {
      await atomicReplace(temporaryFile, file);
    }
  } finally {
    try {
      if (await temporaryFile.exists()) await temporaryFile.delete();
    } on FileSystemException {
      // Cleanup must not hide the original write or replace failure.
    }
  }
}
