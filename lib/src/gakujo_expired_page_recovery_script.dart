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

  var key = '__MBG_EXPIRED_RECOVERY';

  function readHistory() {
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
    return history;
  }

  function writeHistory(history) {
    window[key] = history;
    try {
      window.top[key] = history;
    } catch (e) {}
    try {
      sessionStorage.setItem(key, JSON.stringify(history));
    } catch (e) {}
  }

  // A page that loaded normally ends any recovery streak for its scope, so
  // repeated Back presses during ordinary use are never capped.
  function clearScope(scope) {
    var history = readHistory();
    var changed = false;
    Object.keys(history).forEach(function(entry) {
      if (entry.indexOf(JSON.stringify([scope]).slice(0, -1) + ',') === 0) {
        delete history[entry];
        changed = true;
      }
    });
    if (changed) writeHistory(history);
  }

  function shouldRecover(target, scope) {
    var now = Date.now();
    var history = readHistory();
    var entryKey = JSON.stringify([scope, target]);
    var previous = history[entryKey];
    var attempts = previous && Array.isArray(previous.attempts)
      ? previous.attempts.filter(function(at) { return now - at < 120000; }) : [];
    if (attempts.length >= 3 ||
        (previous && now - previous.at < 10000)) {
      return false;
    }
    history[entryKey] = {target: target, at: now, attempts: attempts.concat(now)};
    Object.keys(history).forEach(function(entry) {
      if (!history[entry] || typeof history[entry].at !== 'number' ||
          now - history[entry].at >= 120000) {
        delete history[entry];
      }
    });
    var keys = Object.keys(history).sort(function(a, b) {
      return history[a].at - history[b].at;
    });
    keys.slice(0, Math.max(0, keys.length - 20)).forEach(function(entry) {
      delete history[entry];
    });
    writeHistory(history);
    return true;
  }

  function recoverFrame(frame) {
    try {
      var frameDocument = frame.contentDocument || frame.contentWindow.document;
      if (!isExpired(frameDocument)) {
        var href = '';
        try {
          href = frameDocument.location.href;
        } catch (e) {}
        if (frameDocument.readyState !== 'loading' && href !== 'about:blank') {
          clearScope('iframe');
        }
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
      clearScope('top');
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
    } else {
      clearScope('top');
    }
  } catch (e) {}
})();
''';
  }
}
