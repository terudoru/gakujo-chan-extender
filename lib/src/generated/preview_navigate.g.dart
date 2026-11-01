// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/preview_navigate/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoPreviewNavigateJs(Map<String, Object?> config) =>
    _gakujoPreviewNavigateJsPrefix +
    jsonEncode(config) +
    _gakujoPreviewNavigateJsSuffix;

const String _gakujoPreviewNavigateJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/preview_navigate/main.ts
  __mbgEntryResult = window.__MBG_PREVIEW_NAVIGATE ? window.__MBG_PREVIEW_NAVIGATE(__mbgConfig.direction) : false;
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoPreviewNavigateJsSuffix = r''')
''';
