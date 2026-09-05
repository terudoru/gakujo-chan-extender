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
      '{"state":"done","payload":{"status":200,"bodyBase64":"AQID"}}',
    ];
    final result = await pollWindowsWebViewDownloadResult(
      readState: () async => states.removeAt(0),
      pollInterval: Duration.zero,
    );
    expect(result, {'status': 200, 'bodyBase64': 'AQID'});
  });

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
