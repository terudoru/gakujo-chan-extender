import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/file_system_gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

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

  test('uses authenticated bytes loader and its server filename', () async {
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
          fileName: 'ダウンロード',
          formFields: {},
        ),
        userAgent: 'test-agent',
        cookieHeader: null,
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );

      expect(result.fileName, 'report.pdf');
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
            contentDispositionFileName: '再取得資料.pdf',
          );
        },
      );
      const request = GakujoDownloadRequest(
        url: 'https://gakujo.iess.niigata-u.ac.jp/file',
        method: 'GET',
        courseName: '情報リテラシー',
        fileName: 'ダウンロード',
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
