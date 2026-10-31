import 'dart:convert';

import 'generated/message_star.g.dart';
import 'generated/message_star_open.g.dart';
import 'generated/message_star_teardown.g.dart';

class GakujoMessageStarScript {
  const GakujoMessageStarScript._();

  static const channelName = 'GakujoMessageStars';

  static String build({Iterable<String> starredIds = const []}) =>
      gakujoMessageStarJs({'initialIds': starredIds.toList()});

  static String buildRefresh(Iterable<String> starredIds) =>
      'if (window.__MBG_MESSAGE_STARS_REFRESH) {'
      'window.__MBG_MESSAGE_STARS_REFRESH(${jsonEncode(starredIds.toList())});'
      '}';

  static String buildTeardown() => gakujoMessageStarTeardownJs;

  static String buildOpen({
    required String keijitype,
    required String genrecd,
    required String seqNo,
  }) =>
      gakujoMessageStarOpenJs({
        'message': {
          'keijitype': keijitype,
          'genrecd': genrecd,
          'seqNo': seqNo,
        },
      });

}
