// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/channel_guard/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoChannelGuardJs(Map<String, Object?> config) =>
    _gakujoChannelGuardJsPrefix +
    jsonEncode(config) +
    _gakujoChannelGuardJsSuffix;

const String _gakujoChannelGuardJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/channel_guard/main.ts
  function channelGuard() {
    if (window !== window.top) return;
    const mappings = __mbgConfig.mappings;
    const capability = __mbgConfig.capability;
    Object.keys(mappings).forEach(function(name) {
      const nativeChannel = window[mappings[name]];
      if (!nativeChannel || !nativeChannel.postMessage) return;
      Object.defineProperty(window, name, {
        configurable: true,
        value: Object.freeze({ postMessage: function(message) {
          nativeChannel.postMessage(JSON.stringify([capability, String(message)]));
        } })
      });
    });
  }
  channelGuard();
})();
})(''';
const String _gakujoChannelGuardJsSuffix = r''');
''';
