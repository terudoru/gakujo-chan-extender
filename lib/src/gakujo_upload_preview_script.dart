import 'gakujo_image_bounds_script.dart';
import 'gakujo_office_preview_script.dart';
import 'gakujo_pdf_viewer_script.dart';
import 'gakujo_remote_file_preview_script.dart';

/// Adds a local preview of the file currently selected for upload.
class GakujoUploadPreviewScript {
  const GakujoUploadPreviewScript._();

  static String build() => '''
(function() {
${GakujoImageBoundsScript.source}
''' r'''
  if (window.__MBG_UPLOAD_PREVIEW_INSTALLED) return;
  window.__MBG_UPLOAD_PREVIEW_INSTALLED = true;
  var waiters = [];
  window.__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED = function() {
    var pending = waiters.splice(0);
    pending.forEach(function(done) { done(); });
  };
  function pdfLibrary(setCancel) {
    if (window.pdfjsLib && window.pdfjsViewer && window.__MBG_PDF_WORKER_URL &&
        window.__MBG_PDF_VIEWER_CSS && window.__MBG_PDF_CMAPS && window.__MBG_PDF_STANDARD_FONTS) return Promise.resolve();
    return new Promise(function(resolve, reject) {
      var channel = window.MbgUploadCompression;
      if (!channel || !channel.postMessage) { reject(new Error('PDFプレビューを読み込めません')); return; }
      var timer = window.setTimeout(function() {
        var index = waiters.indexOf(done);
        if (index >= 0) waiters.splice(index, 1);
        setCancel(null);
        reject(new Error('PDFプレビューの読み込みがタイムアウトしました'));
      }, 30000);
      function done() {
        window.clearTimeout(timer);
        setCancel(null);
        if (window.pdfjsLib && window.pdfjsViewer && window.__MBG_PDF_WORKER_URL &&
            window.__MBG_PDF_VIEWER_CSS && window.__MBG_PDF_CMAPS && window.__MBG_PDF_STANDARD_FONTS) resolve();
        else reject(new Error('PDFプレビューを読み込めません'));
      }
      waiters.push(done);
      setCancel(function() {
        window.clearTimeout(timer);
        var index = waiters.indexOf(done);
        if (index >= 0) waiters.splice(index, 1);
        resolve();
      });
      if (waiters.length === 1) channel.postMessage('preview');
    });
  }
  function documents() {
    var result = [document];
    var frames = document.querySelectorAll('iframe,frame');
    for (var i = 0; i < frames.length; i++) {
      try { if (frames[i].contentWindow.document) result.push(frames[i].contentWindow.document); }
      catch (e) { /* Different origins are not accessible. */ }
    }
    return result;
  }
  function show(input, file, onClosed) {
    var owner = window;
    try {
      if (window.top && window.top.location.origin === window.location.origin) owner = window.top;
    } catch (_) {}
    var previousPreview = owner.__MBG_ACTIVE_UPLOAD_PREVIEW;
    if (previousPreview && typeof previousPreview.close === 'function') previousPreview.close();
    var doc = input.ownerDocument;
    var overlay = doc.createElement('div');
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'ファイルのプレビュー');
    overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#fff;color:#111;display:flex;flex-direction:column;font:16px sans-serif';
    var bar = doc.createElement('div');
    bar.style.cssText = 'display:flex;gap:8px;align-items:center;padding:10px;flex-wrap:wrap;border-bottom:1px solid #ccc';
    // CampusSquare can use a desktop-sized layout viewport on a phone. Keep
    // controls readable even when the WebView scales that viewport down.
    var viewport = window.visualViewport;
    function resizeToolbar() {
      var scale = viewport && Number(viewport.scale);
      bar.style.zoom = String(scale > 0 ? Math.min(3, Math.max(1, 1 / scale)) : 1);
    }
    resizeToolbar();
    if (viewport) viewport.addEventListener('resize', resizeToolbar);
    var title = doc.createElement('strong'); title.textContent = file.name;
    title.style.cssText = 'flex:1 1 180px;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
    var close = doc.createElement('button'); close.type = 'button'; close.textContent = '閉じる';
    var previous = doc.createElement('button'); previous.type = 'button'; previous.textContent = '前へ';
    var next = doc.createElement('button'); next.type = 'button'; next.textContent = '次へ';
    var zoomOut = doc.createElement('button'); zoomOut.type = 'button'; zoomOut.textContent = '縮小';
    var zoomIn = doc.createElement('button'); zoomIn.type = 'button'; zoomIn.textContent = '拡大';
    var count = doc.createElement('span');
    bar.append(title, previous, count, next, zoomOut, zoomIn, close);
    var body = doc.createElement('div'); body.style.cssText = 'overflow:auto;flex:1;text-align:center;padding:12px';
    var status = doc.createElement('p'); status.textContent = '読み込み中…';
    body.appendChild(status); overlay.append(bar, body);
    // CampusSquare scales its body with a CSS transform; a fixed descendant
    // would cover only the scaled body instead of the viewport.
    (doc.documentElement || doc.body).appendChild(overlay);
    var closed = false, pdfStopped = false, worker = null, task = null, pdf = null, objectUrl = null, visual = null, zoom = 100, watchdog = null;
    var reader = null, cancelLibrary = null, pdfViewerCleanup = null;
    var sourceWindow = doc.defaultView || window;
    var detachWatcher = window.setInterval(function() {
      var detached = input.isConnected === false;
      try {
        if (sourceWindow !== window && (!sourceWindow.frameElement || sourceWindow.frameElement.isConnected === false)) detached = true;
      } catch (_) { detached = true; }
      if (detached) cleanup();
    }, 1000);
    var preview = {close: cleanup};
    owner.__MBG_ACTIVE_UPLOAD_PREVIEW = preview;
    function stopPdf() {
      pdfStopped = true;
      if (watchdog) { window.clearTimeout(watchdog); watchdog = null; }
      if (cancelLibrary) { cancelLibrary(); cancelLibrary = null; }
      if (reader) { try { reader.abort(); } catch (e) {} reader = null; }
      if (visual && /^(AUDIO|VIDEO)$/i.test(visual.tagName || '')) {
        try { visual.pause(); visual.removeAttribute('src'); visual.load(); } catch (e) {}
      }
      if (pdfViewerCleanup) { try { pdfViewerCleanup(); } catch (_) {} pdfViewerCleanup = null; }
      if (task) { try { Promise.resolve(task.destroy()).catch(function() {}); } catch (e) {} task = null; }
      if (worker) { worker.terminate(); worker = null; }
      pdf = null;
    }
    function armWatchdog() {
      if (watchdog) window.clearTimeout(watchdog);
      watchdog = window.setTimeout(function() {
        stopPdf();
        if (!closed) status.textContent = 'プレビューがタイムアウトしました。元のファイルは変更されません。';
      }, 30000);
    }
    function cleanup() {
      if (closed) return;
      closed = true;
      stopPdf();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
      overlay.remove();
      input.removeEventListener('change', cleanup);
      window.removeEventListener('pagehide', cleanup);
      if (viewport) viewport.removeEventListener('resize', resizeToolbar);
      if (sourceWindow !== window) sourceWindow.removeEventListener('pagehide', cleanup);
      window.clearInterval(detachWatcher);
      if (owner.__MBG_ACTIVE_UPLOAD_PREVIEW === preview) delete owner.__MBG_ACTIVE_UPLOAD_PREVIEW;
      if (onClosed) onClosed();
    }
    close.addEventListener('click', cleanup);
    input.addEventListener('change', cleanup);
    window.addEventListener('pagehide', cleanup);
    if (sourceWindow !== window) sourceWindow.addEventListener('pagehide', cleanup);
    previous.hidden = next.hidden = true;
    function fail(error) { stopPdf(); if (!closed) status.textContent = 'プレビューできません: ' + (error.message || error); }
    var extension = (file.name.split('.').pop() || '').toLowerCase();
    if (file.type.indexOf('image/') === 0 || /^(jpg|jpeg|png|webp)$/.test(extension)) {
      mbgValidateImage(file).then(function() {
        if (closed) return;
        objectUrl = URL.createObjectURL(file);
        var image = doc.createElement('img'); image.alt = file.name;
        image.style.cssText = 'width:100%;height:auto';
        image.onerror = function() { fail(new Error('画像を開けません')); };
        image.src = objectUrl; body.appendChild(image); visual = image; status.textContent = '';
      }).catch(fail);
    } else if (file.type === 'application/pdf' || extension === 'pdf') {
      if (file.size > 64 * 1024 * 1024) { fail(new Error('PDFが大きすぎます')); return; }
      armWatchdog();
      pdfLibrary(function(cancel) { cancelLibrary = cancel; }).then(function() {
        if (closed || pdfStopped) return null;
        return new Promise(function(resolve, reject) {
          reader = new FileReader();
          reader.onload = function() { var result = reader && reader.result; reader = null; resolve(result); };
          reader.onerror = function() { reader = null; reject(new Error('PDFを読み込めません')); };
          reader.onabort = function() { reader = null; resolve(null); };
          reader.readAsArrayBuffer(file);
        });
      }).then(function(bytes) {
        if (closed || pdfStopped || !bytes) return null;
        worker = new Worker(window.__MBG_PDF_WORKER_URL);
        var pdfWorker = window.pdfjsLib.PDFWorker.fromPort({port: worker});
        function CMapReaderFactory() {}
        CMapReaderFactory.prototype.fetch = function(request) {
          var name = request && request.name;
          var maps = window.__MBG_PDF_CMAPS;
          if (!name || !/^[A-Za-z0-9_-]{1,80}$/.test(name) || !maps ||
              !Object.prototype.hasOwnProperty.call(maps, name)) {
            return Promise.reject(new Error('PDF文字データを読み込めません'));
          }
          var raw = atob(maps[name]), data = new Uint8Array(raw.length);
          for (var i = 0; i < raw.length; i++) data[i] = raw.charCodeAt(i);
          return Promise.resolve({cMapData: data, compressionType: 1});
        };
        function StandardFontDataFactory() {}
        StandardFontDataFactory.prototype.fetch = function(request) {
          var name = request && request.filename, fonts = window.__MBG_PDF_STANDARD_FONTS;
          if (!name || !/^[A-Za-z0-9_.-]{1,80}$/.test(name) || !fonts ||
              !Object.prototype.hasOwnProperty.call(fonts, name)) {
            return Promise.reject(new Error('PDFフォントデータを読み込めません'));
          }
          var raw = atob(fonts[name]), data = new Uint8Array(raw.length);
          for (var i = 0; i < raw.length; i++) data[i] = raw.charCodeAt(i);
          return Promise.resolve(data);
        };
        task = window.pdfjsLib.getDocument({data: new Uint8Array(bytes), worker: pdfWorker,
          CMapReaderFactory: CMapReaderFactory, StandardFontDataFactory: StandardFontDataFactory,
          cMapPacked: true, useWorkerFetch: false, enableXfa: false,
          isEvalSupported: false, useSystemFonts: true, stopAtErrors: true, maxImageSize: 16000000});
        return task.promise;
      }).then(function(result) {
        if (closed || pdfStopped || !result) return;
        if (result.numPages > 2000) throw new Error('ページ数が安全な上限を超えています');
        pdf = result;
        pdfViewerCleanup = mbgCreatePdfViewer(doc, body, bar, status, pdf, previous, next, count, zoomOut, zoomIn,
          function() { if (watchdog) { window.clearTimeout(watchdog); watchdog = null; } });
      }).catch(fail);
    } else if (/^(mp3|m4a|wav|ogg|opus|mp4|m4v|webm)$/i.test(extension) ||
        /^(audio\/(mpeg|mp4|wav|ogg|opus)|video\/(mp4|webm))$/i.test(file.type)) {
      if (file.size > 64 * 1024 * 1024) { fail(new Error('メディアファイルが大きすぎます')); return; }
      var isVideo = /^(mp4|m4v|webm)$/i.test(extension) || /^video\//i.test(file.type);
      var media = doc.createElement(isVideo ? 'video' : 'audio');
      media.controls = true; media.preload = 'metadata';
      media.style.cssText = 'max-width:100%;max-height:80vh';
      media.onerror = function() { fail(new Error('このメディアを開けません')); };
      media.onloadedmetadata = function() {
        if (isVideo && (!media.videoWidth || !media.videoHeight || media.videoWidth > 10000 ||
            media.videoHeight > 10000 || media.videoWidth * media.videoHeight > 16000000)) {
          fail(new Error('動画のサイズが安全な範囲を超えています'));
        }
      };
      objectUrl = URL.createObjectURL(file); media.src = objectUrl;
      body.appendChild(media); visual = media; status.textContent = '';
    } else if (/^(docx|docm|xlsx|xlsm|pptx|pptm)$/i.test(extension)) {
      if (file.size > 32 * 1024 * 1024) { fail(new Error('文書が大きすぎます')); return; }
      armWatchdog();
      officeLibrary(function(cancel) { cancelLibrary = cancel; }).then(function() {
        if (closed || pdfStopped) return null;
        return new Promise(function(resolve, reject) {
          reader = new FileReader();
          reader.onload = function() { var result = reader && reader.result; reader = null; resolve(result); };
          reader.onerror = function() { reader = null; reject(new Error('文書を読み込めません')); };
          reader.onabort = function() { reader = null; resolve(null); };
          reader.readAsArrayBuffer(file);
        });
      }).then(function(bytes) {
        if (closed || pdfStopped || !bytes) return null;
        return mbgOfficeText(bytes, extension, function() { return closed || pdfStopped; });
      }).then(function(text) {
        if (closed || pdfStopped || text === null) return;
        var pre = doc.createElement('pre');
        pre.style.cssText = 'white-space:pre-wrap;overflow-wrap:anywhere;text-align:left';
        pre.textContent = text;
        body.appendChild(pre);
        status.textContent = 'テキストのみ表示しています。書式・画像・数式の表示は元の文書と異なります。';
        if (watchdog) { window.clearTimeout(watchdog); watchdog = null; }
      }).catch(fail);
    } else if (/^(txt|csv|tsv|md|log|json|xml|yaml|yml)$/i.test(extension) ||
        /^text\/(plain|csv|tab-separated-values)$/i.test(file.type) ||
        /^application\/(json|xml)$/i.test(file.type)) {
      if (file.size > 4 * 1024 * 1024) { fail(new Error('テキストが大きすぎます')); return; }
      reader = new FileReader();
      reader.onload = function() {
        var bytes = reader && reader.result; reader = null;
        if (closed || pdfStopped) return;
        var text;
        try {
          var data = new Uint8Array(bytes), encoding = 'utf-8';
          if (data.length >= 2 && data[0] === 255 && data[1] === 254) encoding = 'utf-16le';
          else if (data.length >= 2 && data[0] === 254 && data[1] === 255) encoding = 'utf-16be';
          try { text = new TextDecoder(encoding, {fatal: true}).decode(data); }
          catch (error) {
            if (encoding !== 'utf-8') throw error;
            text = new TextDecoder('shift_jis', {fatal: true}).decode(data);
          }
        } catch (_) { fail(new Error('テキストの文字コードを読み取れません')); return; }
        var pre = doc.createElement('pre');
        pre.style.cssText = 'white-space:pre-wrap;overflow-wrap:anywhere;text-align:left';
        pre.textContent = text;
        body.appendChild(pre); status.textContent = '';
      };
      reader.onerror = function() { reader = null; fail(new Error('テキストを読み込めません')); };
      reader.onabort = function() { reader = null; };
      reader.readAsArrayBuffer(file);
    } else {
      status.textContent = 'この形式のプレビューには対応していません。';
    }
    function setZoom(value) {
      if (pdf) return;
      zoom = Math.max(50, Math.min(300, value));
      if (visual) visual.style.width = zoom + '%';
    }
    zoomOut.addEventListener('click', function() { setZoom(zoom - 50); });
    zoomIn.addEventListener('click', function() { setZoom(zoom + 50); });
    close.focus();
  }
  function attach() {
    documents().forEach(function(doc) {
      var inputs = doc.querySelectorAll('input[type="file"]');
      for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];
        if (input.__mbgPreviewButton && input.__mbgPreviewButton.isConnected) continue;
        if (!input.parentNode) continue;
        var button = doc.createElement('button'); button.type = 'button';
        button.textContent = '選択したファイルをプレビュー';
        button.style.cssText = 'margin:4px 8px;padding:6px 10px';
        input.parentNode.insertBefore(button, input.nextSibling);
        input.__mbgPreviewButton = button;
        (function(target, control) {
          var list = null;
          target.addEventListener('change', function() { if (list) { list.remove(); list = null; } });
          control.addEventListener('click', function() {
            if (list) { list.remove(); list = null; }
            if (target.__mbgUploadCompressionPending) { control.textContent = '圧縮が終わるまでお待ちください'; return; }
            var files = target.files || [];
            if (!files.length) { control.textContent = '先にファイルを選択してください'; return; }
            control.textContent = '選択したファイルをプレビュー';
            // Multiple selection: provide a separate button for each file.
            if (files.length === 1) { show(target, files[0]); return; }
            var doc = target.ownerDocument;
            list = doc.createElement('div');
            Array.prototype.forEach.call(files, function(file) {
              var choice = doc.createElement('button'); choice.type = 'button'; choice.textContent = file.name;
              choice.addEventListener('click', function() { list.remove(); show(target, file); });
              list.appendChild(choice);
            });
            control.after(list);
          });
        })(input, button);
      }
      mbgAttachSubmittedPreviews(doc);
    });
  }
''' '''
${GakujoRemoteFilePreviewScript.source}
${GakujoOfficePreviewScript.source}
${GakujoPdfViewerScript.source}
''' r'''
  attach();
  window.setInterval(attach, 1000);
})();
''';
}
