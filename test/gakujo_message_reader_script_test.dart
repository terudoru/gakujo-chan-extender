import 'package:morebettergakujo_flutter/src/gakujo_message_reader_script.dart';
import 'package:test/test.dart';

import 'support/page_script_dom_harness.dart';

void main() {
  test('builds bulk message read controls', () {
    final script = GakujoMessageReaderScript.build();

    expect(script, contains('__MBG_MESSAGE_READER_VERSION'));
    expect(script, contains("document.getElementById('main-frame-if')"));
    expect(script, contains('|| document'));
    expect(script, contains("doc.querySelector('table.normal:nth-child(9)')"));
    expect(script, contains('指定した個数を既読にする'));
    expect(script, contains('既読にする数(半角数字)'));
    expect(script, contains("fetch(url, { credentials: 'include' })"));
    expect(script, contains('if (response.ok)'));
    expect(script, contains('markReadWithFrame(url)'));
    expect(script, contains('location.reload()'));
  });

  test('matches original extension by reading the first requested rows', () {
    final script = GakujoMessageReaderScript.build();

    expect(
      script,
      contains('for (var i = 1; i < table.rows.length && urls.length < limit'),
    );
    expect(
      script,
      contains("var link = table.rows[i].querySelector('a[href]')"),
    );
    expect(script, isNot(contains('classList')));
    expect(script, isNot(contains('fontWeight')));
  });

  test('reloads after all requested messages are marked read', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 200, 200],
    );

    expect(result['fetchCallCount'], 3);
    expect(result['frameCallCount'], 0);
    expect(result['statusText'], '3件を既読にしました（失敗0件）');
    expect(result['reloadCount'], 1);
  });

  test('reports a failed fallback and does not reload', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200, 403],
      iframeOutcomes: [false],
    );

    expect(result['fetchCallCount'], 2);
    expect(result['frameCallCount'], 1);
    expect(result['statusText'], '1件を既読にしました（失敗1件）');
    expect(result['reloadCount'], 0);
  });

  test('owns the visible result status for teardown', () async {
    final result = await evaluateMessageReaderScript(
      buildScript: GakujoMessageReaderScript.build(),
      fetchStatuses: [200],
    );

    expect(result['statusOwned'], 'true');
    expect(result['controlIds'], contains('mbg-read-status'));
  });

  test('teardown stops polling, removes controls, and is idempotent', () async {
    final result = await evaluatePageScriptLifecycle(
      feature: 'message',
      buildScript: GakujoMessageReaderScript.build(),
      teardownScript: GakujoMessageReaderScript.buildTeardown(),
    );
    final afterBuild = result['afterBuild'] as Map<String, dynamic>;
    final afterTeardown = result['afterTeardown'] as Map<String, dynamic>;
    final afterRebuild = result['afterRebuild'] as Map<String, dynamic>;
    final teardownWithoutBuild =
        result['teardownWithoutBuild'] as Map<String, dynamic>;

    expect(afterBuild['activeIntervalCount'], 1);
    expect(afterBuild['ownedElementCount'], 3);
    expect(afterBuild['controlIds'], [
      'mbg-read-button',
      'mbg-read-num-input',
      'mbg-read-status',
    ]);
    expect(afterTeardown['activeIntervalCount'], 0);
    expect(afterTeardown['ownedElementCount'], 0);
    expect(afterTeardown['controlIds'], isEmpty);
    expect(afterTeardown['globalMarkers'], isEmpty);
    expect(afterRebuild['activeIntervalCount'], 1);
    expect(afterRebuild['ownedElementCount'], 3);
    expect(teardownWithoutBuild['activeIntervalCount'], 0);
    expect(teardownWithoutBuild['ownedElementCount'], 0);
  });
}
