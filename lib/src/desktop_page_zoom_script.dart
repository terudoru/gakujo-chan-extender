class DesktopPageZoomScript {
  const DesktopPageZoomScript._();

  static String build(double zoom, {double? originX, double? originY}) {
    final encodedZoom = zoom.clamp(0.5, 2.0).toStringAsFixed(2);
    final encodedOriginX = originX?.toStringAsFixed(1) ?? 'null';
    final encodedOriginY = originY?.toStringAsFixed(1) ?? 'null';
    return '''
(function() {
  var version = 5;
  var initialZoom = $encodedZoom;
  var initialOrigin = {
    x: $encodedOriginX,
    y: $encodedOriginY
  };

  function clamp(value) {
    if (!isFinite(value)) {
      return 1;
    }
    return Math.max(0.5, Math.min(2, value));
  }

  function allWindows() {
    var windows = [];
    function collect(win) {
      try {
        if (!win || !win.document) {
          return;
        }
        windows.push(win);
        for (var i = 0; i < win.frames.length; i += 1) {
          collect(win.frames[i]);
        }
      } catch (e) {}
    }
    collect(window);
    return windows;
  }

  function measuredSize(win) {
    var doc = win.document;
    var body = doc.body;
    var element = doc.documentElement;
    var previousTransform = body.style.transform;
    var previousBodyMinWidth = body.style.minWidth;
    var previousBodyMinHeight = body.style.minHeight;
    var previousElementMinWidth = element.style.minWidth;
    var previousElementMinHeight = element.style.minHeight;
    body.style.transform = 'none';
    body.style.minWidth = '';
    body.style.minHeight = '';
    element.style.minWidth = '';
    element.style.minHeight = '';
    var width = Math.max(
      body.scrollWidth || 0,
      body.offsetWidth || 0,
      element.scrollWidth || 0,
      element.offsetWidth || 0,
      win.innerWidth || 0
    );
    var height = Math.max(
      body.scrollHeight || 0,
      body.offsetHeight || 0,
      element.scrollHeight || 0,
      element.offsetHeight || 0,
      win.innerHeight || 0
    );
    body.style.transform = previousTransform;
    body.style.minWidth = previousBodyMinWidth;
    body.style.minHeight = previousBodyMinHeight;
    element.style.minWidth = previousElementMinWidth;
    element.style.minHeight = previousElementMinHeight;
    return { width: width, height: height };
  }

  function fitScaleFor(win, size) {
    var doc = win.document;
    var element = doc && doc.documentElement;
    var viewportWidth = (element && element.clientWidth) || win.innerWidth || 0;
    if (!viewportWidth || !size.width) {
      return 1;
    }

    var scale = viewportWidth / size.width;
    if (!isFinite(scale)) {
      return 1;
    }
    return Math.max(0.5, Math.min(1, scale));
  }

  function effectiveZoomFor(win, zoom, size) {
    var baseScale = fitScaleFor(win, size);
    var effectiveZoom = zoom * baseScale;
    if (!isFinite(effectiveZoom)) {
      effectiveZoom = 1;
    }
    window.__MBG_PAGE_ZOOM_BASE_SCALE = baseScale;
    return Math.max(0.25, Math.min(2, effectiveZoom));
  }

  function originFor(win) {
    var origin = window.__MBG_PAGE_ZOOM_ORIGIN || initialOrigin || {};
    var x = Number(origin.x);
    var y = Number(origin.y);
    if (!isFinite(x) || !isFinite(y)) {
      x = (win.innerWidth || 0) / 2;
      y = (win.innerHeight || 0) / 2;
    }
    return {
      x: Math.max(0, x),
      y: Math.max(0, y)
    };
  }

  function applyZoom(win, zoom) {
    try {
      var doc = win.document;
      var body = doc && doc.body;
      var element = doc && doc.documentElement;
      if (!body || !element) {
        return;
      }

      body.style.zoom = '';
      element.style.zoom = '';
      body.style.webkitTextSizeAdjust = '100%';
      body.style.textSizeAdjust = '100%';
      element.style.webkitTextSizeAdjust = '100%';
      element.style.textSizeAdjust = '100%';

      var size = measuredSize(win);
      var effectiveZoom = effectiveZoomFor(win, zoom, size);
      var previousZoom = win.__MBG_PAGE_EFFECTIVE_ZOOM;
      var origin = originFor(win);
      var previousScrollX = win.scrollX || win.pageXOffset || 0;
      var previousScrollY = win.scrollY || win.pageYOffset || 0;
      if (Math.abs(effectiveZoom - 1) < 0.001) {
        body.style.transform = '';
        body.style.transformOrigin = '';
        body.style.minWidth = '';
        body.style.minHeight = '';
        body.style.overflow = '';
        element.style.minWidth = '';
        element.style.minHeight = '';
      } else {
        body.style.transformOrigin = '0 0';
        body.style.transform = 'scale(' + effectiveZoom + ')';
        element.style.minWidth = Math.ceil(size.width * effectiveZoom) + 'px';
        element.style.minHeight = Math.ceil(size.height * effectiveZoom) + 'px';
        body.style.overflow = 'auto';
      }
      win.__MBG_PAGE_EFFECTIVE_ZOOM = effectiveZoom;
      if (isFinite(previousZoom) && previousZoom > 0 &&
          Math.abs(previousZoom - effectiveZoom) > 0.0001) {
        var contentX = (previousScrollX + origin.x) / previousZoom;
        var contentY = (previousScrollY + origin.y) / previousZoom;
        var nextScrollX = Math.max(0, contentX * effectiveZoom - origin.x);
        var nextScrollY = Math.max(0, contentY * effectiveZoom - origin.y);
        win.scrollTo(nextScrollX, nextScrollY);
      }
    } catch (e) {}
  }

  function applyEverywhere(zoom) {
    applyZoom(window, zoom);
  }

  function setZoom(nextZoom) {
    var zoom = clamp(nextZoom);
    window.__MBG_PAGE_ZOOM_VALUE = zoom;
    window.__MBG_PAGE_ZOOM_ORIGIN = initialOrigin;
    applyEverywhere(zoom);
    return zoom;
  }

  function scheduleReapply(win) {
    try {
      win.clearTimeout(win.__MBG_PAGE_ZOOM_REAPPLY_TIMER);
      win.__MBG_PAGE_ZOOM_REAPPLY_TIMER = win.setTimeout(function() {
        setZoom(window.__MBG_PAGE_ZOOM_VALUE || initialZoom);
      }, 150);
    } catch (e) {}
  }

  function attachNativeZoomBlockers() {
    var wins = allWindows();
    for (var i = 0; i < wins.length; i += 1) {
      try {
        (function(win) {
          if (win.__MBG_NATIVE_ZOOM_BLOCKERS_ATTACHED) {
            return;
          }
          win.__MBG_NATIVE_ZOOM_BLOCKERS_ATTACHED = true;
          win.addEventListener('keydown', function(event) {
            if (!event.metaKey && !event.ctrlKey) {
              return;
            }
            if (event.key === '+' || event.key === '=' ||
                event.key === '-' || event.key === '_' ||
                event.key === '0') {
              event.preventDefault();
            }
          }, true);

          win.addEventListener('wheel', function(event) {
            if (!event.metaKey && !event.ctrlKey) {
              return;
            }
            event.preventDefault();
          }, { capture: true, passive: false });

          win.addEventListener('resize', function() {
            scheduleReapply(win);
          }, true);

          if (win.MutationObserver && win.document && win.document.body) {
            win.__MBG_PAGE_ZOOM_OBSERVER = new win.MutationObserver(function(mutations) {
              for (var m = 0; m < mutations.length; m += 1) {
                if (mutations[m].type === 'attributes' &&
                    mutations[m].attributeName === 'style') {
                  continue;
                }
                scheduleReapply(win);
                return;
              }
            });
            win.__MBG_PAGE_ZOOM_OBSERVER.observe(win.document.body, {
              attributes: true,
              childList: true,
              subtree: true
            });
          }
        })(wins[i]);
      } catch (e) {}
    }
  }

  if (window.__MBG_PAGE_ZOOM_VERSION !== version) {
    window.__MBG_PAGE_ZOOM_VERSION = version;
    window.__MBG_SET_PAGE_ZOOM = setZoom;
  } else {
    window.__MBG_SET_PAGE_ZOOM = setZoom;
  }

  attachNativeZoomBlockers();
  setZoom(initialZoom);
})();
''';
  }
}
