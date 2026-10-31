import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef _Notice = ({List<String> packages, String text});

const _bundledLicenses = <(String, String)>[
  ('More Better Gakujo', 'LICENSE.md'),
  ('pdf.js', 'assets/js/upload_compression/LICENSE.pdfjs'),
  ('pdf.js', 'assets/js/upload_compression/LICENSE.pdfjs-cmaps'),
  ('pdf.js', 'assets/js/upload_compression/LICENSE.pdfjs-license_foxit'),
  ('pdf.js', 'assets/js/upload_compression/LICENSE.pdfjs-license_liberation'),
  ('pdf-lib', 'assets/js/upload_compression/LICENSE.pdf-lib.md'),
  ('JSZip', 'assets/js/upload_compression/LICENSE.jszip.md'),
  ('qpdf', 'assets/js/upload_compression/LICENSE.qpdf'),
  ('zlib', 'assets/js/upload_compression/LICENSE.zlib'),
  ('libjpeg', 'assets/js/upload_compression/LICENSE.libjpeg-9f'),
  ('libjpeg', 'assets/js/upload_compression/LICENSE.libjpeg-ijg'),
  ('libjpeg', 'assets/js/upload_compression/LICENSE.libjpeg-turbo'),
  ('Noto Sans CJK', 'tools/pdf_preview/licenses/NotoSansCJK.txt'),
  ('GNU Unifont', 'tools/pdf_preview/licenses/Unifont-OFL.txt'),
];

const _pdfiumLicenses = <(String, String)>[
  ('PDFium', 'LICENSE'),
  ('PDFium', 'pdfium.txt'),
  ('abseil', 'abseil.txt'),
  ('agg23', 'agg23.txt'),
  ('dragonbox', 'dragonbox-Apache2-LLVM.txt'),
  ('dragonbox', 'dragonbox-Boost.txt'),
  ('fast_float', 'fast_float.txt'),
  ('freetype', 'freetype.txt'),
  ('harfbuzz', 'harfbuzz.txt'),
  ('highway', 'highway.txt'),
  ('icu', 'icu.txt'),
  ('lcms', 'lcms.txt'),
  ('libjpeg-turbo', 'libjpeg_turbo.ijg'),
  ('libjpeg-turbo', 'libjpeg_turbo.md'),
  ('libopenjpeg', 'libopenjpeg.txt'),
  ('libpng', 'libpng.txt'),
  ('simdutf', 'simdutf.txt'),
  ('zlib', 'zlib.txt'),
];

List<({List<String> packages, String text})> parseFlutterNotices(
  String notices,
) {
  final normalized = notices.replaceAll('\r\n', '\n');
  return [
    for (final entry in normalized.split('\n${'-' * 80}\n'))
      if (entry.indexOf('\n\n') case final split when split >= 0)
        (
          packages: entry.substring(0, split).split('\n'),
          text: entry.substring(split + 2),
        ),
  ];
}

List<_Notice> _viewerNotices(({String viewer, Uint8List? appBytes}) input) {
  var appEntries = <_Notice>[];
  if (input.appBytes != null) {
    try {
      appEntries = parseFlutterNotices(
        utf8.decode(gzip.decode(input.appBytes!)),
      );
    } on Object {
      // Show all viewer notices if app notices cannot be decoded.
    }
  }
  String key(_Notice entry) => jsonEncode([entry.packages, entry.text]);
  final appKeys = appEntries.map(key).toSet();
  return parseFlutterNotices(input.viewer)
      .where((entry) => !appKeys.contains(key(entry)))
      .toList();
}

void registerBundledLicenses({AssetBundle? bundle}) {
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    for (final (package, path) in [
      ..._bundledLicenses,
      for (final (package, file) in _pdfiumLicenses)
        (package, 'tools/pdf_preview/licenses/pdfium/$file'),
    ]) {
      try {
        final data = await assets.load(path);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        String text;
        try {
          text = utf8.decode(bytes);
        } on FormatException {
          // PDFium's freetype.txt is Latin-1.
          text = latin1.decode(bytes);
        }
        yield LicenseEntryWithLineBreaks([package], text);
      } on Object {
        // An unavailable asset should not hide the remaining licenses.
      }
    }
    try {
      final viewer = await assets.loadString(
        'assets/pdf_preview/web/assets/NOTICES',
      );
      Uint8List? appBytes;
      try {
        final data = await assets.load('NOTICES.Z');
        appBytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      } on Object {
        // Viewer notices remain available without deduplication.
      }
      final entries = await compute(_viewerNotices, (
        viewer: viewer,
        appBytes: appBytes,
      ));
      for (final entry in entries) {
        yield LicenseEntryWithLineBreaks(entry.packages, entry.text);
      }
    } on Object {
      // The viewer notices may be unavailable independently of other assets.
    }
  });
}
