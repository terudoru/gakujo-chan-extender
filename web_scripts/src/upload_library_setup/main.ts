declare const __mbgConfig: {kind: string; sources: (string | Record<string, string>)[]};

function uploadLibrarySetup() {
  const {kind, sources} = __mbgConfig;
  if (kind === 'pdf' && sources.length === 3) {
    window.__MBG_QPDF_WORKER_URL = URL.createObjectURL(new Blob([sources[0] as string], {type: 'text/javascript'}));
    window.__MBG_QPDF_MODULE_URL = URL.createObjectURL(new Blob([sources[1] as string], {type: 'text/javascript'}));
    const raw = atob(sources[2] as string);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    window.__MBG_QPDF_WASM_URL = URL.createObjectURL(new Blob([bytes], {type: 'application/wasm'}));
  } else if (kind === 'preview' && sources.length > 0) {
    window.__MBG_PDF_WORKER_URL = URL.createObjectURL(new Blob([sources[0] as string], {type: 'text/javascript'}));
    if (sources.length >= 6) {
      window.__MBG_PDF_VIEWER_CSS = sources[3] as string;
      window.__MBG_PDF_CMAPS = sources[4] as Record<string, string>;
      window.__MBG_PDF_STANDARD_FONTS = sources[5] as Record<string, string>;
    }
  }
}
uploadLibrarySetup();
export {};
