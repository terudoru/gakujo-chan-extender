class DesktopPageZoomScript {
  const DesktopPageZoomScript._();

  static String build(double zoom) {
    final encodedZoom = zoom.clamp(0.5, 2.0).toStringAsFixed(2);
    return '''
(function() {
  var version = 1;
  var initialZoom = $encodedZoom;

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

  function applyZoom(win, zoom) {
    try {
      var doc = win.document.documentElement;
      if (!doc) {
        return;
      }
      if (Math.abs(zoom - 1) < 0.001) {
        doc.style.zoom = '';
        doc.style.transformOrigin = '';
      } else {
        doc.style.zoom = Math.round(zoom * 100) + '%';
        doc.style.transformOrigin = '0 0';
      }
    } catch (e) {}
  }

  function applyEverywhere(zoom) {
    var wins = allWindows();
    for (var i = 0; i < wins.length; i += 1) {
      applyZoom(wins[i], zoom);
    }
    if (window.__MBG_REFLOW_WEB_VIEW) {
      window.__MBG_REFLOW_WEB_VIEW();
    }
  }

  function setZoom(nextZoom) {
    var zoom = clamp(nextZoom);
    window.__MBG_PAGE_ZOOM_VALUE = zoom;
    applyEverywhere(zoom);
    return zoom;
  }

  function stepZoom(delta) {
    return setZoom((window.__MBG_PAGE_ZOOM_VALUE || 1) + delta);
  }

  function attachInputHandlers() {
    var wins = allWindows();
    for (var i = 0; i < wins.length; i += 1) {
      try {
        if (wins[i].__MBG_PAGE_ZOOM_INPUT_HANDLERS_ATTACHED) {
          continue;
        }
        wins[i].__MBG_PAGE_ZOOM_INPUT_HANDLERS_ATTACHED = true;
        wins[i].addEventListener('keydown', function(event) {
          if (!event.metaKey && !event.ctrlKey) {
            return;
          }
          if (event.key === '+' || event.key === '=') {
            event.preventDefault();
            stepZoom(0.1);
          } else if (event.key === '-' || event.key === '_') {
            event.preventDefault();
            stepZoom(-0.1);
          } else if (event.key === '0') {
            event.preventDefault();
            setZoom(1);
          }
        }, true);

        wins[i].addEventListener('wheel', function(event) {
          if (!event.metaKey && !event.ctrlKey) {
            return;
          }
          event.preventDefault();
          stepZoom(event.deltaY < 0 ? 0.1 : -0.1);
        }, { capture: true, passive: false });
      } catch (e) {}
    }
  }

  if (window.__MBG_PAGE_ZOOM_VERSION !== version) {
    window.__MBG_PAGE_ZOOM_VERSION = version;
    window.__MBG_SET_PAGE_ZOOM = setZoom;
    window.__MBG_STEP_PAGE_ZOOM = stepZoom;
  } else {
    window.__MBG_SET_PAGE_ZOOM = setZoom;
    window.__MBG_STEP_PAGE_ZOOM = stepZoom;
  }

  attachInputHandlers();
  setZoom(initialZoom);
})();
''';
  }
}
