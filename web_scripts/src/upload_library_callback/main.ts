declare const __mbgConfig: {callback: '__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED' | '__MBG_UPLOAD_PREVIEW_OFFICE_LIBRARY_LOADED' | '__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED'; kind: string};
const callback = window[__mbgConfig.callback] as ((kind: string) => void) | undefined;
if (callback) {
  window[__mbgConfig.callback]!(__mbgConfig.kind);
}
export {};
