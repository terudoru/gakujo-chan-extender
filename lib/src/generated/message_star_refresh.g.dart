// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/message_star_refresh/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoMessageStarRefreshJs(Map<String, Object?> config) =>
    _gakujoMessageStarRefreshJsPrefix +
    jsonEncode(config) +
    _gakujoMessageStarRefreshJsSuffix;

const String _gakujoMessageStarRefreshJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/message_star_refresh/main.ts
  if (window.__MBG_MESSAGE_STARS_REFRESH) {
    window.__MBG_MESSAGE_STARS_REFRESH(__mbgConfig.ids);
  }
})();
})(''';
const String _gakujoMessageStarRefreshJsSuffix = r''');
''';
