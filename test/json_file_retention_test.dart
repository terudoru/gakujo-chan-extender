import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:test/test.dart';

void main() {
  test('auto backup pruning preserves manual backups', () async {
    final directory = await Directory.systemTemp.createTemp(
      'more-better-gakujo-backup-retention-',
    );
    try {
      final baseTime = DateTime(2026, 7, 22, 12);
      final manual = File(
        '${directory.path}${Platform.pathSeparator}manual-backup-1.json',
      );
      await manual.writeAsString('{}');
      await manual.setLastModified(baseTime.subtract(const Duration(days: 1)));

      for (var index = 0; index < 12; index += 1) {
        final file = File(
          '${directory.path}${Platform.pathSeparator}auto-backup-$index.json',
        );
        await file.writeAsString('{}');
        await file.setLastModified(baseTime.add(Duration(minutes: index)));
      }

      await pruneJsonFilesForRetention(
        directory,
        keep: 10,
        fileNamePrefix: 'auto-backup-',
      );

      final remainingNames = await directory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .map((file) => file.path.split(Platform.pathSeparator).last)
          .toList();
      expect(await manual.exists(), isTrue);
      expect(
        remainingNames.where((name) => name.startsWith('auto-backup-')),
        hasLength(10),
      );
      expect(remainingNames, isNot(contains('auto-backup-0.json')));
      expect(remainingNames, isNot(contains('auto-backup-1.json')));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
