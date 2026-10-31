import 'generated/session_extender.g.dart';
import 'generated/session_extender_teardown.g.dart';

class GakujoSessionExtenderScript {
  const GakujoSessionExtenderScript._();

  static String build() {
    return gakujoSessionExtenderJs;
  }

  static String buildTeardown() {
    return gakujoSessionExtenderTeardownJs;
  }
}
