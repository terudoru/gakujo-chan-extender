import 'package:morebettergakujo_flutter/src/gakujo_session_extender_script.dart';
import 'package:test/test.dart';

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
}
