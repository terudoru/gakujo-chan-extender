import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

void main() {
  test('request timeout scales with the request body', () {
    expect(starSyncRequestTimeoutFor(0), const Duration(seconds: 20));
    expect(starSyncRequestTimeoutFor(32767), const Duration(seconds: 20));
    expect(starSyncRequestTimeoutFor(32768), const Duration(seconds: 21));
    expect(
      starSyncRequestTimeoutFor(8 * 1024 * 1024),
      const Duration(seconds: 276),
    );
  });

  test('timeout aborts the connection', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final ended = Completer<void>();
    server.listen((socket) {
      socket.listen(
        (_) {},
        onDone: () {
          socket.destroy();
          if (!ended.isCompleted) ended.complete();
        },
      );
    });
    final client = HttpClient();
    try {
      await expectLater(
        starSyncRequest(
          client,
          'POST',
          Uri.parse('http://127.0.0.1:${server.port}/'),
          body: [1],
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<StarSyncTransportException>().having(
            (error) => error.kind,
            'kind',
            StarSyncTransportErrorKind.network,
          ),
        ),
      );
      await ended.future.timeout(const Duration(seconds: 2));
    } finally {
      client.close(force: true);
      await server.close();
    }
  });
}
