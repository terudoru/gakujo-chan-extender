class GakujoExpiredPageRecoveryScript {
  const GakujoExpiredPageRecoveryScript._();

  static String build() {
    return r'''
(function() {
  function isExpired(doc) {
    if (!doc) {
      return false;
    }
    var fields = doc.querySelectorAll('textarea, input, [contenteditable]');
    for (var i = 0; i < fields.length; i++) {
      var field = fields[i];
      var tag = field.tagName.toLowerCase();
      if (tag === 'input' &&
          !/^(text|search|email|url|tel|password|number)$/.test(field.type || 'text')) {
        continue;
      }
      var value = tag === 'input' || tag === 'textarea'
        ? field.value : (field.innerText || field.textContent || '');
      if (value && (tag !== 'input' || value !== field.defaultValue)) {
        return false;
      }
    }
    var pattern = /ページの有効期限(ぎれ|切れ)/;
    if (pattern.test(doc.title || '')) {
      return true;
    }
    var body = doc.body;
    var text = body && (body.innerText || body.textContent || '') || '';
    return text.length < 300 && text.indexOf('ページの有効期限が過ぎています') >= 0;
  }

  function shouldRecover(target, scope) {
    var key = '__MBG_EXPIRED_RECOVERY';
    var now = Date.now();
    var history = null;
    try {
      history = JSON.parse(sessionStorage.getItem(key) || 'null');
    } catch (e) {}
    history = window[key] || history;
    try {
      history = window.top[key] || history;
    } catch (e) {}
    if (!history || typeof history !== 'object' || Array.isArray(history)) {
      history = {};
    }
    var previous = history[scope];
    var attempts = previous && Array.isArray(previous.attempts)
      ? previous.attempts.filter(function(at) { return now - at < 120000; }) : [];
    if (attempts.length >= 3 ||
        (previous && previous.target === target && now - previous.at < 10000)) {
      return false;
    }
    history[scope] = {target: target, at: now, attempts: attempts.concat(now)};
    window[key] = history;
    try {
      window.top[key] = history;
    } catch (e) {}
    try {
      sessionStorage.setItem(key, JSON.stringify(history));
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
      if (shouldRecover(target.href, 'iframe')) {
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
      if (shouldRecover(target, 'top')) {
        location.replace(target);
      }
    }
  } catch (e) {}
})();
''';
  }
}
