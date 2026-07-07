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

  test('uses authenticated bytes loader when no cookie header is available',
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
          fileName: '',
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
