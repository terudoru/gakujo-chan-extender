import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_s3_transport.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

void main() {
  StarSyncS3Config config(Uri endpoint, {bool pathStyle = true}) =>
      StarSyncS3Config(
        endpoint: endpoint,
        region: 'us-east-1',
        bucket: 'examplebucket',
        prefix: '',
        accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        pathStyle: pathStyle,
      );
  test('S3 URL styles and segment encoding', () {
    final endpoint = Uri.parse('https://s3.amazonaws.com');
    expect(
      buildStarSyncS3Url(config(endpoint), key: 'a b/x+y').toString(),
      'https://s3.amazonaws.com/examplebucket/a%20b/x%2By',
    );
    expect(
      buildStarSyncS3Url(
        config(endpoint, pathStyle: false),
        key: 'test.txt',
      ).toString(),
      'https://examplebucket.s3.amazonaws.com/test.txt',
    );
  });
  test('AWS S3 GET Object signature vector', () {
    final headers = signStarSyncS3Request(
      method: 'GET',
      uri: Uri.parse('https://examplebucket.s3.amazonaws.com/test.txt'),
      region: 'us-east-1',
      accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
      secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      time: DateTime.utc(2013, 5, 24),
      headers: {'range': 'bytes=0-9'},
    );
    expect(
      headers['authorization'],
      endsWith(
        'Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
      ),
    );
  });
  test('S3 pagination, missing objects, conditional writes and signed headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    final subscription = server.listen((request) async {
      requests.add('${request.method} ${request.uri}');
      expect(
        request.headers.value('authorization'),
        startsWith('AWS4-HMAC-SHA256 Credential='),
      );
      expect(
        request.headers.value('x-amz-date'),
        matches(RegExp(r'^\d{8}T\d{6}Z$')),
      );
      expect(
        request.headers.value('x-amz-content-sha256'),
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      if (request.uri.queryParameters['list-type'] == '2') {
        final second = request.uri.queryParameters.containsKey(
          'continuation-token',
        );
        request.response.write(
          '<ListBucketResult><IsTruncated>${!second}</IsTruncated><Contents><Key>stars/${second ? 'two' : 'one'}</Key><ETag>&quot;tag&quot;</ETag><Size>2</Size></Contents>${second ? '' : '<NextContinuationToken>a+b</NextContinuationToken>'}</ListBucketResult>',
        );
      } else if (request.method == 'PUT') {
        expect(request.headers.value('if-none-match'), '*');
        request.response.statusCode = 412;
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final transport = StarSyncS3Transport(
      config(Uri.parse('http://127.0.0.1:${server.port}')),
      now: () => DateTime.utc(2013, 5, 24),
    );
    try {
      final entries = await transport.list('stars');
      expect(entries.map((e) => e.path), ['stars/one', 'stars/two']);
      expect(entries.first.etag, 'tag');
      expect(requests[1], contains('continuation-token=a%2Bb'));
      expect(await transport.get('stars/missing'), isNull);
      await expectLater(
        transport.put('stars/item', [1], createOnly: true),
        throwsA(
          isA<StarSyncTransportException>().having(
            (e) => e.kind,
            'kind',
            StarSyncTransportErrorKind.alreadyExists,
          ),
        ),
      );
      await transport.delete('stars/missing');
    } finally {
      transport.close();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
