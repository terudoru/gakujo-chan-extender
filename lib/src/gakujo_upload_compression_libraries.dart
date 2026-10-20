import 'dart:convert';

import 'package:flutter/services.dart';

/// Loads the bundled JavaScript libraries the upload compression script needs
/// for PDF and Office files. They are injected only on request because they
/// are too large to add to every page.
class GakujoUploadCompressionLibraries {
  const GakujoUploadCompressionLibraries._();

  /// JavaScript channel the page script uses to request a library kind.
  static const channelName = 'MbgUploadCompression';

  static const _assetDirectory = 'assets/js/upload_compression';

  /// Asset files per requested kind, in load order. pdf.js finds the worker
  /// through `globalThis.pdfjsWorker` and then runs it on the page thread,
  /// which avoids loading a worker script from a URL the page may block.
  static const _assets = {
    'pdf': ['pdf.worker.min.js', 'pdf.min.js', 'pdf-lib.min.js'],
    'office': ['jszip.min.js'],
  };

  static final Map<String, Future<String>> _cache = {};

  /// Returns the script that defines the libraries for [kind] and then tells
  /// the page they are ready, or null for an unknown request.
  static Future<String?> scriptFor(
    String kind, {
    AssetBundle? bundle,
  }) async {
    final files = _assets[kind.trim()];
    if (files == null) {
      return null;
    }
    final loader = bundle ?? rootBundle;
    final sources = await Future.wait([
      for (final file in files)
        _cache.putIfAbsent(
          '$_assetDirectory/$file',
          () => loader.loadString('$_assetDirectory/$file', cache: false),
        ),
    ]);
    return buildInjectionScript(kind.trim(), sources);
  }

  /// Wraps each library so a page-level AMD or CommonJS loader cannot capture
  /// it, then signals the waiting compression script.
  static String buildInjectionScript(String kind, List<String> sources) {
    final buffer = StringBuffer();
    for (final source in sources) {
      buffer
        ..writeln('(function(define, module, exports) {')
        ..writeln(source)
        ..writeln('}).call(window);');
    }
    buffer.writeln(
      'if (window.__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED) {'
      ' window.__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED(${jsonEncode(kind)});'
      ' }',
    );
    return buffer.toString();
  }
}
