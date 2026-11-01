import 'generated/message_filter.g.dart';
import 'generated/message_filter_teardown.g.dart';
import 'gakujo_app_settings.dart';

class GakujoMessageFilterScript {
  const GakujoMessageFilterScript._();

  static String buildTeardown() => gakujoMessageFilterTeardownJs;

  static String build({required List<String> keywords}) {
    return gakujoMessageFilterJs({
      'keywords': normalizeMessageExcludeKeywords(keywords),
    });
  }
}
