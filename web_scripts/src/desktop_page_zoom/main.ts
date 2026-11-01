export {};

declare const __mbgConfig: { zoom: number; originX: number | null; originY: number | null };

function desktopPageZoom() {
  var version = 6;
  var initialZoom = __mbgConfig.zoom;
  var initialOrigin = {
    x: __mbgConfig.originX,
    y: __mbgConfig.originY
  };

  function clamp(value: number) {
    if (!isFinite(value)) {
      return 1;
    }
    return Math.max(0.5, Math.min(2, value));
  }

  function allWindows() {
    var windows: (Window & typeof globalThis)[] = [];
    function collect(win: Window & typeof globalThis) {
      try {
        if (!win || !win.document) {
          return;
        }
        windows.push(win);
        for (var i = 0; i < win.frames.length; i += 1) {
          collect(win.frames[i] as Window & typeof globalThis);
        }
      } catch (e) {}
    }
    collect(window);
    return windows;
  }

  function measuredSize(win: Window & typeof globalThis) {
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

  function fitScaleFor(win: Window & typeof globalThis, size: { width: number; height: number }) {
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

  function effectiveZoomFor(win: Window & typeof globalThis, zoom: number, size: { width: number; height: number }) {
    var baseScale = fitScaleFor(win, size);
    var effectiveZoom = zoom * baseScale;
    if (!isFinite(effectiveZoom)) {
      effectiveZoom = 1;
    }
    window.__MBG_PAGE_ZOOM_BASE_SCALE = baseScale;
    return Math.max(0.25, Math.min(2, effectiveZoom));
  }

  function originFor(win: Window & typeof globalThis) {
    var origin = window.__MBG_PAGE_ZOOM_ORIGIN || initialOrigin || {};
    var x = origin.x == null ? NaN : Number(origin.x);
    var y = origin.y == null ? NaN : Number(origin.y);
    if (!isFinite(x) || !isFinite(y)) {
      x = (win.innerWidth || 0) / 2;
      y = (win.innerHeight || 0) / 2;
    }
    return {
      x: Math.max(0, x),
      y: Math.max(0, y)
    };
  }

  function applyZoom(win: Window & typeof globalThis, zoom: number) {
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

      // Measuring temporarily removes the transform and minimum dimensions.
      // The browser can clamp the scroll position during that reflow, so the
      // visible position must be captured before measurement starts.
      var previousScrollX = win.scrollX || win.pageXOffset || 0;
      var previousScrollY = win.scrollY || win.pageYOffset || 0;
      var bounds = body.getBoundingClientRect ? body.getBoundingClientRect() : null;
      var bodyOriginX = bounds ? bounds.left + previousScrollX : 0;
      var bodyOriginY = bounds ? bounds.top + previousScrollY : 0;
      var size = measuredSize(win);
      var effectiveZoom = effectiveZoomFor(win, zoom, size);
      var previousZoom = win.__MBG_PAGE_EFFECTIVE_ZOOM as number;
      if (!isFinite(previousZoom) || previousZoom <= 0) previousZoom = 1;
      var origin = originFor(win);
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
      if (isFinite(previousZoom) && previousZoom > 0) {
        var contentX = (previousScrollX + origin.x - bodyOriginX) / previousZoom;
        var contentY = (previousScrollY + origin.y - bodyOriginY) / previousZoom;
        var nextScrollX = Math.max(0, bodyOriginX + contentX * effectiveZoom - origin.x);
        var nextScrollY = Math.max(0, bodyOriginY + contentY * effectiveZoom - origin.y);
        if (Math.abs((win.scrollX || 0) - nextScrollX) > 0.5 ||
            Math.abs((win.scrollY || 0) - nextScrollY) > 0.5) {
          win.scrollTo(nextScrollX, nextScrollY);
        }
      }
    } catch (e) {}
  }

  function applyEverywhere(zoom: number) {
    applyZoom(window, zoom);
  }

  function setZoom(nextZoom: number) {
    var zoom = clamp(nextZoom);
    window.__MBG_PAGE_ZOOM_VALUE = zoom;
    window.__MBG_PAGE_ZOOM_ORIGIN = initialOrigin;
    applyEverywhere(zoom);
    return zoom;
  }

  function scheduleReapply(win: Window & typeof globalThis) {
    try {
      win.clearTimeout(win.__MBG_PAGE_ZOOM_REAPPLY_TIMER);
      win.__MBG_PAGE_ZOOM_REAPPLY_TIMER = win.setTimeout(function() {
        var apply = window.__MBG_SET_PAGE_ZOOM || setZoom;
        apply(window.__MBG_PAGE_ZOOM_VALUE || initialZoom);
      }, 150);
    } catch (e) {}
  }

  function attachNativeZoomBlockers() {
    var wins = allWindows();
    for (var i = 0; i < wins.length; i += 1) {
      try {
        (function(win: Window & typeof globalThis) {
          if (win.__MBG_NATIVE_ZOOM_BLOCKERS_ATTACHED) {
            return;
          }
          win.__MBG_NATIVE_ZOOM_BLOCKERS_ATTACHED = true;
          win.addEventListener('keydown', function(event) {
            if (!event.metaKey && !event.ctrlKey) {
              return;
            }
            var action = event.key === '+' || event.key === '=' ? 'in' :
              event.key === '-' || event.key === '_' ? 'out' :
              event.key === '0' ? 'reset' : null;
            if (!action) {
              return;
            }
            event.preventDefault();
            try {
              window.MoreBetterGakujoDesktopZoom.postMessage(action);
            } catch (e) {}
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
}

desktopPageZoom();
