class WebViewReflowScript {
  const WebViewReflowScript._();

  static String build() {
    return '''
(function() {
  var version = 1;
  if (window.__MBG_WEB_VIEW_REFLOW_VERSION === version) {
    if (window.__MBG_REFLOW_WEB_VIEW) {
      window.__MBG_REFLOW_WEB_VIEW();
    }
    return;
  }
  window.__MBG_WEB_VIEW_REFLOW_VERSION = version;

  function forceReflow() {
    var body = document.body;
    var doc = document.documentElement;
    if (!body || !doc) {
      return;
    }

    doc.style.webkitTextSizeAdjust = '100%';
    doc.style.textSizeAdjust = '100%';
    body.style.webkitTextSizeAdjust = '100%';
    body.style.textSizeAdjust = '100%';

    var previousTransform = body.style.webkitTransform;
    body.style.webkitTransform = 'translateZ(0)';
    void body.offsetHeight;
    window.requestAnimationFrame(function() {
      body.style.webkitTransform = previousTransform;
      void doc.offsetWidth;
    });
  }

  function scheduleReflow() {
    window.clearTimeout(window.__MBG_WEB_VIEW_REFLOW_TIMER);
    window.__MBG_WEB_VIEW_REFLOW_TIMER = window.setTimeout(forceReflow, 80);
  }

  window.__MBG_REFLOW_WEB_VIEW = forceReflow;
  window.addEventListener('resize', scheduleReflow, { passive: true });
  window.addEventListener('orientationchange', scheduleReflow, { passive: true });
  window.addEventListener('pageshow', scheduleReflow, { passive: true });
  window.addEventListener('touchend', scheduleReflow, { passive: true });
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', scheduleReflow, {
      passive: true
    });
    window.visualViewport.addEventListener('scroll', scheduleReflow, {
      passive: true
    });
  }
  scheduleReflow();
})();
''';
  }
}
