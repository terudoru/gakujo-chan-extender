import 'gakujo_image_bounds_script.dart';
import 'gakujo_office_preview_script.dart';
import 'gakujo_pdf_viewer_script.dart';
import 'gakujo_remote_file_preview_script.dart';

/// Adds a local preview of the file currently selected for upload.
class GakujoUploadPreviewScript {
  const GakujoUploadPreviewScript._();

  static String build({bool compactAndroid = false}) => '''
(function() {
var mbgCompactAndroid = $compactAndroid;
${GakujoImageBoundsScript.source}
''' r'''
  if (window.__MBG_UPLOAD_PREVIEW_INSTALLED) return;
  window.__MBG_UPLOAD_PREVIEW_INSTALLED = true;
  function mbgPreviewReport(state) {
    var channel = window.MbgPreviewNavigation;
    if (channel && channel.postMessage) channel.postMessage(state);
  }
  window.__MBG_PREVIEW_NAVIGATE = function(direction) {
    var preview = window.__MBG_ACTIVE_UPLOAD_PREVIEW;
    if (!preview || typeof preview.setVisible !== 'function') return false;
    if (direction === 'back' && preview.visible) preview.setVisible(false);
    else if (direction === 'forward' && !preview.visible) preview.setVisible(true);
    else if (direction === 'forward' && preview.visible) return true;
    else return false;
    return true;
  };
  var waiters = [];
  window.__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED = function() {
    var pending = waiters.splice(0);
    pending.forEach(function(done) { done(); });
  };
  function pdfLibrary(setCancel) {
    if (window.__MBG_PDF_PREVIEW_URL) return Promise.resolve();
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
        if (window.__MBG_PDF_PREVIEW_URL || (window.pdfjsLib && window.pdfjsViewer && window.__MBG_PDF_WORKER_URL &&
            window.__MBG_PDF_VIEWER_CSS && window.__MBG_PDF_CMAPS && window.__MBG_PDF_STANDARD_FONTS)) resolve();
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
    var result = [], seen = new Set();
    function visit(doc) {
      if (!doc || seen.has(doc) || result.length >= 64) return;
      seen.add(doc); result.push(doc);
      var frames = doc.querySelectorAll('iframe,frame');
      for (var i = 0; i < frames.length && result.length < 64; i++) {
        try { visit(frames[i].contentWindow.document); }
        catch (e) { /* Different origins are not accessible. */ }
      }
    }
    visit(document);
    return result;
  }
  function show(input, file, onClosed, initiallyVisible) {
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
    var sourceWindow = doc.defaultView || window;
    var viewport = sourceWindow.visualViewport;
    var rootViewport = window.visualViewport;
    var previewFrame = null;
    function displayedScale() {
      var scale = viewport && Number(viewport.scale);
      if (!(scale > 0)) scale = 1;
      if (sourceWindow === window) return scale;
      try {
        var rootScale = rootViewport && Number(rootViewport.scale);
        if (rootScale > 0) scale *= rootScale;
        var current = sourceWindow;
        for (var depth = 0; current !== window && depth < 64; depth++) {
          var element = current.frameElement;
          if (!element) break;
          if (element.offsetWidth && element.getBoundingClientRect) {
            var ratio = element.getBoundingClientRect().width / element.offsetWidth;
            if (ratio > 0 && isFinite(ratio)) scale *= ratio;
          }
          current = current.parent;
          if (!current) break;
        }
      } catch (_) { /* A cross-origin ancestor is not accessible. */ }
      return scale;
    }
    function resizeToolbar() {
      var scale = displayedScale();
      bar.style.zoom = String(scale > 0 ? Math.min(3, Math.max(1, 1 / scale)) : 1);
      // In a landscape phone with the keyboard open, retain the viewer's
      // search field instead of spending the remaining height on this header.
      var screen = sourceWindow.screen;
      var compact = !!(mbgCompactAndroid && previewFrame && viewport && screen && screen.width > screen.height &&
        viewport.height * scale < 180);
      bar.style.display = compact ? 'none' : 'flex';
      if (visual && textZoom) visual.style.zoom = bar.style.zoom;
      if (previewFrame) {
        // A desktop-width page on a phone can be scaled below 100%. Give the
        // embedded Flutter viewer the physical viewport size and scale its
        // frame back up, so its toolbar and hit targets stay on screen.
        var frameScale = scale > 0 ? Math.max(.1, Math.min(5, scale)) : 1;
        previewFrame.style.width = (frameScale * 100) + '%';
        previewFrame.style.height = (frameScale * 100) + '%';
        previewFrame.style.transform = 'scale(' + (1 / frameScale) + ')';
        previewFrame.style.transformOrigin = 'top left';
      }
      // The layout viewport may be wider or taller than the visible area on
      // Android. A fixed inset:0 overlay otherwise extends off-screen when
      // the user has panned or the page has a desktop-sized layout viewport.
      if (viewport && viewport.width > 0 && viewport.height > 0) {
        overlay.style.left = (viewport.offsetLeft || 0) + 'px';
        overlay.style.top = (viewport.offsetTop || 0) + 'px';
        overlay.style.width = viewport.width + 'px';
        overlay.style.height = viewport.height + 'px';
        overlay.style.right = 'auto'; overlay.style.bottom = 'auto';
      }
    }
    resizeToolbar();
    if (viewport) {
      viewport.addEventListener('resize', resizeToolbar);
      viewport.addEventListener('scroll', resizeToolbar);
    }
    if (rootViewport && rootViewport !== viewport) {
      rootViewport.addEventListener('resize', resizeToolbar);
      rootViewport.addEventListener('scroll', resizeToolbar);
    }
    var title = doc.createElement('strong'); title.textContent = file.name;
    title.style.cssText = 'flex:1 1 180px;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
    var close = doc.createElement('button'); close.type = 'button'; close.textContent = '閉じる';
    var previous = doc.createElement('button'); previous.type = 'button'; previous.textContent = '前へ';
    var next = doc.createElement('button'); next.type = 'button'; next.textContent = '次へ';
    var zoomOut = doc.createElement('button'); zoomOut.type = 'button'; zoomOut.textContent = '縮小';
    var zoomIn = doc.createElement('button'); zoomIn.type = 'button'; zoomIn.textContent = '拡大';
    var imageZoomLabel = doc.createElement('span'); imageZoomLabel.hidden = true;
    imageZoomLabel.setAttribute('aria-label', '表示倍率');
    var count = doc.createElement('span');
    bar.append(title, previous, count, next, zoomOut, imageZoomLabel, zoomIn, close);
    var body = doc.createElement('div'); body.style.cssText = 'overflow:auto;flex:1;text-align:center;padding:12px';
    var status = doc.createElement('p'); status.textContent = '読み込み中…';
    body.appendChild(status); overlay.append(bar, body);
    // CampusSquare scales its body with a CSS transform; a fixed descendant
    // would cover only the scaled body instead of the viewport.
    (doc.documentElement || doc.body).appendChild(overlay);
    var closed = false, pdfStopped = false, worker = null, task = null, pdf = null, objectUrl = null, visual = null, zoom = 100, watchdog = null;
    var reader = null, cancelLibrary = null, pdfViewerCleanup = null, imageGestureCleanup = null;
    var textZoom = false;
    var detachWatcher = window.setInterval(function() {
      var detached = input.isConnected === false;
      try {
        if (sourceWindow !== window && (!sourceWindow.frameElement || sourceWindow.frameElement.isConnected === false)) detached = true;
      } catch (_) { detached = true; }
      if (detached) cleanup();
    }, 1000);
    var preview = {close: cleanup, visible: initiallyVisible !== false, setVisible: setVisible};
    owner.__MBG_ACTIVE_UPLOAD_PREVIEW = preview;
    function setVisible(visible) {
      if (closed) return;
      preview.visible = visible;
      overlay.style.display = visible ? 'flex' : 'none';
      if (!visible && visual && /^(AUDIO|VIDEO)$/i.test(visual.tagName || '')) {
        try { visual.pause(); } catch (_) {}
      }
      mbgPreviewReport(visible ? 'visible' : 'hidden');
    }
    setVisible(preview.visible);
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
      if (imageGestureCleanup) { imageGestureCleanup(); imageGestureCleanup = null; }
      stopPdf();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
      overlay.remove();
      input.removeEventListener('change', cleanup);
      window.removeEventListener('pagehide', cleanup);
      if (viewport) {
        viewport.removeEventListener('resize', resizeToolbar);
        viewport.removeEventListener('scroll', resizeToolbar);
      }
      if (rootViewport && rootViewport !== viewport) {
        rootViewport.removeEventListener('resize', resizeToolbar);
        rootViewport.removeEventListener('scroll', resizeToolbar);
      }
      if (sourceWindow !== window) sourceWindow.removeEventListener('pagehide', cleanup);
      window.clearInterval(detachWatcher);
      if (owner.__MBG_ACTIVE_UPLOAD_PREVIEW === preview) {
        delete owner.__MBG_ACTIVE_UPLOAD_PREVIEW;
        mbgPreviewReport('none');
      }
      if (onClosed) onClosed();
    }
    close.addEventListener('click', cleanup);
    input.addEventListener('change', cleanup);
    window.addEventListener('pagehide', cleanup);
    if (sourceWindow !== window) sourceWindow.addEventListener('pagehide', cleanup);
    previous.hidden = next.hidden = true;
    function fail(error) { stopPdf(); if (!closed) status.textContent = 'プレビューできません: ' + (error.message || error); }
    function enableVisualZoom(element, isText) {
      visual = element; textZoom = isText;
      resizeToolbar();
      imageZoomLabel.hidden = false; imageZoomLabel.textContent = '100%';
      imageGestureCleanup = mbgPreviewGestures(body, {
        min: .25, max: 5, getScale: function() { return zoom / 100; },
        setScale: function(scale) { setZoom(scale * 100); }
      });
    }
    var extension = (file.name.split('.').pop() || '').toLowerCase();
    if (file.type.indexOf('image/') === 0 || /^(jpg|jpeg|png|webp)$/.test(extension)) {
      mbgValidateImage(file).then(function() {
        if (closed) return;
        objectUrl = URL.createObjectURL(file);
        var image = doc.createElement('img'); image.alt = file.name;
        image.style.cssText = 'width:100%;height:auto';
        image.onerror = function() { fail(new Error('画像を開けません')); };
        image.src = objectUrl; body.appendChild(image); status.textContent = '';
        enableVisualZoom(image, false);
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
        if (window.__MBG_PDF_PREVIEW_URL) {
          var popup = !!window.__MBG_PDF_PREVIEW_POPUP;
          var frame = popup ? null : doc.createElement('iframe');
          var viewer = null, popupTimer = null;
          var sent = false;
          if (frame) {
            frame.setAttribute('title', 'PDFプレビュー');
            frame.setAttribute('sandbox', 'allow-scripts');
            frame.style.cssText = 'width:100%;height:100%;border:0;display:block';
          }
          body.style.cssText = 'position:relative;overflow:hidden;flex:1;min-height:0;padding:0';
          status.style.cssText = 'position:absolute;z-index:1;top:0;left:0;right:0;text-align:center;pointer-events:none';
          zoomOut.hidden = zoomIn.hidden = true;
          function onViewerMessage(event) {
            if (closed || pdfStopped || event.source !== viewer) return;
            if (event.data === 'mbg-preview-ready' && !sent) {
              sent = true;
              armWatchdog();
              viewer.postMessage(bytes, '*', [bytes]);
              bytes = null;
            } else if (event.data === 'mbg-preview-password-requested' && sent) {
              if (watchdog) { window.clearTimeout(watchdog); watchdog = null; }
              status.textContent = '';
            } else if (event.data === 'mbg-preview-password-finished' && sent) {
              armWatchdog();
            } else if (event.data === 'mbg-preview-loaded' && sent) {
              if (watchdog) { window.clearTimeout(watchdog); watchdog = null; }
              status.textContent = popup ? 'PDFプレビューを別のウィンドウで表示中です' : '';
            } else if (event.data === 'mbg-preview-failed') {
              fail(new Error('PDFを開けません'));
            }
          }
          sourceWindow.addEventListener('message', onViewerMessage);
          pdfViewerCleanup = function() {
            sourceWindow.removeEventListener('message', onViewerMessage);
            if (popupTimer) window.clearInterval(popupTimer);
            if (frame) frame.remove();
            else if (viewer) { try { viewer.close(); } catch (_) {} }
            previewFrame = null;
            bytes = null;
          };
          if (popup) {
            viewer = sourceWindow.open(window.__MBG_PDF_PREVIEW_URL, '_blank');
            if (!viewer) { fail(new Error('PDFプレビューを開けません')); return null; }
            if (!preview.visible) mbgPreviewReport('hidden');
            popupTimer = window.setInterval(function() {
              try { if (viewer.closed) cleanup(); } catch (_) { cleanup(); }
            }, 500);
          } else {
            previewFrame = frame;
            resizeToolbar();
            frame.src = window.__MBG_PDF_PREVIEW_URL;
            body.appendChild(frame);
            viewer = frame.contentWindow;
          }
          return null;
        }
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
      zoomOut.hidden = zoomIn.hidden = true;
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
        enableVisualZoom(pre, true);
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
        enableVisualZoom(pre, true);
      };
      reader.onerror = function() { reader = null; fail(new Error('テキストを読み込めません')); };
      reader.onabort = function() { reader = null; };
      reader.readAsArrayBuffer(file);
    } else {
      status.textContent = 'この形式のプレビューには対応していません。';
    }
    function setZoom(value) {
      if (pdf) return;
      zoom = Math.max(25, Math.min(500, value));
      if (visual) {
        if (textZoom) visual.style.fontSize = zoom + '%';
        else visual.style.width = zoom + '%';
        imageZoomLabel.textContent = Math.round(zoom) + '%';
      }
    }
    zoomOut.addEventListener('click', function() { setZoom(zoom / 1.2); });
    zoomIn.addEventListener('click', function() { setZoom(zoom * 1.2); });
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
        button.setAttribute('data-mbg-upload-preview', 'true');
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
              choice.setAttribute('data-mbg-upload-preview', 'true');
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
