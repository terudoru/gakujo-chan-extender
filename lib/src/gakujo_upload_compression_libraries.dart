import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'generated/upload_library_ack.g.dart';
import 'generated/upload_library_setup.g.dart';

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
    'preview': [
      'pdf.worker.min.js',
      'pdf.min.js',
      'pdf_viewer.js',
      'pdf_viewer.css',
      'pdf-cmaps.json',
      'pdf-standard-fonts.json',
    ],
    'preview-office': ['jszip.min.js'],
    'office': ['jszip.min.js'],
  };

  static final Map<String, Future<String>> _cache = {};

  /// A WebView may report script execution success even when JavaScript
  /// throws. Return an explicit acknowledgement and undo partial Blob URLs.
  static String acknowledgedInjectionScript(String kind, String script) {
    return '${gakujoUploadLibraryAckJs.trimRight()}'
        '(${jsonEncode(kind)}, function() {\n$script\n})';
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
    if ((kind == 'pdf' && sources.length == 3) ||
        (kind == 'preview' && sources.isNotEmpty)) {
      final setupSources = <Object?>[...sources];
      if (kind == 'preview') {
        if (setupSources.length > 1) setupSources[1] = '';
        if (setupSources.length > 2) setupSources[2] = '';
      }
      if (kind == 'preview' && sources.length >= 6) {
        setupSources[4] = jsonDecode(sources[4]);
        setupSources[5] = jsonDecode(sources[5]);
      }
      buffer.write(
        gakujoUploadLibrarySetupJs({'kind': kind, 'sources': setupSources}),
      );
    }
    for (final source
        in kind == 'pdf'
            ? <String>[]
            : kind == 'preview'
            ? sources.skip(1).take(2)
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
