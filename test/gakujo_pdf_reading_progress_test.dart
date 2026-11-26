import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_pdf_reading_progress.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late GakujoPdfReadingProgress progress;
  late File progressFile;

  String digest(int n) => n.toRadixString(16).padLeft(64, '0');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdf-reading-progress');
    progress = GakujoPdfReadingProgress(directory: directory);
    progressFile = File.fromUri(
      directory.uri.resolve('pdf_reading_progress.json'),
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test('remembers only each digest and page across instances', () async {
    await Future.wait([
      progress.save(digest(1), 42),
      progress.save(digest(2), 3),
      progress.save(digest(1), 9),
    ]);

    final restored = GakujoPdfReadingProgress(directory: directory);
    expect(await restored.read(digest(1)), 9);
    expect(await restored.read(digest(2)), 3);
    expect(await restored.read(digest(3)), isNull);
    expect(jsonDecode(await progressFile.readAsString()), {
      digest(2): 3,
      digest(1): 9,
    });
  });

  test('ignores invalid keys and out-of-bounds page numbers', () async {
    await progress.save('https://example.com/document.pdf', 5);
    await progress.save(digest(1), 0);
    await progress.save(digest(2), GakujoPdfReadingProgress.maxPage + 1);
    expect(await progressFile.exists(), isFalse);
    expect(await progress.read('not-a-digest'), isNull);

    await progressFile.writeAsString(
      jsonEncode({digest(1): -14, digest(2): '4', digest(3): 12, 'bad': 4}),
    );
    expect(await progress.read(digest(1)), isNull);
    expect(await progress.read(digest(2)), isNull);
    expect(await progress.read(digest(3)), 12);
  });

  test('a failed save does not block later writes on the same instance', () async {
    final file = File.fromUri(directory.uri.resolve('unavailable'));
    await file.writeAsString('A file occupies the intended directory path.');
    final blockedDirectory = Directory(file.path);
    final progress = GakujoPdfReadingProgress(directory: blockedDirectory);
    await expectLater(
      progress.save(digest(1), 7),
      throwsA(isA<FileSystemException>()),
    );

    await file.delete();
    await blockedDirectory.create();
    await progress.save(digest(2), 9);
    expect(await progress.read(digest(1)), isNull);
    expect(await progress.read(digest(2)), 9);
  });

  test(
    'limits stored progress to the most recently updated documents',
    () async {
      final seeded = {for (var i = 1; i <= 128; i++) digest(i): 3};
      await progressFile.writeAsString(jsonEncode(seeded));
      await progress.save(digest(1), 7);
      await progress.save(digest(129), 4);

      expect(await progress.read(digest(1)), 7);
      expect(await progress.read(digest(2)), isNull);
      expect(await progress.read(digest(129)), 4);
    },
  );

  test(
    'clear runs after pending writes and removes owned temporary files',
    () async {
      final orphan = File('${progressFile.path}.123.456.tmp');
      await orphan.writeAsString('{}');
      final unrelated = File.fromUri(directory.uri.resolve('other.tmp'));
      await unrelated.writeAsString('keep');

      await Future.wait([progress.save(digest(1), 2), progress.clear()]);
      expect(await progress.read(digest(1)), isNull);
      expect(await progressFile.exists(), isFalse);
      expect(await orphan.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
    },
  );
}
