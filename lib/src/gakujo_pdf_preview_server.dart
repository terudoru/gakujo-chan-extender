import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'generated/popup_relay.g.dart';

/// Serves only bundled viewer resources. PDF bytes never pass through HTTP.
class GakujoPdfPreviewServer {
  GakujoPdfPreviewServer({
    AssetBundle? bundle,
    Future<void> Function(String)? writeClipboard,
    Future<bool> Function(Uri)? openExternalLink,
  }) : _bundle = bundle ?? rootBundle,
       _writeClipboard =
           writeClipboard ??
           ((text) => Clipboard.setData(ClipboardData(text: text))),
       _openExternalLink =
           openExternalLink ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  final AssetBundle _bundle;
  final Future<void> Function(String) _writeClipboard;
  final Future<bool> Function(Uri) _openExternalLink;
  HttpServer? _server;
  Future<Uri>? _starting;
  bool _closed = false;
  late final String _token = _newToken();

  static String _newToken() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  // This allowlist intentionally cannot name files outside the viewer bundle.
  static const _resources = <String>{
    'index.html',
    'orientation.js',
    'flutter_bootstrap.js',
    'popup_relay.js',
    'main.dart.js',
    'canvaskit/canvaskit.js',
    'canvaskit/canvaskit.wasm',
    'canvaskit/chromium/canvaskit.js',
    'canvaskit/chromium/canvaskit.wasm',
    'canvaskit/webparagraph/canvaskit.js',
    'canvaskit/webparagraph/canvaskit.wasm',
    'assets/AssetManifest.bin',
    'assets/FontManifest.json',
    'assets/NOTICES',
    'assets/fonts/fallback/Roboto-Regular.ttf',
    'assets/fonts/MaterialIcons-Regular.otf',
    'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
    'assets/packages/material_ui/shaders/ink_sparkle.frag',
    'assets/packages/pdfrx/assets/pdfium_client.js',
    'assets/packages/pdfrx/assets/pdfium_worker.js',
    'assets/packages/pdfrx/assets/pdfium.wasm',
    'assets/shaders/ink_sparkle.frag',
    'assets/shaders/stretch_effect.frag',
    'assets/assets/NotoSansCJK-Regular.ttc',
    'assets/assets/MBGPreviewUI.otf',
    'assets/assets/unifont.otf',
  };

