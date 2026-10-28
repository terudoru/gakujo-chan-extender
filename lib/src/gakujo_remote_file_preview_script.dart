import 'dart:convert';

import 'gakujo_download_request.dart';

/// Retrieves a selected attachment into memory and hands it to the local
/// preview. It never writes the response to a download destination.
class GakujoRemoteFilePreviewScript {
  const GakujoRemoteFilePreviewScript._();

  static String open(GakujoDownloadRequest request) =>
      'window.__MBG_OPEN_REMOTE_PREVIEW(${jsonEncode(request.toJson())});';

  // Inserted inside the preview closure so it can use the same renderer and
  // lifecycle as files selected locally.
  static const source = r'''
  window.__MBG_OPEN_REMOTE_PREVIEW = function(request) {
    if (window.location.origin !== 'https://gakujo.iess.niigata-u.ac.jp') return false;
    var url;
    try { url = new URL(request.url, window.location.href); } catch (_) { return false; }
    if (url.origin !== window.location.origin || url.username || url.password) return false;
    var method = String(request.method || '').toUpperCase();
    if (method !== 'GET' && method !== 'POST') return false;
    var fields = request.formFields || {}, strong = false, workflow = false;
    var fileRefer = false, fileId = false;
    function inspect(value, key) {
      var named = /^_eventId_(.*)$/i.exec(key);
      if (/^_eventId$/i.test(key) || named) {
        var action = named ? named[1] : String(value);
        if (/download/i.test(action)) strong = true;
        if (/(confirm|entry|submit|save|regist|update|delete|back|clear|cancel|next|prev|complete|finish|reset)/i.test(action) ||
            (action.trim() && !/download/i.test(action))) workflow = true;
      }
      if (/^(file.?download|download.?file|downloadType)$/i.test(key)) strong = true;
      if (/^_flowId$/i.test(key) && /filerefer/i.test(String(value))) fileRefer = true;
      if (/^fileId$/i.test(key) && String(value).trim()) fileId = true;
    }
    url.searchParams.forEach(inspect);
    Object.keys(fields).forEach(function(key) { inspect(fields[key], key); });
    if (/\.(pdf|png|jpe?g|webp|txt|csv|tsv|md|log|json|xml|ya?ml|mp3|m4a|wav|ogg|opus|mp4|m4v|webm|docx|docm|xlsx|xlsm|pptx|pptm)(?:$|[?#])/i.test(url.pathname)) strong = true;
    if (fileRefer && fileId) strong = true;
    if (!strong || workflow) return false;
    var keys = Object.keys(fields);
    if (keys.length > 100 || keys.some(function(key) {
      return key.length > 1024 || String(fields[key]).length > 16384;
    })) return false;

    var previous = window.__MBG_ACTIVE_UPLOAD_PREVIEW;
    if (previous && typeof previous.close === 'function') previous.close();
    var doc = document, overlay = doc.createElement('div');
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'ファイルのプレビュー');
    overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#fff;color:#111;padding:24px;font:16px sans-serif';
    var status = doc.createElement('p'); status.textContent = 'ファイルを読み込み中…';
    var close = doc.createElement('button'); close.type = 'button'; close.textContent = '閉じる';
    overlay.append(status, close); doc.body.appendChild(overlay);
    var controller = new AbortController(), closed = false;
    var timeout = window.setTimeout(function() {
      controller.abort();
      if (!closed) status.textContent = '読み込みがタイムアウトしました。';
    }, 30000);
    var operation = {close: cleanup};
    window.__MBG_ACTIVE_UPLOAD_PREVIEW = operation;
    function cleanup() {
      if (closed) return;
      closed = true; controller.abort(); window.clearTimeout(timeout);
      window.removeEventListener('pagehide', cleanup); overlay.remove();
      if (window.__MBG_ACTIVE_UPLOAD_PREVIEW === operation) delete window.__MBG_ACTIVE_UPLOAD_PREVIEW;
    }
    close.addEventListener('click', cleanup);
    window.addEventListener('pagehide', cleanup);
    close.focus();
    var options = {method: method, credentials: 'same-origin', redirect: 'error',
      cache: 'no-store', signal: controller.signal};
    if (method === 'GET') {
      keys.forEach(function(key) { url.searchParams.set(key, String(fields[key])); });
    } else {
      var body = new URLSearchParams();
      keys.forEach(function(key) { body.append(key, String(fields[key])); });
      options.body = body.toString();
      options.headers = {'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'};
    }
    fetch(url.href, options).then(function(response) {
      if (!response.ok || !response.url || new URL(response.url).origin !== window.location.origin) {
        throw new Error('ファイルを取得できません');
      }
      var type = (response.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
      if (type === 'text/html' || type === 'application/xhtml+xml') throw new Error('ファイルではなくページが返されました');
      var length = response.headers.get('content-length');
      if (length && (!/^\d+$/.test(length) || Number(length) > 64 * 1024 * 1024)) throw new Error('ファイルが大きすぎます');
      if (!response.body || !response.body.getReader) throw new Error('この環境では安全に読み込めません');
      var disposition = response.headers.get('content-disposition') || '';
      var extended = /(?:^|;)\s*filename\*\s*=\s*UTF-8''([^;]+)/i.exec(disposition);
      var plain = /(?:^|;)\s*filename\s*=\s*(?:"([^"]*)"|([^;]*))/i.exec(disposition);
      var suggested = plain ? (plain[1] || plain[2] || '').trim() : '';
      if (extended) { try { suggested = decodeURIComponent(extended[1].trim()); } catch (_) {} }
      var reader = response.body.getReader(), parts = [], size = 0;
      function next() {
        return reader.read().then(function(item) {
          if (closed) return null;
          if (item.done) return {parts: parts, type: type, name: suggested};
          size += item.value.byteLength;
          if (size > 64 * 1024 * 1024) { controller.abort(); throw new Error('ファイルが大きすぎます'); }
          parts.push(item.value); return next();
        });
      }
      return next();
    }).then(function(result) {
      if (closed || !result) return;
      var name = String(result.name || request.fileName || '').trim() || 'ファイル';
      var header = [], remaining = 1024;
      result.parts.some(function(part) {
        var take = Math.min(remaining, part.length);
        for (var i = 0; i < take; i++) header.push(part[i]);
        remaining -= take; return remaining === 0;
      });
      var first = new Uint8Array(header);
      var prefix = String.fromCharCode.apply(null, first);
      if (/^(?:\xEF\xBB\xBF)?\s*(?:<!doctype\s+html|<html)(?:\s|>)/i.test(prefix)) throw new Error('ファイルではなくページが返されました');
      var type = result.type;
      if (prefix.indexOf('%PDF-') === 0) type = 'application/pdf';
      else if (first.length >= 3 && first[0] === 255 && first[1] === 216 && first[2] === 255) type = 'image/jpeg';
      else if (first.length >= 8 && first[0] === 137 && prefix.slice(1, 4) === 'PNG') type = 'image/png';
      else if (prefix.slice(0, 4) === 'RIFF' && prefix.slice(8, 12) === 'WEBP') type = 'image/webp';
      var file = new File(result.parts, name, {type: type});
      var anchor = doc.createElement('input'); anchor.type = 'hidden'; doc.body.appendChild(anchor);
      cleanup();
      show(anchor, file, function() { anchor.remove(); });
    }).catch(function(error) {
      window.clearTimeout(timeout);
      if (!closed && error.name !== 'AbortError') status.textContent = 'プレビューできません: ' + (error.message || error);
    });
    return true;
  };
''';
}
