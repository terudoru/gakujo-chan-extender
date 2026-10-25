import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/file_system_gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final fromFile in [false, true]) {
    for (final mimeType in [
      'text/html; charset=UTF-8',
      'application/octet-stream',
      'application/pdf',
    ]) {
      test('rejects a page before saving (file: $fromFile, MIME: $mimeType)',
          () async {
        final directory = await Directory.systemTemp.createTemp('mbg-page-');
        var disposed = false;
        final bytes = Uint8List.fromList(utf8
            .encode('\uFEFF${' ' * 512}\n<!DoCtYpE hTmL><html>login</html>'));
        final temporary = File('${directory.path}/temporary');
        if (fromFile) await temporary.writeAsBytes(bytes);
        final service = FileSystemGakujoDownloadService(
          secureStorage: _MemorySecureStorage({
            'more_better_gakujo_download_root_path': directory.path,
          }),
          usesNativeDownloadRoot: false,
          authenticatedBytesLoader: (request, {userAgent}) async => fromFile
              ? AuthenticatedDownloadedFile.fromFile(
                  file: temporary,
                  cleanup: () async {
                    disposed = true;
                    await temporary.delete();
                  },
                  finalUrl: request.url,
                  mimeType: mimeType,
                )
              : AuthenticatedDownloadedFile(
                  bytes: bytes,
                  finalUrl: request.url,
                  mimeType: mimeType,
                ),
        );
        try {
          await expectLater(
            service.download(
              const GakujoDownloadRequest(
                url: 'https://gakujo.iess.niigata-u.ac.jp/file',
                method: 'GET',
                fileName: 'attachment.pdf',
                courseName: '',
                formFields: {},
              ),
              saveMode: DownloadSaveMode.flatToConfiguredFolder,
            ),
            throwsA(isA<PlatformException>()
                .having((error) => error.code, 'code', 'download_failed')
                .having((error) => error.message, 'message',
                    'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください')),
          );
          expect(await directory.list().toList(), isEmpty);
          if (fromFile) expect(disposed, isTrue);
        } finally {
          await directory.delete(recursive: true);
        }
      });
    }
  }

  for (final fromFile in [false, true]) {
    for (final (name, mimeType, body, dispositionName, urlPath, rejected) in [
      ('attachment.pdf', 'text/html', '%PDF-1.7', null, 'file', false),
      ('notes.txt', 'text/plain', '<html> is an HTML tag', null, 'file', false),
      (
        'Download',
        'text/html',
        '<html>attachment</html>',
        'page.HtM',
        'file',
        false
      ),
      (
        'Download',
        'text/html',
        '<html>attachment</html>',
        null,
        'page.HtM?download=1',
        false
      ),
      (
        'Download',
        'text/html',
        '<html>login</html>',
        null,
        'file?name=page.html',
        true
      ),
      ('', 'text/html', '<html>login</html>', null, 'file', true),
    ]) {
      test('save page policy: $name / $mimeType / $urlPath / file: $fromFile',
          () async {
        final directory = await Directory.systemTemp.createTemp('mbg-policy-');
        addTearDown(() => directory.delete(recursive: true));
        final bytes = Uint8List.fromList(utf8.encode(body));
        final temporary = File('${directory.path}/temporary');
        if (fromFile) await temporary.writeAsBytes(bytes);
        final service = FileSystemGakujoDownloadService(
          secureStorage: _MemorySecureStorage({
            'more_better_gakujo_download_root_path': directory.path,
          }),
          usesNativeDownloadRoot: false,
          authenticatedBytesLoader: (request, {userAgent}) async => fromFile
              ? AuthenticatedDownloadedFile.fromFile(
                  file: temporary,
                  cleanup: () async {
                    await temporary.delete();
                  },
                  finalUrl: 'https://gakujo.iess.niigata-u.ac.jp/$urlPath',
                  mimeType: mimeType,
                  contentDispositionFileName: dispositionName,
                )
              : AuthenticatedDownloadedFile(
                  bytes: bytes,
                  finalUrl: 'https://gakujo.iess.niigata-u.ac.jp/$urlPath',
                  mimeType: mimeType,
                  contentDispositionFileName: dispositionName,
                ),
        );
        final saving = service.download(
          GakujoDownloadRequest(
            url: 'https://gakujo.iess.niigata-u.ac.jp/$urlPath',
            method: 'GET',
            fileName: name,
            courseName: '',
            formFields: const {},
          ),
          saveMode: DownloadSaveMode.flatToConfiguredFolder,
        );
        if (rejected) {
          await expectLater(saving, throwsA(isA<PlatformException>()));
          expect(await directory.list().toList(), isEmpty);
        } else {
          await saving;
          final saved = (await directory.list().toList()).single as File;
          expect(await saved.readAsBytes(), bytes);
        }
      });
    }
  }

  test('resolves relative redirect locations against the current url', () {
    final finalUrl = resolveRedirectedDownloadUrl(
      Uri.parse('https://gakujo.iess.niigata-u.ac.jp/campusweb/start'),
      [Uri.parse('/campusweb/download/file.pdf')],
    );

    expect(
      finalUrl,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/download/file.pdf',
    );
  });

  test('resolves chained relative redirects in order', () {
    final finalUrl = resolveRedirectedDownloadUrl(
      Uri.parse('https://gakujo.iess.niigata-u.ac.jp/campusweb/start'),
      [
        Uri.parse('step1'),
        Uri.parse('download/file.pdf'),
      ],
    );

    expect(
      finalUrl,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/download/file.pdf',
    );
  });

  test('keeps the initial url when there are no redirects', () {
    final finalUrl = resolveRedirectedDownloadUrl(
      Uri.parse('https://gakujo.iess.niigata-u.ac.jp/campusweb/file.pdf'),
      const [],
    );

    expect(
      finalUrl,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/file.pdf',
    );
  });

  test('keeps the frontend display name when the server name differs',
      () async {
    final directory = await Directory.systemTemp.createTemp('mbg-download-');
    try {
      final storage = _MemorySecureStorage({
        'more_better_gakujo_download_root_path': directory.path,
      });
      final service = FileSystemGakujoDownloadService(
        secureStorage: storage,
        usesNativeDownloadRoot: false,
        authenticatedBytesLoader: (request, {userAgent}) async {
          expect(request.url, 'https://gakujo.iess.niigata-u.ac.jp/file');
          expect(userAgent, 'test-agent');
          return AuthenticatedDownloadedFile(
            bytes: Uint8List.fromList([1, 2, 3]),
            finalUrl: request.url,
            mimeType: 'application/pdf',
            contentDispositionFileName: 'report.pdf',
          );
        },
      );

      final result = await service.download(
        const GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/file',
          method: 'GET',
          courseName: '情報リテラシー',
          fileName: '画面表示の講義資料',
          formFields: {},
        ),
        userAgent: 'test-agent',
        cookieHeader: null,
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );

      expect(result.fileName, '画面表示の講義資料.pdf');
      expect(await File(result.location!).readAsBytes(), [1, 2, 3]);
    } finally {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('does not overwrite an existing file whose name differs only by case',
      () async {
    final directory = await Directory.systemTemp.createTemp('mbg-download-');
    try {
      final existingFile = File(
        '${directory.path}${Platform.pathSeparator}Lecture.PDF',
      );
      await existingFile.writeAsBytes([9, 9, 9]);
      final service = FileSystemGakujoDownloadService(
        secureStorage: _MemorySecureStorage({
          'more_better_gakujo_download_root_path': directory.path,
        }),
        usesNativeDownloadRoot: false,
        authenticatedBytesLoader: (request, {userAgent}) async =>
            AuthenticatedDownloadedFile(
          bytes: Uint8List.fromList([1, 2, 3]),
          finalUrl: request.url,
          mimeType: 'application/pdf',
        ),
      );

      final result = await service.download(
        const GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/file',
          method: 'GET',
          courseName: 'course',
          fileName: 'lecture.pdf',
          formFields: {},
        ),
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );

      expect(result.fileName, 'lecture (1).pdf');
      expect(await existingFile.readAsBytes(), [9, 9, 9]);
      expect(await File(result.location!).readAsBytes(), [1, 2, 3]);
    } finally {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('does not overwrite a file addressed by its Windows short name',
      () async {
    if (!Platform.isWindows) {
      markTestSkipped('Windows 8.3 short names are required for this test.');
      return;
    }

    final directory = await Directory.systemTemp.createTemp('mbg-download-');
    try {
      final existingFile = File(
        '${directory.path}${Platform.pathSeparator}LongLectureMaterial.pdf',
      );
      await existingFile.writeAsBytes([9, 9, 9]);
      final directoryListing = await Process.run(
        'cmd',
        ['/c', 'dir', '/x', directory.path],
      );
      final shortNameMatch = RegExp(
        r'\s([^\s]*~[^\s]*)\s+LongLectureMaterial\.pdf\s*$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(directoryListing.stdout as String);
      if (shortNameMatch == null) {
        markTestSkipped(
          'The temporary volume did not generate an 8.3 short name.',
        );
        return;
      }
      final shortName = shortNameMatch.group(1)!;
      final service = FileSystemGakujoDownloadService(
        secureStorage: _MemorySecureStorage({
          'more_better_gakujo_download_root_path': directory.path,
        }),
        usesNativeDownloadRoot: false,
        authenticatedBytesLoader: (request, {userAgent}) async =>
            AuthenticatedDownloadedFile(
          bytes: Uint8List.fromList([1, 2, 3]),
          finalUrl: request.url,
          mimeType: 'application/pdf',
        ),
      );

      final result = await service.download(
        GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/file',
          method: 'GET',
          courseName: 'course',
          fileName: shortName,
          formFields: const {},
        ),
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );

      expect(await existingFile.readAsBytes(), [9, 9, 9]);
      expect(result.fileName, isNot(equalsIgnoringCase(shortName)));
      expect(await File(result.location!).readAsBytes(), [1, 2, 3]);
    } finally {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('prefers authenticated bytes loader over a partial cookie header',
      () async {
    final directory = await Directory.systemTemp.createTemp('mbg-download-');
    try {
      final storage = _MemorySecureStorage({
        'more_better_gakujo_download_root_path': directory.path,
      });
      var loaderCalls = 0;
      final service = FileSystemGakujoDownloadService(
        secureStorage: storage,
        usesNativeDownloadRoot: false,
        authenticatedBytesLoader: (request, {userAgent}) async {
          loaderCalls += 1;
          return AuthenticatedDownloadedFile(
            bytes: Uint8List.fromList([4, 5, 6]),
            finalUrl: request.url,
            mimeType: 'application/pdf',
            contentDispositionFileName: 'authenticated.pdf',
          );
        },
      );

      final result = await service.download(
        const GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/file',
          method: 'GET',
          courseName: '情報リテラシー',
          fileName: '',
          formFields: {},
        ),
        cookieHeader: 'theme=dark',
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );

      expect(loaderCalls, 1);
      expect(result.fileName, 'authenticated.pdf');
      expect(await File(result.location!).readAsBytes(), [4, 5, 6]);
    } finally {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('saves reserved device names as readable files in a safe course folder',
      () async {
    final directory = await Directory.systemTemp.createTemp('mbg-download-');
    try {
      final service = FileSystemGakujoDownloadService(
        secureStorage: _MemorySecureStorage({
          'more_better_gakujo_download_root_path': directory.path,
        }),
        usesNativeDownloadRoot: false,
        authenticatedBytesLoader: (request, {userAgent}) async =>
            AuthenticatedDownloadedFile(
          bytes: Uint8List.fromList([7, 8, 9]),
          finalUrl: request.url,
          mimeType: 'application/pdf',
        ),
      );
      final result = await service.download(
        const GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/file',
          method: 'GET',
          courseName: 'AUX',
          fileName: 'NUL.pdf',
          formFields: {},
        ),
        saveMode: DownloadSaveMode.autoSortToConfiguredFolder,
      );
      expect(result.fileName, '_NUL.pdf');
      expect(File(result.location!).parent.path,
          '${directory.path}${Platform.pathSeparator}_AUX');
      expect(await File(result.location!).readAsBytes(), [7, 8, 9]);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('concurrent same-name downloads are saved as distinct files', () async {
    final directory = await Directory.systemTemp.createTemp('mbg-download-');
    try {
      final service = FileSystemGakujoDownloadService(
        secureStorage: _MemorySecureStorage({
          'more_better_gakujo_download_root_path': directory.path,
        }),
        usesNativeDownloadRoot: false,
        authenticatedBytesLoader: (request, {userAgent}) async {
          final index = int.parse(Uri.parse(request.url).queryParameters['n']!);
          return AuthenticatedDownloadedFile(
            bytes: Uint8List.fromList([index]),
            finalUrl: request.url,
            contentDispositionFileName: '同名資料.pdf',
          );
        },
      );

      final results = await Future.wait([
        for (var index = 0; index < 12; index += 1)
          service.download(
            GakujoDownloadRequest(
              url: 'https://gakujo.iess.niigata-u.ac.jp/file.pdf?n=$index',
              method: 'GET',
              courseName: '情報リテラシー',
              fileName: '同名資料.pdf',
              formFields: const {},
            ),
            saveMode: DownloadSaveMode.flatToConfiguredFolder,
          ),
      ]);

      expect(results.map((result) => result.fileName).toSet(), hasLength(12));
      final files = await directory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      expect(files, hasLength(12));
      final contents = <int>{};
      for (final file in files) {
        contents.add((await file.readAsBytes()).single);
      }
      expect(contents, {for (var index = 0; index < 12; index += 1) index});
    } finally {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('a 255-character name is shortened, saved once and reused',
      () async {
    final directory = await Directory.systemTemp.createTemp('mbg-download-');
    try {
      final base = List.filled(251, 'a').join();
      final desired = '$base.pdf';
      final existing =
          File('${directory.path}${Platform.pathSeparator}$desired');
      await existing.writeAsBytes([9]);
      final service = _dedupeService(directory, [1, 2, 3]);
      final request = GakujoDownloadRequest(
        url: _dedupeRequest.url,
        method: 'GET',
        courseName: 'course',
        fileName: desired,
        formFields: const {},
      );
      final first = await service.download(
        request,
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );
      // Names are bounded below the 255-unit limit before any collision.
      expect(first.fileName, '${base.substring(0, 196)}.pdf');
      expect(first.fileName.length, 200);
      expect(await File(first.location!).readAsBytes(), [1, 2, 3]);
      final second = await service.download(
        request,
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );
      expect(second.alreadySaved, isTrue);
      expect(second.location, first.location);
      expect(await existing.readAsBytes(), [9]);
      expect(await directory.list().length, 2);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('a deleted download can be saved again with its original name',
      () async {
    final directory = await Directory.systemTemp.createTemp('mbg-download-');
    try {
      final service = FileSystemGakujoDownloadService(
        secureStorage: _MemorySecureStorage({
          'more_better_gakujo_download_root_path': directory.path,
        }),
        usesNativeDownloadRoot: false,
        authenticatedBytesLoader: (request, {userAgent}) async {
          return AuthenticatedDownloadedFile(
            bytes: Uint8List.fromList([1, 2, 3]),
            finalUrl: request.url,
            contentDispositionFileName: 'internal_98765.pdf',
          );
        },
      );
      const request = GakujoDownloadRequest(
        url: 'https://gakujo.iess.niigata-u.ac.jp/file',
        method: 'GET',
        courseName: '情報リテラシー',
        fileName: '再取得資料',
        formFields: {},
      );

      final first = await service.download(
        request,
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );
      await File(first.location!).delete();
      final second = await service.download(
        request,
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );

      expect(first.fileName, '再取得資料.pdf');
      expect(second.fileName, '再取得資料.pdf');
      expect(await File(second.location!).readAsBytes(), [1, 2, 3]);
    } finally {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  group('configured folder duplicate downloads', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mbg-download-dedupe-');
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    for (final existingName in ['x.pdf', 'x (1).pdf', 'X.PDF', 'X (999).PDF']) {
      test('reuses identical $existingName and removes only the new file',
          () async {
        final bytes = List<int>.generate(2 * 64 * 1024 + 17, (i) => i % 251);
        final existing = File(
          '${directory.path}${Platform.pathSeparator}$existingName',
        );
        await existing.writeAsBytes(bytes);
        await existing.setLastModified(DateTime.utc(2020));
        final modified = await existing.lastModified();

        final result = await _dedupeService(directory, bytes).download(
          _dedupeRequest,
          saveMode: DownloadSaveMode.flatToConfiguredFolder,
        );

        expect(result.alreadySaved, isTrue);
        expect(result.fileName, existingName);
        expect(result.location, existing.path);
        expect(result.courseName, isEmpty);
        expect(await directory.list().map((file) => file.path).toList(),
            [existing.path]);
        expect(await existing.readAsBytes(), bytes);
        expect(await existing.lastModified(), modified);
      });
    }

    for (final existingBytes in [
      [1, 2],
      [1, 2, 4],
      List<int>.filled(2 * 64 * 1024 + 17, 1)..last = 2,
    ]) {
      test('keeps different content of size ${existingBytes.length}', () async {
        final bytes = List<int>.filled(
          existingBytes.length < 4 ? 3 : existingBytes.length,
          1,
        );
        final existing =
            File('${directory.path}${Platform.pathSeparator}x.pdf');
        await existing.writeAsBytes(existingBytes);
        await existing.setLastModified(DateTime.utc(2020));
        final modified = await existing.lastModified();

        final result = await _dedupeService(directory, bytes).download(
          _dedupeRequest,
          saveMode: DownloadSaveMode.flatToConfiguredFolder,
        );

        expect(result.alreadySaved, isFalse);
        expect(result.fileName, 'x (1).pdf');
        expect(result.location,
            '${directory.path}${Platform.pathSeparator}x (1).pdf');
        expect(await File(result.location!).readAsBytes(), bytes);
        expect(await directory.list().length, 2);
        expect(await existing.readAsBytes(), existingBytes);
        expect(await existing.lastModified(), modified);
      });
    }

    test('ignores identical files with unrelated or out-of-range names',
        () async {
      final bytes = [1, 2, 3];
      final existing = <File>[];
      for (final name in [
        'other.pdf',
        'x (0).pdf',
        'x (01).pdf',
        'x (1000).pdf'
      ]) {
        final file = File('${directory.path}${Platform.pathSeparator}$name');
        await file.writeAsBytes(bytes);
        existing.add(file);
      }

      final result = await _dedupeService(directory, bytes).download(
        _dedupeRequest,
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );

      expect(result.alreadySaved, isFalse);
      expect(result.fileName, 'x.pdf');
      expect(await File(result.location!).readAsBytes(), bytes);
      expect(await directory.list().length, existing.length + 1);
      for (final file in existing) {
        expect(await file.readAsBytes(), bytes);
      }
    });

    test('reuses an empty file after comparing both streams to EOF', () async {
      final existing = File('${directory.path}${Platform.pathSeparator}x.pdf');
      await existing.writeAsBytes([]);
      final result = await _dedupeService(directory, []).download(
        _dedupeRequest,
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );

      expect(result.alreadySaved, isTrue);
      expect(result.location, existing.path);
      expect(await existing.length(), 0);
      expect(await directory.list().length, 1);
    });

    test('compares only files in the selected course folder', () async {
      final bytes = [1, 2, 3];
      final rootFile = File('${directory.path}${Platform.pathSeparator}x.pdf');
      await rootFile.writeAsBytes(bytes);
      final service = _dedupeService(directory, bytes);
      final first = await service.download(
        _dedupeRequest,
        saveMode: DownloadSaveMode.autoSortToConfiguredFolder,
      );
      final second = await service.download(
        _dedupeRequest,
        saveMode: DownloadSaveMode.autoSortToConfiguredFolder,
      );

      expect(first.alreadySaved, isFalse);
      expect(second.alreadySaved, isTrue);
      expect(second.courseName, 'course');
      expect(second.fileName, 'x.pdf');
      expect(second.location, first.location);
      expect(await File(first.location!).parent.list().length, 1);
      expect(await rootFile.readAsBytes(), bytes);
      expect(await File(first.location!).readAsBytes(), bytes);
    });

    test('concurrent identical downloads all return the one completed file',
        () async {
      final service = _dedupeService(directory, [1, 2, 3]);
      final results = await Future.wait([
        for (var index = 0; index < 4; index += 1)
          service.download(
            _dedupeRequest,
            saveMode: DownloadSaveMode.flatToConfiguredFolder,
          ),
      ]);

      expect(results.where((result) => !result.alreadySaved), hasLength(1));
      expect(results.map((result) => result.location).toSet(), hasLength(1));
      expect(results.map((result) => result.fileName).toSet(), {'x.pdf'});
      expect(await directory.list().length, 1);
      expect(await File(results.first.location!).readAsBytes(), [1, 2, 3]);
    });
  });
}

const _dedupeRequest = GakujoDownloadRequest(
  url: 'https://gakujo.iess.niigata-u.ac.jp/file',
  method: 'GET',
  courseName: 'course',
  fileName: 'x.pdf',
  formFields: {},
);

FileSystemGakujoDownloadService _dedupeService(
  Directory directory,
  List<int> bytes,
) {
  return FileSystemGakujoDownloadService(
    secureStorage: _MemorySecureStorage({
      'more_better_gakujo_download_root_path': directory.path,
    }),
    usesNativeDownloadRoot: false,
    authenticatedBytesLoader: (request, {userAgent}) async =>
        AuthenticatedDownloadedFile(
      bytes: Uint8List.fromList(bytes),
      finalUrl: request.url,
      mimeType: 'application/pdf',
    ),
  );
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage(this.values);

  final Map<String, String> values;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }
}
