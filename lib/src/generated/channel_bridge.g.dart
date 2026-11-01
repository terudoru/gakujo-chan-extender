// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/channel_bridge/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoChannelBridgeJs(Map<String, Object?> config) =>
    _gakujoChannelBridgeJsPrefix +
    jsonEncode(config) +
    _gakujoChannelBridgeJsSuffix;

const String _gakujoChannelBridgeJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/channel_bridge/main.ts
  function channelBridge() {
    var channelName = __mbgConfig.channelName;
    window[channelName] = {
      postMessage: function(message) {
        window.chrome.webview.postMessage(JSON.stringify({
          channel: channelName,
          message: String(message)
        }));
      }
    };
  }
  channelBridge();
})();
})(''';
const String _gakujoChannelBridgeJsSuffix = r''');
''';
