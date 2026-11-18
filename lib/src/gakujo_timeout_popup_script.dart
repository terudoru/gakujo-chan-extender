import 'gakujo_login_observer_script.dart';
import 'generated/timeout_popup.g.dart';

class GakujoTimeoutPopupScript {
  const GakujoTimeoutPopupScript._();

  static String build() {
    return gakujoTimeoutPopupJs;
  }

  static String buildWithLoginObserver() =>
      '''
try {
  (function() {
${build()}
  })();
} finally {
${GakujoLoginObserverScript.build()}
}
''';
}
