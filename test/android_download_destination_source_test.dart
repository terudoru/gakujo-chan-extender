import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
      'picker launch failures clear pending results and payloads before replying',
      () {
    final source = File(
      'android/app/src/main/kotlin/net/yoshida/morebettergakujo/MainActivity.kt',
    ).readAsStringSync();
    for (final (method, nextMethod, fields) in [
      (
        'exportDownloadedFile',
        'handleExportFileResult',
        ['pendingExportResult', 'pendingExportBytes', 'pendingExportFileName'],
      ),
      (
        'pickDownloadRoot',
        'handlePickDownloadRootResult',
        ['pendingPickRootResult'],
      ),
      (
        'downloadToPickedFile',
        'performDownload',
        ['pendingPickFileResult', 'pendingPickFileArgs'],
      ),
    ]) {
      final picker = source.substring(
        source.indexOf('private fun $method('),
        source.indexOf('private fun $nextMethod('),
      );
      final handler = RegExp(
        r'try \{\s*@Suppress\("DEPRECATION"\)\s*'
        r'startActivityForResult\([^\n]+\)\s*'
        r'\} catch \(error: Exception\) \{([^}]+)\}',
      ).firstMatch(picker)?.group(1);
      expect(handler, isNotNull, reason: method);
      final cleanup = handler!;
      expect(cleanup, contains('result.error("picker_failed",'));
      for (final field in fields) {
        expect(cleanup.indexOf('$field = null'),
            inInclusiveRange(0, cleanup.indexOf('result.error(') - 1),
            reason: '$method clears $field before replying');
      }
    }
  });

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