  Future<Uri> start() {
    final pending = _starting;
    if (pending != null) return pending;
    late final Future<Uri> starting;
    starting = _start().onError((Object error, StackTrace stackTrace) {
      if (identical(_starting, starting)) _starting = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    return _starting = starting;
  }

  Future<Uri> _start() async {
    if (_closed) throw StateError('PDF preview server is closed');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      throw StateError('PDF preview server is closed');
    }
    // Dart's default SAMEORIGIN header would block this intentionally
    // sandboxed, cross-origin iframe. The random capability still gates every
    // static resource, and the server never serves document data.
    server.defaultResponseHeaders.removeAll('x-frame-options');
    _server = server;
    server.listen((request) => unawaited(_serve(request)), onError: (_) {});
    return Uri.parse('http://127.0.0.1:${server.port}/$_token/index.html');
  }

  bool isViewerUrl(String url) {
    final server = _server;
    if (server == null) return false;
    return url == 'http://127.0.0.1:${server.port}/$_token/index.html';
  }

  Future<void> close() async {
    _closed = true;
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final server = _server;
      final segments = request.uri.pathSegments;
      final name = segments.skip(1).join('/');
      if (server == null ||
          request.headers.value(HttpHeaders.hostHeader) !=
              '127.0.0.1:${server.port}' ||
          request.uri.hasQuery ||
          segments.isEmpty ||
          segments.first != _token) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if ((name == 'clipboard' || name == 'open-link') &&
          request.method == 'POST') {
        await _handleViewerAction(request, name);
        return;
      }
      if ((request.method != 'GET' && request.method != 'HEAD') ||
          !_resources.contains(name)) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      List<int> data;
      if (name == 'popup_relay.js') {
        data = utf8.encode(_popupRelay);
      } else {
        final asset = name.startsWith('assets/assets/')
            ? 'tools/pdf_preview/${name.substring('assets/'.length)}'
            : 'assets/pdf_preview/web/$name';
        final bytes = await _bundle.load(asset);
        data = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
      }
      if (name == 'index.html') {
        final html = utf8.decode(data);
        const base = '<base href="/">';
        const bootstrap = '<script src="flutter_bootstrap.js"';
        if (!html.contains(base) || !html.contains(bootstrap)) {
          throw StateError('Invalid viewer entry point');
        }
        data = utf8.encode(
          html
              .replaceFirst(base, '<base href="/$_token/">')
              .replaceFirst(
                bootstrap,
                '<script src="popup_relay.js"></script><script src="flutter_bootstrap.js"',
              ),
        );
      }
      final origin = 'http://127.0.0.1:${server.port}';
      response.headers
        ..set(HttpHeaders.contentTypeHeader, _contentType(name))
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff')
        ..set('Access-Control-Allow-Origin', '*')
        ..set(
          'Content-Security-Policy',
          "default-src 'none'; script-src 'wasm-unsafe-eval' blob: $origin; "
              "style-src 'unsafe-inline' $origin; img-src blob: data: $origin; "
              "font-src blob: data: $origin; connect-src blob: $origin; "
              "worker-src blob:; frame-src $origin; form-action 'none'; base-uri $origin",
        );
      response.contentLength = data.length;
      if (request.method == 'GET') response.add(data);
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      try {
        await response.close();
      } catch (_) {
        // The viewer may be closed while an asset is still being delivered.
      }
    }
  }

  Future<void> _handleViewerAction(HttpRequest request, String action) async {
    final response = request.response;
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');
    // A sandboxed iframe has an opaque origin; Apple popups use our origin.
    final origin = request.headers.value('origin');
    final viewerOrigin = 'http://127.0.0.1:${_server!.port}';
    if ((origin != 'null' && origin != viewerOrigin) ||
        request.headers.contentType?.mimeType != 'text/plain') {
      response.statusCode = HttpStatus.forbidden;
      return;
    }
    final maxBytes = action == 'clipboard' ? 16 * 1024 * 1024 : 8192;
    if (request.contentLength > maxBytes) {
      response.statusCode = HttpStatus.requestEntityTooLarge;
      return;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request.timeout(const Duration(seconds: 10))) {
      if (bytes.length + chunk.length > maxBytes) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
      bytes.add(chunk);
    }
    final text = utf8.decode(bytes.takeBytes());
    if (text.isEmpty || text.length > 4000000 || _closed) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    if (action == 'clipboard') {
      await _writeClipboard(text);
    } else {
      final url = Uri.tryParse(text);
      if (url == null ||
          (url.scheme != 'https' && url.scheme != 'http') ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          text.contains(RegExp(r'[\x00-\x20\x7f\\]'))) {
        response.statusCode = HttpStatus.badRequest;
        return;
      }
      if (!await _openExternalLink(url)) {
        response.statusCode = HttpStatus.serviceUnavailable;
        return;
      }
    }
    response.statusCode = HttpStatus.noContent;
  }

  // The isolated viewer expects its PDF from its parent frame. A macOS
  // top-level popup relays only messages from its opener into itself; no PDF
  // bytes are served over HTTP or written to disk.
  static const _popupRelay = gakujoPopupRelayJs;

  static String _contentType(String name) {
    if (name.endsWith('.html')) return 'text/html; charset=utf-8';
    if (name.endsWith('.js')) return 'application/javascript; charset=utf-8';
    if (name.endsWith('.json')) return 'application/json';
    if (name.endsWith('.wasm')) return 'application/wasm';
    if (name.endsWith('.ttf')) return 'font/ttf';
    if (name.endsWith('.otf')) return 'font/otf';
    if (name.endsWith('.ttc')) return 'font/collection';
    return 'application/octet-stream';
  }
}
