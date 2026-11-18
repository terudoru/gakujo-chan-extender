import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:test/test.dart';

Future<Directory> tempDirectory() async {
  final directory = await Directory.systemTemp.createTemp('mbg-retention-');
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

Future<File> writeFile(
  Directory directory,
  String name, {
  DateTime? modified,
  String content = '{}',
}) async {
  final file = File.fromUri(directory.uri.resolve(name));
  await file.writeAsString(content, flush: true);
  if (modified != null) await file.setLastModified(modified);
  return file;
}

Future<List<String>> fileNames(Directory directory) =>
    directory.list().map((entry) => entry.uri.pathSegments.last).toList();

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

  test(
    'each post-correction write keeps its file and nine newest backups',
    () async {
      final directory = await tempDirectory();
      final now = DateTime.now();
      final history = <String>[];
      for (var i = 0; i < 10; i++) {
        final time = now.add(Duration(days: 365, hours: 6 * i));
        final name = 'auto-backup-${time.microsecondsSinceEpoch}.json';
        await writeFile(directory, name, modified: time);
        history.add(name);
      }

      for (var i = 0; i < 2; i++) {
        final name = 'auto-backup-${now.microsecondsSinceEpoch + i}.json';
        final content = '{"save":$i}';
        final current = await writeFile(directory, name, content: content);
        await pruneJsonFilesForRetention(
          directory,
          keep: 10,
          fileNamePrefix: 'auto-backup-',
          protectedFile: current,
        );
        expect(await current.exists(), isTrue);
        expect(await current.readAsString(), content);
        expect(
          await fileNames(directory),
          unorderedEquals([name, ...history.skip(1)]),
        );
      }
    },
  );

  for (final (label, days, survivors) in [
    ('past', [-3, -2, -1], [-2, -1]),
    ('mixed', [-3, -1, 2], [-1, 2]),
    ('below capacity', [1], [1]),
  ]) {
    test(
      'protected backup preserves mtime order with $label history',
      () async {
        final directory = await tempDirectory();
        final now = DateTime.now();
        for (final day in days) {
          await writeFile(
            directory,
            '$day.json',
            modified: now.add(Duration(days: day)),
          );
        }
        final current = await writeFile(directory, 'current.json');
        await pruneJsonFilesForRetention(
          directory,
          keep: 3,
          protectedFile: current,
        );
        expect(
          await fileNames(directory),
          unorderedEquals([
            'current.json',
            for (final day in survivors) '$day.json',
          ]),
        );
      },
    );
  }

  for (final candidate in ['missing', 'outside', 'manual', 'non-JSON']) {
    test('$candidate file does not reserve a retention slot', () async {
      final directory = await tempDirectory();
      final now = DateTime.now();
      await writeFile(
        directory,
        'auto-backup-1.json',
        modified: now.subtract(const Duration(days: 1)),
      );
      await writeFile(directory, 'auto-backup-2.json');
      final manual = await writeFile(directory, 'manual-backup-1.json');
      final nonJson = await writeFile(directory, 'auto-backup-3.txt');
      final outside = await writeFile(
        await tempDirectory(),
        'auto-backup-1.json',
      );
      final protectedFile = switch (candidate) {
        'outside' => outside,
        'manual' => manual,
        'non-JSON' => nonJson,
        _ => File.fromUri(directory.uri.resolve('auto-backup-missing.json')),
      };
      await pruneJsonFilesForRetention(
        directory,
        keep: 1,
        fileNamePrefix: 'auto-backup-',
        protectedFile: protectedFile,
      );
      expect(
        await fileNames(directory),
        unorderedEquals([
          'auto-backup-2.json',
          'manual-backup-1.json',
          'auto-backup-3.txt',
        ]),
      );
      expect(await outside.exists(), isTrue);
    });
  }

  test('keep zero removes even the protected file', () async {
    final directory = await tempDirectory();
    final current = await writeFile(directory, 'current.json');
    await pruneJsonFilesForRetention(
      directory,
      keep: 0,
      protectedFile: current,
    );
    expect(await fileNames(directory), isEmpty);
  });
}
