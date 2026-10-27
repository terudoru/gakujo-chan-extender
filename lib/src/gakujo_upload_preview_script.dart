import 'gakujo_image_bounds_script.dart';

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
    if (window.pdfjsLib && window.__MBG_PDF_WORKER_URL) return Promise.resolve();
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
        if (window.pdfjsLib && window.__MBG_PDF_WORKER_URL) resolve();
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
  function show(input, file) {
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
    var title = doc.createElement('strong'); title.textContent = file.name;
    title.style.cssText = 'flex:1;overflow-wrap:anywhere';
    var close = doc.createElement('button'); close.type = 'button'; close.textContent = '閉じる';
    var previous = doc.createElement('button'); previous.type = 'button'; previous.textContent = '前へ';
    var next = doc.createElement('button'); next.type = 'button'; next.textContent = '次へ';
    var zoomOut = doc.createElement('button'); zoomOut.type = 'button'; zoomOut.textContent = '縮小';
    var zoomIn = doc.createElement('button'); zoomIn.type = 'button'; zoomIn.textContent = '拡大';
    var count = doc.createElement('span');
    bar.append(title, previous, count, next, zoomOut, zoomIn, close);
    var body = doc.createElement('div'); body.style.cssText = 'overflow:auto;flex:1;text-align:center;padding:12px';
    var status = doc.createElement('p'); status.textContent = '読み込み中…';
    body.appendChild(status); overlay.append(bar, body); doc.body.appendChild(overlay);
    var closed = false, pdfStopped = false, worker = null, task = null, pdf = null, pageNumber = 1, objectUrl = null, render = null, visual = null, zoom = 100, watchdog = null;
    var reader = null, cancelLibrary = null, rendering = false, renderRevision = 0;
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
      renderRevision++;
      if (watchdog) { window.clearTimeout(watchdog); watchdog = null; }
      if (cancelLibrary) { cancelLibrary(); cancelLibrary = null; }
      if (reader) { try { reader.abort(); } catch (e) {} reader = null; }
      if (render) { try { render.cancel(); } catch (e) {} render = null; }
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
      if (sourceWindow !== window) sourceWindow.removeEventListener('pagehide', cleanup);
      window.clearInterval(detachWatcher);
      if (owner.__MBG_ACTIVE_UPLOAD_PREVIEW === preview) delete owner.__MBG_ACTIVE_UPLOAD_PREVIEW;
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
        task = window.pdfjsLib.getDocument({data: new Uint8Array(bytes), worker: pdfWorker,
          isEvalSupported: false, useSystemFonts: true, stopAtErrors: true, maxImageSize: 16000000});
        return task.promise;
      }).then(function(result) {
        if (closed || pdfStopped || !result) return;
        pdf = result; previous.hidden = next.hidden = false;
        requestPage();
      }).catch(fail);
    } else {
      status.textContent = 'この形式のプレビューには対応していません。';
    }
    function requestPage() {
      if (closed || pdfStopped || !pdf) return;
      renderRevision++;
      if (render) { try { render.cancel(); } catch (e) {} }
      if (!rendering) displayPage();
    }
    function displayPage() {
      if (closed || pdfStopped || !pdf || rendering) return;
      rendering = true;
      armWatchdog();
      previous.disabled = pageNumber <= 1; next.disabled = pageNumber >= pdf.numPages;
      count.textContent = pageNumber + ' / ' + pdf.numPages;
      status.textContent = 'ページを読み込み中…';
      var current = pageNumber, revision = renderRevision, pageForCleanup = null;
      Promise.resolve().then(function() { return pdf.getPage(current); }).then(function(page) {
        pageForCleanup = page;
        if (closed || pdfStopped || revision !== renderRevision) return;
        var viewport = page.getViewport({scale: 1.5});
        if (!Number.isFinite(viewport.width) || !Number.isFinite(viewport.height) ||
            viewport.width <= 0 || viewport.height <= 0) throw new Error('PDFページのサイズが不正です');
        var scale = Math.min(1, Math.sqrt(16000000 / (viewport.width * viewport.height)));
        viewport = page.getViewport({scale: 1.5 * scale});
        var canvas = doc.createElement('canvas');
        canvas.width = Math.ceil(viewport.width); canvas.height = Math.ceil(viewport.height);
        canvas.style.cssText = 'width:' + zoom + '%;height:auto';
        render = page.render({canvasContext: canvas.getContext('2d'), viewport: viewport});
        return render.promise.then(function() {
          if (closed || pdfStopped || revision !== renderRevision) return;
          while (body.lastChild && body.lastChild !== status) body.removeChild(body.lastChild);
          status.textContent = '大きな画像は安全上表示されない場合があります。';
          body.appendChild(canvas); visual = canvas;
          if (watchdog) { window.clearTimeout(watchdog); watchdog = null; }
        });
      }).catch(function(error) {
        if (!closed && !pdfStopped && revision === renderRevision) fail(error);
      }).finally(function() {
        if (pageForCleanup) { try { pageForCleanup.cleanup(); } catch (e) {} }
        render = null;
        rendering = false;
        if (!closed && !pdfStopped && revision !== renderRevision) displayPage();
      });
    }
    previous.addEventListener('click', function() { if (pageNumber > 1) { pageNumber--; requestPage(); } });
    next.addEventListener('click', function() { if (pdf && pageNumber < pdf.numPages) { pageNumber++; requestPage(); } });
    function setZoom(value) { zoom = Math.max(100, Math.min(300, value)); if (visual) visual.style.width = zoom + '%'; }
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
    });
  }
  attach();
  window.setInterval(attach, 1000);
})();
''';
}
