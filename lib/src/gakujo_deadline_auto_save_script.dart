/// Presses Gakujo's 「確定保存」 button shortly before a report deadline when
/// the student has already entered an answer or chosen a file, so a finished
/// but unconfirmed submission is not lost to the deadline.
///
/// The user gets a cancellable countdown first, and the script acts at most
/// once per page and deadline.
class GakujoDeadlineAutoSaveScript {
  const GakujoDeadlineAutoSaveScript._();

  static const leadTime = Duration(minutes: 5);
  static const countdown = Duration(seconds: 30);

  static String build() {
    return '''
(function() {
  var version = 1;
  var leadMs = ${leadTime.inMilliseconds};
  var countdownMs = ${countdown.inMilliseconds};
'''
        r'''
  window.__MBG_AUTO_SAVE_ENABLED = true;
  if (window.__MBG_AUTO_SAVE_VERSION === version) {
    if (window.__MBG_AUTO_SAVE_UPDATE) {
      window.__MBG_AUTO_SAVE_UPDATE();
    }
    return;
  }
  window.__MBG_AUTO_SAVE_VERSION = version;

  var buttonPattern = /^\s*確定保存\s*$/;
  // Ordered by how specifically each label names the submission deadline.
  var deadlineLabels = [
    /提出期間|提出期限|提出締切|Submission period|Deadline/i,
    /締切日時|締め切り|受付期間|回答期間/
  ];
  var handled = {};
  var pending = null;

  function documents() {
    var result = [document];
    var frames = document.querySelectorAll('iframe,frame');
    for (var i = 0; i < frames.length; i += 1) {
      try {
        if (frames[i].contentWindow && frames[i].contentWindow.document) {
          result.push(frames[i].contentWindow.document);
        }
      } catch (e) {
        // Cross-origin frames cannot be inspected.
      }
    }
    return result;
  }

  function halfWidth(text) {
    return String(text || '')
      .replace(/[０-９：／]/g, function(ch) {
        return String.fromCharCode(ch.charCodeAt(0) - 0xFEE0);
      })
      .replace(/[〜～]/g, '~');
  }

  function textOf(element) {
    return element ? String(element.innerText || element.textContent || '') : '';
  }

  // Returns the latest date-time that follows a deadline label, which is the
  // end of a "start ～ end" submission period.
  function parseDeadline(rawText) {
    var text = halfWidth(rawText);
    for (var i = 0; i < deadlineLabels.length; i += 1) {
      var label = deadlineLabels[i].exec(text);
      if (!label) {
        continue;
      }
      var deadline = latestDateTime(text.slice(label.index, label.index + 160));
      if (deadline) {
        return deadline;
      }
    }
    return null;
  }

  function latestDateTime(text) {
    var pattern = /(\d{4})\s*[\/年.\-]\s*(\d{1,2})\s*[\/月.\-]\s*(\d{1,2})\s*日?\s*(?:[(（][^)）]{1,3}[)）])?\s*(\d{1,2})\s*[:時]\s*(\d{2})/g;
    var latest = null;
    var match;
    while ((match = pattern.exec(text)) !== null) {
      // Date rolls 24:00 over to 00:00 of the next day.
      var date = new Date(
        Number(match[1]), Number(match[2]) - 1, Number(match[3]),
        Number(match[4]), Number(match[5])
      );
      if (!isNaN(date.getTime()) && (!latest || date > latest)) {
        latest = date;
      }
    }
    return latest;
  }

  function visible(element) {
    if (!element || element.disabled) {
      return false;
    }
    var view = element.ownerDocument.defaultView;
    var style = view && view.getComputedStyle ? view.getComputedStyle(element) : null;
    if (style && (style.display === 'none' || style.visibility === 'hidden')) {
      return false;
    }
    return !element.getClientRects || element.getClientRects().length > 0;
  }

  function finalSaveButton(doc) {
    var candidates = doc.querySelectorAll(
      'button,input[type="button"],input[type="submit"],a'
    );
    for (var i = 0; i < candidates.length; i += 1) {
      var candidate = candidates[i];
      var label = candidate.tagName === 'INPUT' ? candidate.value : textOf(candidate);
      if (buttonPattern.test(label || '') && visible(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  // Only press when the student has entered something; confirming an empty
  // form would submit a blank answer.
  function hasAnswer(doc) {
    var fields = doc.querySelectorAll('textarea,input[type="file"],[contenteditable="true"]');
    for (var i = 0; i < fields.length; i += 1) {
      var field = fields[i];
      if (field.tagName === 'INPUT') {
        if (field.files && field.files.length > 0) {
          return true;
        }
      } else if (String(field.value !== undefined ? field.value : textOf(field)).trim()) {
        return true;
      }
    }
    return false;
  }

  function keyFor(doc, deadline) {
    var url = '';
    try {
      url = String(doc.location && doc.location.href || '').split('#')[0];
    } catch (e) {
      url = '';
    }
    return url + '|' + deadline.getTime();
  }

  function wasHandled(doc, key) {
    if (handled[key]) {
      return true;
    }
    try {
      return window.sessionStorage.getItem('mbg-auto-save:' + key) === '1';
    } catch (e) {
      return false;
    }
  }

  function markHandled(key) {
    handled[key] = true;
    try {
      window.sessionStorage.setItem('mbg-auto-save:' + key, '1');
    } catch (e) {
      // The in-memory marker still prevents a second press on this page.
    }
  }

  function removeBanner() {
    if (pending && pending.banner && pending.banner.remove) {
      pending.banner.remove();
    }
  }

  function cancelPending() {
    if (!pending) {
      return;
    }
    window.clearTimeout(pending.timer);
    window.clearInterval(pending.ticker);
    removeBanner();
    pending = null;
  }

  function press(doc, button) {
    var view = doc.defaultView || window;
    // A native confirm() would stop the automation at the last moment, so
    // accept only the confirmation raised synchronously by this click.
    var originalConfirm = view.confirm;
    try {
      view.confirm = function() {
        return true;
      };
      button.click();
    } finally {
      view.confirm = originalConfirm;
    }
  }

  function showBanner(doc, onNow, onCancel) {
    var banner = doc.createElement('div');
    banner.setAttribute('data-mbg-auto-save-owned', 'true');
    banner.setAttribute('role', 'alert');
    banner.style.cssText = 'position:fixed;left:8px;right:8px;bottom:8px;z-index:2147483647;' +
      'padding:10px 12px;background:#fff3e0;color:#5d4037;border:1px solid #ff9800;' +
      'border-radius:6px;font-size:14px;box-shadow:0 2px 8px rgba(0,0,0,.2);';
    var label = doc.createElement('span');
    var nowButton = doc.createElement('button');
    nowButton.type = 'button';
    nowButton.textContent = '今すぐ確定保存';
    nowButton.style.marginLeft = '8px';
    nowButton.addEventListener('click', onNow);
    var cancelButton = doc.createElement('button');
    cancelButton.type = 'button';
    cancelButton.textContent = 'キャンセル';
    cancelButton.style.marginLeft = '8px';
    cancelButton.addEventListener('click', onCancel);
    banner.appendChild(label);
    banner.appendChild(nowButton);
    banner.appendChild(cancelButton);
    (doc.body || doc.documentElement).appendChild(banner);
    return { banner: banner, label: label };
  }

  function check() {
    if (!window.__MBG_AUTO_SAVE_ENABLED) {
      cancelPending();
      return;
    }
    if (pending) {
      if (!pending.button.isConnected) {
        // The page moved on (for example the student saved manually).
        cancelPending();
      }
      return;
    }
    var now = Date.now();
    var docs = documents();
    for (var i = 0; i < docs.length; i += 1) {
      var doc = docs[i];
      var button = finalSaveButton(doc);
      if (!button) {
        continue;
      }
      var deadline = parseDeadline(textOf(doc.body));
      if (!deadline) {
        continue;
      }
      var remaining = deadline.getTime() - now;
      var key = keyFor(doc, deadline);
      if (remaining <= 0 || remaining > leadMs || wasHandled(doc, key) ||
          !hasAnswer(doc)) {
        continue;
      }
      schedule(doc, button, key);
      return;
    }
  }

  function schedule(doc, button, key) {
    var fireAt = Date.now() + countdownMs;
    function fire() {
      var target = pending;
      cancelPending();
      if (!target || !window.__MBG_AUTO_SAVE_ENABLED || !target.button.isConnected) {
        return;
      }
      markHandled(key);
      press(doc, target.button);
    }
    var ui = showBanner(doc, fire, function() {
      markHandled(key);
      cancelPending();
    });
    function tick() {
      var seconds = Math.max(0, Math.ceil((fireAt - Date.now()) / 1000));
      ui.label.textContent = '提出期限が迫っています。' + seconds +
        '秒後に「確定保存」を自動で押します。';
    }
    pending = {
      button: button,
      banner: ui.banner,
      timer: window.setTimeout(fire, countdownMs),
      ticker: window.setInterval(tick, 1000)
    };
    tick();
  }

  window.__MBG_AUTO_SAVE_UPDATE = check;
  window.__MBG_AUTO_SAVE_PARSE_DEADLINE = parseDeadline;
  window.__MBG_AUTO_SAVE_CANCEL = cancelPending;
  window.__MBG_AUTO_SAVE_INTERVAL = window.setInterval(check, 15000);
  check();
})();
''';
  }

  static String buildTeardown() {
    return r'''
(function() {
  window.__MBG_AUTO_SAVE_ENABLED = false;
  if (window.__MBG_AUTO_SAVE_CANCEL) {
    window.__MBG_AUTO_SAVE_CANCEL();
  }
})();
''';
  }
}
