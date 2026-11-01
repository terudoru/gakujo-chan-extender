import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/app_licenses.dart';

final _separator = '-' * 80;

class _LicenseBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'LICENSE.md') {
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode('App license')),
      );
    }
    if (key == 'NOTICES.Z') {
      final bytes = Uint8List.fromList(
        gzip.encode(utf8.encode('shared\n\nShared license')),
      );
      return ByteData.sublistView(bytes);
    }
    throw FlutterError('Missing asset: $key');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    switch (key) {
      case 'assets/pdf_preview/web/assets/NOTICES':
        return 'shared\n\nShared license\n$_separator\nviewer\n\nViewer license';
      default:
        throw FlutterError('Missing asset: $key');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(LicenseRegistry.reset);

  test('parses multiple packages and CRLF notices', () {
    final text =
        'first\nsecond\n\nFirst license\n$_separator\nthird\n\nSecond license';
    for (final input in [text, text.replaceAll('\n', '\r\n')]) {
      final entries = parseFlutterNotices(input);
      expect(entries, hasLength(2));
      expect(entries[0].packages, ['first', 'second']);
      expect(entries[0].text, 'First license');
      expect(entries[1].packages, ['third']);
      expect(entries[1].text, 'Second license');
    }
  });

  test('registers available assets and deduplicates viewer notices', () async {
    LicenseRegistry.reset();
    registerBundledLicenses(bundle: _LicenseBundle());
    final entries = await LicenseRegistry.licenses.toList();
    expect(
      entries.where((entry) => entry.packages.contains('More Better Gakujo')),
      hasLength(1),
    );
    expect(
      entries.where((entry) => entry.packages.contains('viewer')),
      hasLength(1),
    );
    expect(
      entries.where((entry) => entry.packages.contains('shared')),
      isEmpty,
    );
  });

  test('loads every bundled license asset', () async {
    LicenseRegistry.reset();
    registerBundledLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = {for (final entry in entries) ...entry.packages};
    for (final package in [
      'More Better Gakujo',
      'pdf.js',
      'pdf-lib',
      'JSZip',
      'qpdf',
      'zlib',
      'libjpeg',
      'PDFium',
      'freetype',
      'Noto Sans CJK',
      'GNU Unifont',
      // Only in the PDF preview viewer's notices.
      'pdfrx',
    ]) {
      expect(packages, contains(package));
    }
  });
}
