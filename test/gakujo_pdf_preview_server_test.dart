import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_pdf_preview_server.dart';

class _ViewerBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key != 'assets/pdf_preview/web/index.html') {
      throw StateError('Unexpected asset');
    }
    return ByteData.sublistView(
      Uint8List.fromList(
        utf8.encode(
          '<html><head><base href="/"></head><body>'
          '<script src="flutter_bootstrap.js" async></script></body></html>',
        ),
      ),
    );
  }
}

class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  test('only the capability URL can read bundled resources', () async {
    final server = GakujoPdfPreviewServer(bundle: _ViewerBundle());
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });
    final url = await server.start();
    expect(server.isViewerUrl(url.toString()), isTrue);
    expect(server.isViewerUrl('$url?x=1'), isFalse);

    final response = await (await client.getUrl(url)).close();
    final html = await utf8.decoder.bind(response).join();
    expect(response.statusCode, HttpStatus.ok);
    expect(html, contains('<base href="/${url.pathSegments.first}/">'));
    expect(html, contains('<script src="popup_relay.js"></script>'));
    expect(response.headers.value('access-control-allow-origin'), '*');
    expect(response.headers.value('cache-control'), contains('no-store'));
    expect(response.headers.value('x-frame-options'), isNull);
    expect(
      response.headers.value('content-security-policy'),
      contains("default-src 'none'"),
    );

    Future<int> status(String method, Uri target, {String? host}) async {
      final request = await client.openUrl(method, target);
      if (host != null) request.headers.set(HttpHeaders.hostHeader, host);
      final result = await request.close();
      await result.drain<void>();
      return result.statusCode;
    }

    expect(await status('POST', url), HttpStatus.notFound);
    expect(
      await status('GET', url.replace(query: 'extra=1')),
      HttpStatus.notFound,
    );
    expect(
      await status('GET', url.replace(path: '/wrong/index.html')),
      HttpStatus.notFound,
    );
    expect(
      await status(
        'GET',
        url.replace(path: '/${url.pathSegments.first}/document.pdf'),
      ),
      HttpStatus.notFound,
    );
    expect(await status('GET', url, host: 'example.org'), HttpStatus.notFound);
    expect(await status('HEAD', url), HttpStatus.ok);
    final relayUrl = url.replace(
      path: '/${url.pathSegments.first}/popup_relay.js',
    );
    final relayResponse = await (await client.getUrl(relayUrl)).close();
    final relay = await utf8.decoder.bind(relayResponse).join();
    expect(relayResponse.statusCode, HttpStatus.ok);
    expect(relay, contains('event.source === window.opener'));
    expect(relay, contains('event.data instanceof ArrayBuffer'));
  });

  test('the viewer files and fallback fonts can be served', () async {
    final server = GakujoPdfPreviewServer(bundle: _FileBundle());
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });
    final url = await server.start();
    for (final name in [
      'index.html',
      'flutter_bootstrap.js',
      'assets/packages/pdfrx/assets/pdfium.wasm',
      'assets/assets/NotoSansCJK-Regular.ttc',
      'assets/assets/MBGPreviewUI.otf',
      'assets/assets/unifont.otf',
    ]) {
      final target = url.replace(path: '/${url.pathSegments.first}/$name');
      final response = await (await client.getUrl(target)).close();
      expect(response.statusCode, HttpStatus.ok, reason: name);
      expect(response.contentLength, greaterThan(0), reason: name);
      await response.drain<void>();
    }
  });
}
