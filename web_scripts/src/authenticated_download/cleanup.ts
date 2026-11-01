export {};

declare const __mbgConfig: { requestId: string };

function authenticatedDownloadCleanup() {
  const results = window.__MBG_AUTHENTICATED_DOWNLOAD_RESULTS;
  if (results) {
    const requestId = __mbgConfig.requestId;
    const entry = results[requestId];
    delete results[requestId];
    if (entry && typeof entry.cancel === 'function') {
      entry.cancel();
    }
  }
  return true;
}
__mbgEntryResult = authenticatedDownloadCleanup();
