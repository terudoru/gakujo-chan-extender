import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Deduplicates library requests within a navigation while allowing retries
/// after failures and ignoring completion from an older document.
class GakujoUploadLibraryGate {
  int? _revision;
  final _loaded = <String>{};
  final _pending = <String, Future<void>>{};

  Future<void> run({
    required int revision,
    required String kind,
    required Future<bool> Function() inject,
  }) {
    if (_revision != revision) {
      _revision = revision;
      _loaded.clear();
      _pending.clear();
    }
    if (_loaded.contains(kind)) return Future.value();
    final existing = _pending[kind];
    if (existing != null) return existing;

    final completer = Completer<void>();
    final pending = completer.future;
    _pending[kind] = pending;
    unawaited(() async {
      try {
        if (await inject() && _revision == revision) _loaded.add(kind);
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (_revision == revision && identical(_pending[kind], pending)) {
          unawaited(_pending.remove(kind));
        }
      }
    }());
    return pending;
  }
}

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
    'preview': ['pdf.worker.min.js', 'pdf.min.js', 'pdf-cmaps.json'],
    'preview-office': ['jszip.min.js'],
    'office': ['jszip.min.js'],
  };

  static final Map<String, Future<String>> _cache = {};

  /// A WebView may report script execution success even when JavaScript
  /// throws. Return an explicit acknowledgement and undo partial Blob URLs.
  static String acknowledgedInjectionScript(String kind, String script) {
    final ready = switch (kind) {
      'pdf' => 'window.__MBG_QPDF_WORKER_URL && window.__MBG_QPDF_MODULE_URL && window.__MBG_QPDF_WASM_URL',
      'preview' => 'window.pdfjsLib && window.__MBG_PDF_WORKER_URL',
      'preview-office' => 'window.JSZip',
      'office' => 'window.JSZip',
      _ => 'false',
    };
    final callback = switch (kind) {
      'preview' => '__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED',
      'preview-office' => '__MBG_UPLOAD_PREVIEW_OFFICE_LIBRARY_LOADED',
      _ => '__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED',
    };
    final marker = jsonEncode('__MBG_UPLOAD_LIBRARY_READY_$kind');
    final afterReady = kind == 'preview-office'
        ? 'if (window.$callback) window.$callback(${jsonEncode(kind)});'
        : '';
    return '''
(function() {
  var keys = ['__MBG_QPDF_WORKER_URL', '__MBG_QPDF_MODULE_URL', '__MBG_QPDF_WASM_URL', '__MBG_PDF_WORKER_URL'];
  var before = keys.map(function(key) { return window[key]; });
  var markerBefore = window[$marker];
  try {
    if (window[$marker] && ($ready)) {
      if (window.$callback) window.$callback(${jsonEncode(kind)});
      return 'mbg-ready';
    }
    $script
    if (!($ready)) throw new Error('library unavailable');
    window[$marker] = true;
    $afterReady
    return 'mbg-ready';
  } catch (_) {
    if (markerBefore === undefined) delete window[$marker]; else window[$marker] = markerBefore;
    keys.forEach(function(key, index) {
      try {
        if (window[key] && window[key] !== before[index]) URL.revokeObjectURL(window[key]);
        if (before[index] === undefined) delete window[key]; else window[key] = before[index];
      } catch (_) {}
    });
    try { if (window.$callback) window.$callback(${jsonEncode(kind)}); } catch (_) {}
    return 'mbg-failed';
  }
})()
''';
  }

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
      if (sources.length >= 3) {
        buffer.writeln(
          'window.__MBG_PDF_CMAPS = ${jsonEncode(jsonDecode(sources[2]))};',
        );
      }
    }
    for (final source
        in kind == 'pdf'
            ? <String>[]
            : kind == 'preview'
            ? sources.skip(1).take(1)
            : sources) {
      buffer
        ..writeln('(function(define, module, exports) {')
        ..writeln(source)
        ..writeln('}).call(window);');
    }
    final callback = switch (kind) {
      'preview' => '__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED',
      'preview-office' => '__MBG_UPLOAD_PREVIEW_OFFICE_LIBRARY_LOADED',
      _ => '__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED',
    };
    if (kind != 'preview-office') {
      buffer.writeln(
        'if (window.$callback) {'
        ' window.$callback(${jsonEncode(kind)});'
        ' }',
      );
    }
    return buffer.toString();
  }
}
