/// Retrieves a selected attachment into memory and hands it to the local
/// preview. It never writes the response to a download destination.
class GakujoRemoteFilePreviewScript {
  const GakujoRemoteFilePreviewScript._();

  // Inserted inside the preview closure so it can use the same renderer and
  // lifecycle as files selected locally.
  static const source = r'''
  function mbgSubmittedFileRequest(anchor) {
    try {
      if (!anchor || !anchor.ownerDocument ||
          !/^javascript:\s*void\s*\(\s*0\s*\)\s*;?$/i.test(anchor.getAttribute('href') || '')) return null;
      var handler = anchor.getAttribute('onclick') || '';
      // Only parse the known read-only handler; never evaluate page code or
      // invoke its form submission when the user asks for a preview.
      var match = /^\s*(?:return\s+)?callFileDownLoad\s*\(\s*(['"])answerDownLoad\1\s*,\s*(['"]?)(\d{1,9})\2\s*,\s*(['"]?)(\d{1,9})\4\s*,\s*(['"])([^'"\\\r\n]{0,256})\6\s*\)\s*;?\s*$/i.exec(handler);
      if (!match) return null;
      var page = new URL(anchor.ownerDocument.location.href);
      if (page.origin !== 'https://gakujo.iess.niigata-u.ac.jp' || page.username || page.password ||
          page.pathname.toLowerCase() !== '/campusweb/campussquare.do') return null;
      var flow = page.searchParams.getAll('_flowExecutionKey');
      if (flow.length !== 1 || !flow[0] || flow[0].length > 1024) return null;
      var url = new URL('/campusweb/campussquare.do', page.origin);
      url.searchParams.set('_flowExecutionKey', flow[0]);
      url.searchParams.set('_eventId', 'answerDownLoad');
      url.searchParams.set('questionSort', match[3]);
      url.searchParams.set('tempNo', match[5]);
      url.searchParams.set('ansTempId', match[7]);
      var name = (anchor.textContent || '').replace(/\s+/g, ' ').trim();
      return {url: url.href, method: 'GET', fileName: name.slice(0, 240), formFields: {}};
    } catch (_) { return null; }
  }
  function mbgAttachSubmittedPreviews(doc) {
    var anchors = doc.querySelectorAll('a[href], button, input[type="submit"], input[type="button"]');
    for (var i = 0; i < anchors.length; i++) {
      var anchor = anchors[i];
      if (anchor.__mbgSubmittedPreviewButton && anchor.__mbgSubmittedPreviewButton.isConnected) continue;
      if (!anchor.parentNode || !mbgRemoteFileRequest(anchor)) continue;
      var button = doc.createElement('button'); button.type = 'button';
      button.textContent = 'プレビューを見る';
      button.setAttribute('data-mbg-submitted-preview', 'true');
      button.style.cssText = 'margin:4px 8px;padding:6px 10px';
      anchor.parentNode.insertBefore(button, anchor.nextSibling);
      anchor.__mbgSubmittedPreviewButton = button;
      (function(target, control) {
        control.addEventListener('click', function() {
          var request = mbgRemoteFileRequest(target);
          if (!request || !window.__MBG_OPEN_REMOTE_PREVIEW(request)) {
            control.textContent = 'プレビューできません';
            return;
          }
          control.textContent = 'プレビューを見る';
        });
      })(anchor, button);
    }
  }
  function mbgRemoteFileRequest(anchor) {
    try {
      var page = new URL(anchor.ownerDocument.location.href);
      if (page.origin !== 'https://gakujo.iess.niigata-u.ac.jp' || page.username || page.password) return null;
      if (String(anchor.tagName || '').toLowerCase() !== 'a') {
        // Never run a page's onclick or replay a workflow action to preview.
        if (anchor.getAttribute('onclick')) return null;
        var form = anchor.form;
        if (!form) return null;
        var method = (anchor.getAttribute('formmethod') || form.getAttribute('method') || 'GET').toUpperCase();
        var enctype = (anchor.getAttribute('formenctype') || form.getAttribute('enctype') || 'application/x-www-form-urlencoded').toLowerCase();
        var target = anchor.getAttribute('formtarget') || form.getAttribute('target') || '_self';
        if (!/^(GET|POST)$/.test(method) || (method === 'POST' && enctype !== 'application/x-www-form-urlencoded') || !/^_self$/i.test(target)) return null;
        var action = anchor.getAttribute('formaction') || form.getAttribute('action') || page.href;
        var fields = {}, unsafe = false, data = new FormData(form);
        if (anchor.name) data.set(anchor.name, anchor.value || '');
        data.forEach(function(value, key) { if (typeof value !== 'string' || /^(?:__proto__|constructor|prototype)$/.test(key) || Object.prototype.hasOwnProperty.call(fields, key)) unsafe = true; else fields[key] = value; });
        if (unsafe) return null;
        var formRequest = {url: new URL(action, page.href).href, method: method,
          fileName: String(anchor.textContent || anchor.value || '').trim().slice(0, 240), formFields: fields};
        return mbgValidateRemotePreviewRequest(formRequest) ? formRequest : null;
      }
      var submitted = mbgSubmittedFileRequest(anchor);
      if (submitted) return submitted;
      var href = (anchor.getAttribute('href') || '').trim();
      if (!href || /^javascript:/i.test(href) || href.charAt(0) === '#') return null;
      var request = {url: new URL(href, page.href).href, method: 'GET',
        fileName: String(anchor.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 240), formFields: {}};
      return mbgValidateRemotePreviewRequest(request) ? request : null;
    } catch (_) { return null; }
  }
  function mbgValidateRemotePreviewRequest(request) {
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
    return true;
  }
  window.__MBG_OPEN_REMOTE_PREVIEW = function(request) {
    if (!mbgValidateRemotePreviewRequest(request)) return false;
    var url = new URL(request.url, window.location.href);
    var method = String(request.method || '').toUpperCase();
    var fields = request.formFields || {}, keys = Object.keys(fields);

    var previous = window.__MBG_ACTIVE_UPLOAD_PREVIEW;
    if (previous && typeof previous.close === 'function') previous.close();
    var doc = document, overlay = doc.createElement('div');
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'ファイルのプレビュー');
    overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#fff;color:#111;padding:24px;font:16px sans-serif';
    var status = doc.createElement('p'); status.textContent = 'ファイルを読み込み中…';
    var close = doc.createElement('button'); close.type = 'button'; close.textContent = '閉じる';
    overlay.append(status, close); (doc.documentElement || doc.body).appendChild(overlay);
    var controller = new AbortController(), closed = false;
    var timeout = window.setTimeout(function() {
      controller.abort();
      if (!closed) status.textContent = '読み込みがタイムアウトしました。';
    }, 30000);
    var operation = {close: cleanup, visible: true, setVisible: setVisible};
    window.__MBG_ACTIVE_UPLOAD_PREVIEW = operation;
    function setVisible(visible) {
      if (closed) return;
      operation.visible = visible;
      overlay.style.display = visible ? 'block' : 'none';
      mbgPreviewReport(visible ? 'visible' : 'hidden');
    }
    setVisible(true);
    function cleanup(preserveState) {
      if (closed) return;
      closed = true; controller.abort(); window.clearTimeout(timeout);
      window.removeEventListener('pagehide', cleanup); overlay.remove();
      if (window.__MBG_ACTIVE_UPLOAD_PREVIEW === operation) {
        delete window.__MBG_ACTIVE_UPLOAD_PREVIEW;
        if (preserveState !== true) mbgPreviewReport('none');
      }
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
      var visible = operation.visible;
      cleanup(true);
      show(anchor, file, function() { anchor.remove(); }, visible);
    }).catch(function(error) {
      window.clearTimeout(timeout);
      if (!closed && error.name !== 'AbortError') status.textContent = 'プレビューできません: ' + (error.message || error);
    });
    return true;
  };
''';
}
