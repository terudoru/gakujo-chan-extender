import 'dart:convert';

import 'download_response_policy.dart';
import 'gakujo_download_request.dart';

class WindowsWebViewAuthenticatedDownloadScript {
  const WindowsWebViewAuthenticatedDownloadScript._();

  static const _resultStore = '__MBG_AUTHENTICATED_DOWNLOAD_RESULTS';

  static String start({
    required String requestId,
    required GakujoDownloadRequest request,
  }) {
    return '''
(function() {
  // The native caller can race a navigation; reject the receiving document
  // before constructing request fields or invoking page-controlled APIs.
  if (location.origin !== 'https://gakujo.iess.niigata-u.ac.jp') {
    return false;
  }
  const requestId = ${jsonEncode(requestId)};
  const results = window.$_resultStore =
    window.$_resultStore || Object.create(null);
  if (Object.prototype.hasOwnProperty.call(results, requestId)) {
    return false;
  }
  const controller = new AbortController();
  const pending = { state: 'pending', chunks: [], resume: null, completion: null };
  pending.cancel = () => {
    controller.abort();
    if (pending.resume) pending.resume();
  };
  results[requestId] = pending;
  const setResult = function(value) {
    if (results[requestId] === pending) {
      results[requestId] = value;
    }
  };
  (async function() {
    try {
      const inputUrl = ${jsonEncode(request.url)};
      const method = ${jsonEncode(request.method.toUpperCase() == 'POST' ? 'POST' : 'GET')};
      const fields = ${jsonEncode(request.formFields)};
      const url = new URL(inputUrl, window.location.href);
      const options = {
        method,
        credentials: 'include',
        // Fetch cannot expose each redirect destination before following it.
        // Refuse redirects rather than forwarding authenticated POST data.
        redirect: 'error',
        signal: controller.signal
      };
      if (method === 'GET') {
        Object.keys(fields || {}).forEach(function(key) {
          url.searchParams.set(key, String(fields[key]));
        });
      } else {
        const body = new URLSearchParams();
        Object.keys(fields || {}).forEach(function(key) {
          body.append(key, String(fields[key]));
        });
        options.body = body.toString();
        options.headers = {
          'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'
        };
      }
      const response = await fetch(url.toString(), options);
      const finalUrl = new URL(response.url);
      const isAllowedFinalUrl =
        finalUrl.protocol === 'https:' &&
        finalUrl.hostname === 'gakujo.iess.niigata-u.ac.jp' &&
        (finalUrl.port === '' || finalUrl.port === '443') &&
        finalUrl.username === '' &&
        finalUrl.password === '';
      if (!isAllowedFinalUrl) {
        controller.abort();
        setResult({
          state: 'done',
          payload: {
            blocked: true,
            finalUrl: response.url,
            status: response.status
          }
        });
        return;
      }
      const metadata = {
        status: response.status,
        ok: response.ok,
        finalUrl: response.url,
        mimeType: response.headers.get('content-type') || '',
        contentDisposition: response.headers.get('content-disposition') || ''
      };
      if (!response.ok) {
        controller.abort();
        setResult({ state: 'done', payload: metadata });
        return;
      }
      const requestedName = ${jsonEncode(request.fileName)};
      const parameters = Object.create(null);
      const parameter = /(?:^|;)\\s*([^=;\\s]+)\\s*=\\s*(?:"((?:\\\\.|[^"\\\\])*)"|([^;]*))/g;
      for (const match of metadata.contentDisposition.matchAll(parameter)) {
        const key = match[1].toLowerCase();
        if (!(key in parameters)) {
          parameters[key] = match[2] === undefined ? match[3].trim() :
            match[2].replace(/\\\\(.)/g, '\$1');
        }
      }
      let dispositionName = parameters['filename'] || '';
      const extended = /^([^']*)'[^']*'(.+)\$/.exec(parameters['filename*'] || '');
      if (extended) {
        dispositionName = extended[2].replace(/%([0-9a-f]{2})/gi,
          (_, hex) => String.fromCharCode(parseInt(hex, 16)));
      }
      const type = metadata.mimeType.split(';')[0].trim().toLowerCase();
      const checkPage = !/\\.html?\$/i.test(requestedName.trim()) &&
        !/\\.html?\$/i.test(dispositionName.trim()) &&
        !/\\.html?\$/i.test(url.pathname) &&
        !(type.startsWith('text/') && type !== 'text/html');
      const chunkSize = 256 * 1024;
      let chunkIndex = 0;
      let totalBytes = 0;
      async function emitChunk(bytes) {
        if (totalBytes + bytes.length > $maxGakujoDownloadBytes) {
          throw Object.assign(new Error('ダウンロードが大きすぎます'), { code: 'download_too_large' });
        }
        if (chunkIndex === 0 && checkPage &&
            /^(?:\\xEF\\xBB\\xBF)?[\\x09-\\x0D\\x20]*(?:<!doctype html|<html)[\\x09-\\x0D\\x20/>]/i.test(
              String.fromCharCode.apply(null, bytes.subarray(0, 1024)))) {
          throw Object.assign(new Error(${jsonEncode(DownloadResponsePolicy.pageReturnedMessage)}),
            { code: 'page_response' });
        }
        while (pending.chunks.length >= 4 && !controller.signal.aborted) {
          await new Promise(resolve => { pending.resume = resolve; });
          pending.resume = null;
        }
        if (controller.signal.aborted || results[requestId] !== pending) {
          throw new Error('Download cancelled');
        }
        let binary = '';
        for (let index = 0; index < bytes.length; index += 0x8000) {
          binary += String.fromCharCode.apply(null, bytes.subarray(index, index + 0x8000));
        }
        pending.chunks.push({ state: 'chunk', index: chunkIndex++, bodyBase64: btoa(binary) });
        totalBytes += bytes.length;
      }
      if (response.body) {
        const reader = response.body.getReader();
        try {
          let chunk = new Uint8Array(chunkSize);
          let used = 0;
          while (true) {
            const result = await reader.read();
            if (result.done) break;
            const bytes = result.value;
            let offset = 0;
            while (offset < bytes.length) {
              const count = Math.min(chunkSize - used, bytes.length - offset);
              chunk.set(bytes.subarray(offset, offset + count), used);
              used += count;
              offset += count;
              if (used === chunkSize) {
                await emitChunk(chunk);
                chunk = new Uint8Array(chunkSize);
                used = 0;
              }
            }
          }
          if (used > 0) await emitChunk(chunk.subarray(0, used));
        } finally {
          reader.releaseLock();
        }
      }
      pending.completion = { ...metadata, bodyByteLength: totalBytes, chunkCount: chunkIndex };
    } catch (error) {
      controller.abort();
      setResult({
        state: 'error',
        code: error && error.code || '',
        errorName: error && error.name || '',
        message: String(error && error.message || error || '')
      });
    }
  })();
  return true;
})()
''';
  }

  static String poll(String requestId) {
    return '''
(function() {
  const results = window.$_resultStore;
  const entry = results && results[${jsonEncode(requestId)}];
  if (!entry) return 'null';
  if (entry.state !== 'pending') return JSON.stringify(entry);
  if (entry.chunks.length > 0) {
    const chunk = entry.chunks.shift();
    if (entry.resume) entry.resume();
    return JSON.stringify(chunk);
  }
  if (entry.completion) return JSON.stringify({ state: 'done', payload: entry.completion });
  return JSON.stringify({ state: 'pending' });
})()
''';
  }

  static String cleanup(String requestId) {
    return '''
(function() {
  const results = window.$_resultStore;
  if (results) {
    const requestId = ${jsonEncode(requestId)};
    const entry = results[requestId];
    delete results[requestId];
    if (entry && typeof entry.cancel === 'function') {
      entry.cancel();
    }
  }
  return true;
})()
''';
  }
}
