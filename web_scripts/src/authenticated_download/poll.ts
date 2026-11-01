export {};

declare const __mbgConfig: { requestId: string };

function authenticatedDownloadPoll() {
  const results = window.__MBG_AUTHENTICATED_DOWNLOAD_RESULTS;
  const entry = results && results[__mbgConfig.requestId];
  if (!entry) return 'null';
  if (entry.state !== 'pending') return JSON.stringify(entry);
  if (entry.chunks!.length > 0) {
    const chunk = entry.chunks!.shift();
    if (entry.resume) entry.resume();
    return JSON.stringify(chunk);
  }
  if (entry.completion) return JSON.stringify({ state: 'done', payload: entry.completion });
  return JSON.stringify({ state: 'pending' });
}
__mbgEntryResult = authenticatedDownloadPoll();
