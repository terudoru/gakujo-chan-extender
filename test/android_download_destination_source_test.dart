import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('failed per-file downloads delete the document created by the picker',
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
        r'GakujoDownloadStreams\.copy\([\s\S]*?'
        r'cleanupFailedDestination = \{\s*try \{\s*if \(!'
        r'DocumentsContract\.deleteDocument\(contentResolver, destination\)'
        r'[\s\S]*?catch \(error: Exception\)',
      )),
    );
  });
}
