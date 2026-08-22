import 'dart:convert';

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
  const requestId = ${jsonEncode(requestId)};
  const results = window.$_resultStore =
    window.$_resultStore || Object.create(null);
  if (Object.prototype.hasOwnProperty.call(results, requestId)) {
    return false;
  }
  results[requestId] = { state: 'pending' };
  const setResult = function(value) {
    if (results[requestId] && results[requestId].state === 'cancelled') {
      delete results[requestId];
      return;
    }
    results[requestId] = value;
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
        redirect: 'follow'
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
      const buffer = await response.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      let binary = '';
      const chunkSize = 0x8000;
      for (let index = 0; index < bytes.length; index += chunkSize) {
        binary += String.fromCharCode.apply(
          null,
          bytes.subarray(index, index + chunkSize)
        );
      }
      setResult({
        state: 'done',
        payload: {
          status: response.status,
          ok: response.ok,
          finalUrl: response.url,
          mimeType: response.headers.get('content-type') || '',
          contentDisposition:
            response.headers.get('content-disposition') || '',
          bodyBase64: btoa(binary)
        }
      });
    } catch (error) {
      setResult({
        state: 'error',
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
  return JSON.stringify(results && results[${jsonEncode(requestId)}] || null);
})()
''';
  }

  static String cleanup(String requestId) {
    return '''
(function() {
  const results = window.$_resultStore;
  if (results) {
    const requestId = ${jsonEncode(requestId)};
    if (results[requestId] && results[requestId].state === 'pending') {
      results[requestId] = { state: 'cancelled' };
    } else {
      delete results[requestId];
    }
  }
  return true;
})()
''';
  }
}
