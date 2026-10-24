class GakujoExpiredPageRecoveryScript {
  const GakujoExpiredPageRecoveryScript._();

  static String build() {
    return r'''
(function() {
  function isExpired(doc) {
    if (!doc) {
      return false;
    }
    var pattern = /ページの有効期限(ぎれ|切れ)/;
    if (pattern.test(doc.title || '')) {
      return true;
    }
    var body = doc.body;
    var text = body && (body.innerText || body.textContent || '') || '';
    return text.length < 300 && text.indexOf('ページの有効期限が過ぎています') >= 0;
  }

  function shouldRecover(target) {
    var key = '__MBG_EXPIRED_RECOVERY';
    var now = Date.now();
    var previous = null;
    try {
      previous = JSON.parse(sessionStorage.getItem(key) || 'null');
    } catch (e) {}
    if (previous && previous.target === target && now - previous.at < 10000) {
      return false;
    }
    try {
      sessionStorage.setItem(key, JSON.stringify({target: target, at: now}));
    } catch (e) {}
    return true;
  }

  function recoverFrame(frame) {
    try {
      if (!isExpired(frame.contentDocument || frame.contentWindow.document)) {
        return;
      }
      var src = frame.getAttribute('src');
      if (!src) {
        return;
      }
      var target = new URL(src, location.href);
      if (target.origin !== location.origin ||
          target.href.indexOf('_flowExecutionKey=') >= 0) {
        return;
      }
      if (shouldRecover(target.href)) {
        frame.contentWindow.location.replace(target.href);
      }
    } catch (e) {}
  }

  try {
    var frame = document.getElementById('main-frame-if');
    if (frame) {
      if (!frame.__MBG_EXPIRED_RECOVERY_ATTACHED) {
        frame.addEventListener('load', function() {
          recoverFrame(frame);
        });
        frame.__MBG_EXPIRED_RECOVERY_ATTACHED = true;
      }
      recoverFrame(frame);
    } else if (isExpired(document)) {
      var target = location.origin + '/campusweb/campusportal.do?page=main';
      if (shouldRecover(target)) {
        location.replace(target);
      }
    }
  } catch (e) {}
})();
''';
  }
}
