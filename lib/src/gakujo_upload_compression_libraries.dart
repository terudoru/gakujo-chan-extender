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

  /// Asset files per requested kind, in load order. PDF parsing runs in a
  /// dedicated, terminable worker instead of blocking the page thread.
  static const _assets = {
    'pdf': ['qpdf-worker.js', 'qpdf.js'],
    'preview': ['pdf.worker.min.js', 'pdf.min.js'],
    'office': ['jszip.min.js'],
  };

  static final Map<String, Future<String>> _cache = {};

  /// Returns the script that defines the libraries for [kind] and then tells
  /// the page they are ready, or null for an unknown request.
  static Future<String?> scriptFor(String kind, {AssetBundle? bundle}) async {
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
    if (kind.trim() == 'pdf') {
      final wasm = await loader.load('$_assetDirectory/qpdf.wasm');
      return buildInjectionScript(kind.trim(), [
        ...sources,
        base64Encode(
          wasm.buffer.asUint8List(wasm.offsetInBytes, wasm.lengthInBytes),
        ),
      ]);
    }
    return buildInjectionScript(kind.trim(), sources);
  }

  /// Wraps each library so a page-level AMD or CommonJS loader cannot capture
  /// it, then signals the waiting compression script.
  static String buildInjectionScript(String kind, List<String> sources) {
    final buffer = StringBuffer();
    if (kind == 'pdf' && sources.length == 3) {
      buffer.writeln(
        'window.__MBG_QPDF_WORKER_URL = URL.createObjectURL('
        'new Blob([${jsonEncode(sources[0])}], {type: "text/javascript"}));',
      );
      buffer.writeln(
        'window.__MBG_QPDF_MODULE_URL = URL.createObjectURL('
        'new Blob([${jsonEncode(sources[1])}], {type: "text/javascript"}));',
      );
      buffer.writeln(
        '(function() { var raw = atob(${jsonEncode(sources[2])});'
        ' var bytes = new Uint8Array(raw.length);'
        ' for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);'
        ' window.__MBG_QPDF_WASM_URL = URL.createObjectURL('
        'new Blob([bytes], {type: "application/wasm"})); })();',
      );
    } else if (kind == 'preview' && sources.isNotEmpty) {
      buffer.writeln(
        'window.__MBG_PDF_WORKER_URL = URL.createObjectURL('
        'new Blob([${jsonEncode(sources.first)}], {type: "text/javascript"}));',
      );
    }
    for (final source
        in kind == 'pdf'
            ? <String>[]
            : kind == 'preview'
            ? sources.skip(1)
            : sources) {
      buffer
        ..writeln('(function(define, module, exports) {')
        ..writeln(source)
        ..writeln('}).call(window);');
    }
    final callback = kind == 'preview'
        ? '__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED'
        : '__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED';
    buffer.writeln(
      'if (window.$callback) {'
      ' window.$callback(${jsonEncode(kind)});'
      ' }',
    );
    return buffer.toString();
  }
}
