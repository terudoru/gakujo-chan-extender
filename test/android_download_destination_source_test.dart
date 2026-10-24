import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('failed per-file downloads delete only a known empty picked document',
      () {
    final source = File(
      'android/app/src/main/kotlin/net/yoshida/morebettergakujo/MainActivity.kt',
    ).readAsStringSync();
    final download = source.substring(
      source.indexOf('private fun performDownloadToUri('),
      source.indexOf('private fun chooseFileName('),
    );
    expect(
      download,
      matches(RegExp(
        r'contentResolver\.query\(destination, arrayOf\(OpenableColumns.SIZE\)'
        r'[\s\S]*?!cursor\.isNull\(index\)[\s\S]*?cursor\.getLong\(index\)'
        r'[\s\S]*?GakujoDownloadStreams\.copy\([\s\S]*?'
        r'cleanupFailedDestination = \{\s*'
        r'if \(GakujoDownloadStreams\.shouldDeleteFailedPickedDestination\(initialSize\)\)'
        r'\s*\{\s*try \{\s*if \(!'
        r'DocumentsContract\.deleteDocument\(contentResolver, destination\)'
        r'[\s\S]*?catch \(error: Exception\)',
      )),
    );
  });
}
