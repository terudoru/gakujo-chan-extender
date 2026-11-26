import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class PreviewTestAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key != 'assets/pdf_preview/web/index.html') {
      throw StateError('Unexpected asset: $key');
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

Future<({int status, String body})> sendPreviewRequest(
  HttpClient client,
  Uri url, {
  String method = 'POST',
  String? origin = 'null',
  String? contentType = 'text/plain; charset=utf-8',
  String? host,
  List<int>? bodyBytes,
}) async {
  final request = await client.openUrl(method, url);
  request.persistentConnection = false;
  if (host != null) {
    request.headers.set(HttpHeaders.hostHeader, host);
  }
  if (origin != null) {
    request.headers.set('origin', origin);
  }
  if (contentType != null) {
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
  }
  if (bodyBytes != null) {
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
  } else if (method == 'POST') {
    request.contentLength = 0;
  }
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  return (status: response.statusCode, body: responseBody);
}
