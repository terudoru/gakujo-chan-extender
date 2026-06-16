class DesktopPageFitScript {
  const DesktopPageFitScript._();

  static String build() {
    return '''
(function() {
  var version = 1;
  if (window.__MBG_DESKTOP_PAGE_FIT_VERSION === version) {
    if (window.__MBG_FIT_DESKTOP_PAGE) {
      window.__MBG_FIT_DESKTOP_PAGE();
    }
    return;
  }
  window.__MBG_DESKTOP_PAGE_FIT_VERSION = version;
  window.clearTimeout(window.__MBG_DESKTOP_PAGE_FIT_TIMER);

  function measureContentWidth() {
    var body = document.body;
    var doc = document.documentElement;
    if (!body || !doc) {
      return window.innerWidth || 0;
    }
    return Math.max(
      body.scrollWidth || 0,
      body.offsetWidth || 0,
      doc.scrollWidth || 0,
      doc.offsetWidth || 0,
      window.innerWidth || 0
    );
  }

  function fit() {
    var body = document.body;
    var doc = document.documentElement;
    if (!body || !doc || !window.innerWidth) {
      return;
    }

    body.style.zoom = '';
    doc.style.zoom = '';
    body.style.minWidth = '';
    body.style.overflowX = '';

    var contentWidth = measureContentWidth();
    var viewportWidth = window.innerWidth;
    var scale = Math.min(1, viewportWidth / contentWidth);
    if (!isFinite(scale) || scale >= 0.98) {
      return;
    }

    var percent = Math.max(55, Math.floor(scale * 100));
    body.style.zoom = percent + '%';
    body.style.minWidth = Math.ceil(viewportWidth / scale) + 'px';
    body.style.overflowX = 'hidden';
  }

  window.__MBG_FIT_DESKTOP_PAGE = fit;
  window.addEventListener('resize', fit);
  fit();
  window.__MBG_DESKTOP_PAGE_FIT_TIMER = window.setTimeout(fit, 500);
})();
''';
  }
}
