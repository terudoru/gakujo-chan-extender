export {};

declare const __mbgConfig: { channelName: string };

function channelBridge() {
  var channelName = __mbgConfig.channelName;
  (window as unknown as Record<string, unknown>)[channelName] = {
    postMessage: function(message: unknown) {
      window.chrome.webview.postMessage(JSON.stringify({
        channel: channelName,
        message: String(message)
      }));
    }
  };
}
channelBridge();
