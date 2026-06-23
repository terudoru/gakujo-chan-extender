class GakujoSessionExtenderScript {
  const GakujoSessionExtenderScript._();

  static String build() {
    return r'''
(function() {
  var version = 1;
  if (window.__MBG_SESSION_EXTENDER_VERSION === version) {
    return;
  }
  window.__MBG_SESSION_EXTENDER_VERSION = version;
  window.clearInterval(window.__MBG_SESSION_EXTENDER_INTERVAL);
  window.__MBG_SESSION_EXTENDER_COUNT = 0;
  window.__MBG_SESSION_EXTENDER_URL = location.href;

  function remainingMinutes() {
    var timer = document.getElementById('timeout-timer');
    if (!timer) {
      return NaN;
    }
    var match = (timer.textContent || '').match(/\d+/);
    return match ? Number(match[0]) : NaN;
  }

  function extendIfNeeded() {
    if (window.__MBG_SESSION_EXTENDER_URL !== location.href) {
      window.__MBG_SESSION_EXTENDER_URL = location.href;
      window.__MBG_SESSION_EXTENDER_COUNT = 0;
    }
    if (window.__MBG_SESSION_EXTENDER_COUNT >= 10) {
      return;
    }

    var minutes = remainingMinutes();
    var button = document.getElementById('portaltimerimg');
    if (!isFinite(minutes) || minutes > 11 || !button) {
      return;
    }

    button.click();
    window.__MBG_SESSION_EXTENDER_COUNT += 1;
  }

  window.__MBG_SESSION_EXTENDER_INTERVAL =
    window.setInterval(extendIfNeeded, 60000);
  extendIfNeeded();
})();
''';
  }
}
