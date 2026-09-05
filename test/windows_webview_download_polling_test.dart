import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:test/test.dart';

void main() {
  Matcher failure(String code) =>
      isA<PlatformException>().having((error) => error.code, 'code', code);

  test('returns the completed payload after pending states', () async {
    final states = [
      '{"state":"pending"}',
      '{"state":"done","payload":{"status":200,"ok":true,"bodyByteLength":0,"chunkCount":0}}',
    ];
    final result = await pollWindowsWebViewDownloadResult(
      readState: () async => states.removeAt(0),
      pollInterval: Duration.zero,
    );
    expect(result, {
      'status': 200,
      'ok': true,
      'bodyByteLength': 0,
      'chunkCount': 0,
      'bodyBytes': isEmpty
    });
  });

  test('assembles chunks in order and checks the declared byte count',
      () async {
    final states = [
      '{"state":"chunk","index":0,"bodyBase64":"AQID"}',
      '{"state":"chunk","index":1,"bodyBase64":"BAU="}',
      '{"state":"done","payload":{"bodyByteLength":5,"chunkCount":2}}',
    ];
    final result = await pollWindowsWebViewDownloadResult(
        readState: () async => states.removeAt(0));
    expect(result['bodyBytes'], [1, 2, 3, 4, 5]);
  });

  test('waits for the receiver before requesting another chunk', () async {
    final receiverStarted = Completer<void>();
    final receiverFinished = Completer<void>();
    var calls = 0;
    final receiving = pollWindowsWebViewDownloadResult(
      readState: () async => calls++ == 0
          ? '{"state":"chunk","index":0,"bodyBase64":"AQID"}'
          : '{"state":"done","payload":{"bodyByteLength":3,"chunkCount":1}}',
      onChunk: (bytes) async {
        receiverStarted.complete();
        await receiverFinished.future;
      },
    );
    await receiverStarted.future;
    expect(calls, 1);
    receiverFinished.complete();
    final result = await receiving;
    expect(result.containsKey('bodyBytes'), isFalse);
  });

  for (final chunk in [
    {'state': 'chunk', 'index': 1, 'bodyBase64': 'AQID'},
    {'state': 'chunk', 'index': 0, 'bodyBase64': ''},
    {'state': 'chunk', 'index': 0, 'bodyBase64': '!invalid!'},
    {'state': 'chunk', 'index': 0, 'bodyBase64': 'A' * 349532},
  ]) {
    test(
        'rejects malformed or oversized chunks (${chunk['index']}, ${(chunk['bodyBase64'] as String).length})',
        () async {
      await expectLater(
          pollWindowsWebViewDownloadResult(
            readState: () async => jsonEncode(chunk),
          ),
          throwsFormatException);
    });
  }

  test('stops immediately when navigation has discarded the result store',
      () async {
    var calls = 0;
    await expectLater(
      pollWindowsWebViewDownloadResult(
        readState: () async {
          calls += 1;
          return 'null';
        },
        timeout: const Duration(milliseconds: 30),
        pollInterval: const Duration(milliseconds: 1),
      ),
      throwsA(failure('download_interrupted')),
    );
    expect(calls, 1);
  });

  test('bounds a JavaScript bridge call that never returns', () async {
    await expectLater(
      pollWindowsWebViewDownloadResult(
        readState: () => Completer<String>().future,
        timeout: const Duration(milliseconds: 30),
      ).timeout(const Duration(seconds: 1)),
      throwsA(failure('download_timeout')),
    );
  });

  test('times out a download that remains pending', () async {
    await expectLater(
      pollWindowsWebViewDownloadResult(
        readState: () async => '{"state":"pending"}',
        timeout: const Duration(milliseconds: 30),
        pollInterval: const Duration(milliseconds: 1),
      ),
      throwsA(failure('download_timeout')),
    );
  });

  test('reports a fetch failure without further polling', () async {
    await expectLater(
      pollWindowsWebViewDownloadResult(
        readState: () async =>
            jsonEncode({'state': 'error', 'message': 'offline'}),
      ),
      throwsA(failure('download_failed')),
    );
  });

  test('rejects malformed completion payloads', () async {
    await expectLater(
      pollWindowsWebViewDownloadResult(
        readState: () async => '{"state":"done","payload":null}',
      ),
      throwsFormatException,
    );
  });
}
