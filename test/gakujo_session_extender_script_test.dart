import 'package:morebettergakujo_flutter/src/gakujo_session_extender_script.dart';
import 'package:test/test.dart';

import 'support/page_script_dom_harness.dart';

void main() {
  test('builds a session extender compatible with the original extension', () {
    final script = GakujoSessionExtenderScript.build();

    expect(script, contains('__MBG_SESSION_EXTENDER_VERSION'));
    expect(script, contains("document.getElementById('timeout-timer')"));
    expect(script, contains("document.getElementById('portaltimerimg')"));
    expect(script, contains('minutes > 11'));
    expect(script, contains('__MBG_SESSION_EXTENDER_COUNT >= 10'));
    expect(script, contains('window.setInterval(extendIfNeeded, 60000)'));
  });

  test('teardown stops the interval and is safe before injection', () async {
    final result = await evaluatePageScriptLifecycle(
      feature: 'session',
      buildScript: GakujoSessionExtenderScript.build(),
      teardownScript: GakujoSessionExtenderScript.buildTeardown(),
    );
    final afterBuild = result['afterBuild'] as Map<String, dynamic>;
    final afterTeardown = result['afterTeardown'] as Map<String, dynamic>;
    final afterRebuild = result['afterRebuild'] as Map<String, dynamic>;
    final teardownWithoutBuild =
        result['teardownWithoutBuild'] as Map<String, dynamic>;

    expect(afterBuild['activeIntervalCount'], 1);
    expect(afterBuild['globalMarkers'], isNotEmpty);
    expect(afterTeardown['activeIntervalCount'], 0);
    expect(afterTeardown['globalMarkers'], isEmpty);
    expect(afterRebuild['activeIntervalCount'], 1);
    expect(teardownWithoutBuild['activeIntervalCount'], 0);
    expect(teardownWithoutBuild['globalMarkers'], isEmpty);
  });
}
