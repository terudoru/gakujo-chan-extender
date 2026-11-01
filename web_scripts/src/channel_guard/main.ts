export {};

declare const __mbgConfig: { mappings: Record<string, string>; capability: string };

function channelGuard() {
  if (window !== window.top) return;
  const mappings = __mbgConfig.mappings;
  const capability = __mbgConfig.capability;
  Object.keys(mappings).forEach(function(name) {
    const nativeChannel = (window as unknown as Record<string, { postMessage: (message: string) => void }>)[mappings[name]];
    if (!nativeChannel || !nativeChannel.postMessage) return;
    Object.defineProperty(window, name, {
      configurable: true,
      value: Object.freeze({postMessage: function(message: unknown) {
        nativeChannel.postMessage(JSON.stringify([capability, String(message)]));
      }})
    });
  });
}
channelGuard();
