// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/upload_library_callback/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoUploadLibraryCallbackJs(Map<String, Object?> config) =>
    _gakujoUploadLibraryCallbackJsPrefix +
    jsonEncode(config) +
    _gakujoUploadLibraryCallbackJsSuffix;

const String _gakujoUploadLibraryCallbackJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/upload_library_callback/main.ts
  var callback = window[__mbgConfig.callback];
  if (callback) {
    window[__mbgConfig.callback](__mbgConfig.kind);
  }
})();
})(''';
const String _gakujoUploadLibraryCallbackJsSuffix = r''');
''';
