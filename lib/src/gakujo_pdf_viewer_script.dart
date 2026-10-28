/// Offline PDF.js viewer controls, kept inside the preview lifecycle.
class GakujoPdfViewerScript {
  const GakujoPdfViewerScript._();

  static const source = r'''
  function mbgPreviewGestures(node, callbacks) {
    var start = null, pinch = null, pending = null, frame = null;
    node.style.touchAction = 'pan-y';
    function distance(a, b) { return Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY); }
    function centre(a, b) { return {x:(a.clientX+b.clientX)/2, y:(a.clientY+b.clientY)/2}; }
    function applyScale(value, point) {
      var old = callbacks.getScale();
      if (!Number.isFinite(old) || old <= 0 || !Number.isFinite(value)) return;
      var next = Math.max(callbacks.min, Math.min(callbacks.max, value));
      var rect = node.getBoundingClientRect(), x = point.x - rect.left, y = point.y - rect.top;
      var left = node.scrollLeft, top = node.scrollTop;
      callbacks.setScale(next);
      node.scrollLeft = (left + x) * next / old - x;
      node.scrollTop = (top + y) * next / old - y;
    }
    function flush() {
      frame = null;
      if (pending) { var value = pending; pending = null; applyScale(value.scale, value.point); }
    }
    function onStart(event) {
      if (event.target && event.target.closest && event.target.closest('a,button,input,textarea,select,audio,video')) return;
      if (event.touches.length === 2) {
        var length = distance(event.touches[0], event.touches[1]);
        pinch = length > 0 ? {distance:length, scale:callbacks.getScale()} : null; start = null;
      } else if (event.touches.length === 1) {
        var touch = event.touches[0];
        start = {x:touch.clientX, y:touch.clientY, time:Date.now()}; pinch = null;
      }
    }
    function onMove(event) {
      if (!pinch || event.touches.length !== 2) return;
      if (event.cancelable) event.preventDefault();
      pending = {scale:pinch.scale * distance(event.touches[0], event.touches[1]) / pinch.distance,
        point:centre(event.touches[0], event.touches[1])};
      if (frame === null) frame = window.requestAnimationFrame(flush);
    }
    function onEnd(event) {
      if (pinch) {
        if (frame !== null) { window.cancelAnimationFrame(frame); frame = null; }
        if (pending) flush();
        if (event.touches.length < 2) { pinch = null; start = null; }
        return;
      }
      if (!start || event.touches.length || !event.changedTouches.length) return;
      var touch = event.changedTouches[0], dx = touch.clientX-start.x, dy = touch.clientY-start.y;
      if (Date.now()-start.time < 900 && Math.abs(dx) >= 80 && Math.abs(dx) > Math.abs(dy)*1.5) {
        if (dx < 0 && callbacks.next) callbacks.next();
        else if (dx > 0 && callbacks.previous) callbacks.previous();
      }
      start = null;
    }
    function onCancel() {
      start = pinch = pending = null;
      if (frame !== null) { window.cancelAnimationFrame(frame); frame = null; }
    }
    function onWheel(event) {
      if (!event.ctrlKey && !event.metaKey) return;
      if (event.cancelable) event.preventDefault();
      var multiplier = Math.max(0.75, Math.min(1.33, Math.exp(-event.deltaY * 0.01)));
      applyScale(callbacks.getScale()*multiplier, {x:event.clientX, y:event.clientY});
    }
    node.addEventListener('touchstart', onStart, {passive:true});
    node.addEventListener('touchmove', onMove, {passive:false});
    node.addEventListener('touchend', onEnd, {passive:true});
    node.addEventListener('touchcancel', onCancel, {passive:true});
    node.addEventListener('wheel', onWheel, {passive:false});
    return function() {
      onCancel();
      node.removeEventListener('touchstart', onStart); node.removeEventListener('touchmove', onMove);
      node.removeEventListener('touchend', onEnd); node.removeEventListener('touchcancel', onCancel);
      node.removeEventListener('wheel', onWheel);
    };
  }
  function mbgCreatePdfViewer(doc, body, bar, status, pdf, previous, next, count, zoomOut, zoomIn, onFirstPage) {
    var host = doc.createElement('div');
    host.style.cssText = 'position:absolute;inset:0';
    var root = host.attachShadow({mode:'closed'});
    var style = doc.createElement('style'); style.textContent = window.__MBG_PDF_VIEWER_CSS;
    var container = doc.createElement('div');
    container.style.cssText = 'position:absolute;inset:0;overflow:auto;background:#e5e5e5';
    var pages = doc.createElement('div'); pages.className = 'pdfViewer';
    container.appendChild(pages); root.append(style, container); body.appendChild(host);
    body.style.cssText = 'position:relative;flex:1;min-height:0';
    bar.appendChild(status); status.style.cssText = 'font-size:12px;margin:0;color:#555';
    status.textContent = 'ページを読み込み中…';
    var search = doc.createElement('input'); search.type = 'search'; search.placeholder = '文書内を検索';
    search.setAttribute('aria-label', '文書内を検索'); search.maxLength = 256;
    var findPrevious = doc.createElement('button'); findPrevious.type = 'button'; findPrevious.textContent = '前の検索結果';
    var findNext = doc.createElement('button'); findNext.type = 'button'; findNext.textContent = '次の検索結果';
    var matches = doc.createElement('span'); matches.setAttribute('aria-live', 'polite');
    var pageInput = doc.createElement('input'); pageInput.type = 'number'; pageInput.min = '1';
    pageInput.max = String(pdf.numPages); pageInput.style.cssText = 'width:4.5em';
    pageInput.setAttribute('aria-label', 'ページ番号');
    var go = doc.createElement('button'); go.type = 'button'; go.textContent = 'ページ移動';
    var zoomLabel = doc.createElement('span'); zoomLabel.setAttribute('aria-label', '表示倍率');
    var fit = doc.createElement('button'); fit.type = 'button'; fit.textContent = '幅に合わせる';
    bar.insertBefore(pageInput, zoomOut); bar.insertBefore(go, zoomOut);
    bar.insertBefore(search, zoomOut); bar.insertBefore(findPrevious, zoomOut);
    bar.insertBefore(findNext, zoomOut); bar.insertBefore(matches, zoomOut);
    bar.insertBefore(zoomLabel, zoomOut); bar.insertBefore(fit, zoomOut);
    var events = new window.pdfjsViewer.EventBus();
    var links = new window.pdfjsViewer.PDFLinkService({eventBus: events});
    links.externalLinkEnabled = false;
    var finder = new window.pdfjsViewer.PDFFindController({eventBus: events, linkService: links});
    var viewer = new window.pdfjsViewer.PDFViewer({container: container, viewer: pages,
      eventBus: events, linkService: links, findController: finder,
      // Annotation icons must never resolve against the university page or an
      // address supplied by a PDF. The fragment absorbs PDF.js's icon name.
      imageResourcesPath: 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="20" height="20"%3E%3Ccircle cx="10" cy="10" r="7" fill="%23555"/%3E%3C/svg%3E#',
      annotationMode: window.pdfjsLib.AnnotationMode.ENABLE, maxCanvasPixels: 2000000});
    links.setViewer(viewer); links.setDocument(pdf, null); finder.setDocument(pdf);
    function updatePage() {
      var current = viewer.currentPageNumber || 1;
      count.textContent = current + ' / ' + pdf.numPages;
      pageInput.value = String(current);
      previous.disabled = current <= 1; next.disabled = current >= pdf.numPages;
    }
    events.on('pagesinit', function() { viewer.currentScaleValue = 'page-width'; updatePage(); });
    events.on('pagechanging', updatePage);
    events.on('scalechanging', function(event) { zoomLabel.textContent = Math.round(event.scale * 100) + '%'; });
    events.on('pagerendered', function(event) {
      if (event.error) {
        status.textContent = /maximum allowed size/i.test(String(event.error.message || event.error))
          ? '画像が大きすぎるため、このページを表示できません' : 'ページを表示できません';
      } else { status.textContent = '大きな画像は表示されない場合があります'; }
      onFirstPage();
    });
    function updateMatches(event) {
      var value = event.matchesCount || {};
      matches.textContent = search.value ? (value.current || 0) + ' / ' + (value.total || 0) : '';
    }
    var alternatives = [], alternative = 0;
    events.on('updatefindmatchescount', updateMatches);
    events.on('updatefindcontrolstate', function(event) {
      // Some producers store right-to-left text in visual order or map Arabic
      // and Persian letter variants differently. Retry only after no match.
      if (event.rawQuery === alternatives[alternative] && event.state === 1 &&
          alternative + 1 < alternatives.length) {
        alternative++; dispatchFind(false, false); return;
      }
      updateMatches(event);
    });
    function searchAlternatives(query) {
      if (!/[\u0590-\u08ff\ufb1d-\ufeff]/.test(query)) return [query];
      var forms = [query, query.replace(/[يى]/g, 'ی').replace(/ك/g, 'ک'),
        query.replace(/ی/g, 'ي').replace(/ک/g, 'ك')];
      var result = [];
      forms.forEach(function(form) {
        var units;
        if (typeof Intl !== 'undefined' && Intl.Segmenter) {
          units = Array.from(new Intl.Segmenter(undefined, {granularity:'grapheme'}).segment(form), function(x) { return x.segment; });
        } else { units = Array.from(form); }
        [form, units.reverse().join('')].forEach(function(value) {
          if (result.indexOf(value) < 0) result.push(value);
        });
      });
      return result;
    }
    function dispatchFind(again, backwards) {
      events.dispatch('find', {source: search, type: again ? 'again' : '', query: alternatives[alternative],
        caseSensitive: false, entireWord: false, highlightAll: true,
        findPrevious: backwards, matchDiacritics: false});
    }
    function find(again, backwards) {
      if (!again || !alternatives.length) { alternatives = searchAlternatives(search.value); alternative = 0; }
      dispatchFind(again, backwards);
    }
    search.addEventListener('input', function() { find(false, false); });
    search.addEventListener('keydown', function(event) {
      if (event.key === 'Enter') { event.preventDefault(); find(true, !!event.shiftKey); }
    });
    bar.parentNode.addEventListener('keydown', function(event) {
      if ((event.ctrlKey || event.metaKey) && String(event.key).toLowerCase() === 'f') {
        event.preventDefault(); search.focus();
      }
    });
    function goToPage() {
      var page = Number(pageInput.value);
      if (Number.isInteger(page) && page >= 1 && page <= pdf.numPages) viewer.currentPageNumber = page;
      else updatePage();
    }
    pageInput.addEventListener('keydown', function(event) { if (event.key === 'Enter') { event.preventDefault(); goToPage(); } });
    go.addEventListener('click', goToPage);
    findPrevious.addEventListener('click', function() { find(true, true); });
    findNext.addEventListener('click', function() { find(true, false); });
    previous.addEventListener('click', function() { if (viewer.currentPageNumber > 1) viewer.currentPageNumber--; });
    next.addEventListener('click', function() { if (viewer.currentPageNumber < pdf.numPages) viewer.currentPageNumber++; });
    zoomOut.addEventListener('click', function() { viewer.currentScale = Math.max(0.25, viewer.currentScale / 1.25); });
    zoomIn.addEventListener('click', function() { viewer.currentScale = Math.min(4, viewer.currentScale * 1.25); });
    fit.addEventListener('click', function() { viewer.currentScaleValue = 'page-width'; });
    var removeGestures = mbgPreviewGestures(container, {
      min:0.25, max:4, getScale:function() { return viewer.currentScale; },
      setScale:function(value) { viewer.currentScale = value; },
      previous:function() { if (viewer.currentPageNumber > 1) viewer.currentPageNumber--; },
      next:function() { if (viewer.currentPageNumber < pdf.numPages) viewer.currentPageNumber++; }
    });
    previous.hidden = next.hidden = false; updatePage();
    viewer.setDocument(pdf);
    return function() {
      removeGestures();
      try { viewer.setDocument(null); links.setDocument(null, null); } catch (_) {}
      host.remove();
    };
  }
''';
}
