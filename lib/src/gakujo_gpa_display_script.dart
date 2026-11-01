import 'generated/gpa_display.g.dart';
import 'generated/gpa_display_teardown.g.dart';

class GakujoGpaDisplayScript {
  const GakujoGpaDisplayScript._();

  static const channelName = 'GakujoGpaReport';

  static String build() {
    return gakujoGpaDisplayJs;
  }

  static String buildTeardown() {
    return gakujoGpaDisplayTeardownJs;
  }
}
