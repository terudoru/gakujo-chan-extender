class GakujoReportDraftScript {
  const GakujoReportDraftScript._();

  static String build() {
    return r'''
(function() {
  var version = 6;
  var prefix = 'mbg-report-draft:v1:';
  var retentionMs = 14 * 24 * 60 * 60 * 1000;
  if (window.__MBG_REPORT_DRAFT_VERSION === version) {
    if (window.__MBG_REPORT_DRAFT_UPDATE) {
      window.__MBG_REPORT_DRAFT_UPDATE();
    }
    return;
  }
  window.__MBG_REPORT_DRAFT_VERSION = version;

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

  function compactText(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }

  function storageFor(doc) {
    try {
      return doc.defaultView.localStorage || window.localStorage;
    } catch (e) {
      try {
        return window.localStorage;
      } catch (_) {
        return null;
      }
    }
  }

  function visible(element) {
    if (!element || element.disabled || element.readOnly) {
      return false;
    }
    var style = element.ownerDocument.defaultView.getComputedStyle(element);
    if (style.display === 'none' || style.visibility === 'hidden') {
      return false;
    }
    return element.getClientRects().length > 0;
  }

  function isIgnoredInput(input) {
    var type = (input.getAttribute('type') || 'text').toLowerCase();
    if ([
      'button', 'checkbox', 'color', 'file', 'hidden', 'image', 'password',
      'radio', 'range', 'reset', 'submit'
    ].indexOf(type) >= 0) {
      return true;
    }
    var metadata = [
      input.getAttribute('name'),
      input.getAttribute('id'),
      input.getAttribute('autocomplete'),
      input.getAttribute('aria-label')
    ].join(' ').toLowerCase();
    return metadata.indexOf('password') >= 0 ||
      metadata.indexOf('login') >= 0 ||
      metadata.indexOf('userid') >= 0 ||
      metadata.indexOf('username') >= 0 ||
      metadata.indexOf('ninshocode') >= 0;
  }

  function saveableFields(doc) {
    var fields = Array.prototype.slice.call(
      doc.querySelectorAll('textarea,input,[contenteditable]')
    ).filter(function(field) {
      if (!visible(field)) {
        return false;
      }
      if (field.matches('[contenteditable]')) {
        return field.getAttribute('contenteditable') !== 'false';
      }
      if (field.tagName.toLowerCase() === 'textarea') {
        return true;
      }
      return field.tagName.toLowerCase() === 'input' && !isIgnoredInput(field);
    });
    return fields;
  }

  function pageTextWithoutFields(doc) {
    if (!doc.body) {
      return '';
    }
    var clone = doc.body.cloneNode(true);
    Array.prototype.slice.call(
      clone.querySelectorAll(
        'textarea,input,select,button,[contenteditable],#mbg-report-draft-status'
      )
    ).forEach(function(node) {
      node.remove();
    });
    return compactText(clone.innerText || clone.textContent || '');
  }

  function stablePageTextForKey(doc) {
    return pageTextWithoutFields(doc)
      .replace(/残り約\s*[0-9０-９]+\s*分/g, '')
      .replace(/前回ログイン日時[:：]?\s*[0-9０-９]{4}年[0-9０-９]{1,2}月[0-9０-９]{1,2}日\s*[0-9０-９]{1,2}時[0-9０-９]{1,2}分/g, '')
      .replace(/[0-9０-９]{4}年[0-9０-９]{1,2}月[0-9０-９]{1,2}日\s*[0-9０-９]{1,2}時[0-9０-９]{1,2}分/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function looksLikeReportSubmission(doc, fields) {
    if (!fields.length) {
      return false;
    }
    var url = '';
    try {
      url = doc.location.href || '';
    } catch (e) {
      url = '';
    }
    var hasDraftWorthyField = fields.some(function(field) {
      if (field.matches('[contenteditable]')) {
        return true;
      }
      var tagName = field.tagName.toLowerCase();
      if (tagName === 'textarea') {
        return true;
      }
      if (tagName !== 'input') {
        return false;
      }
      return /本文|コメント|回答|解答|内容|理由|備考/.test(labelFor(field));
    });
    if (!hasDraftWorthyField) {
      return false;
    }
    var text = compactText((doc.title || '') + ' ' + pageTextWithoutFields(doc));
    var reportContext =
      text.indexOf('レポート・小テスト・アンケート提出') >= 0 ||
      /レポート提出(?!日)/.test(text) ||
      /小テスト(?:提出(?!日)|回答|解答)/.test(text) ||
      /アンケート(?:提出(?!期限)|回答)/.test(text) ||
      /report|enq|questionnaire/i.test(url);
    var submissionContext =
      /提出(?!日|期限)/.test(text) ||
      text.indexOf('回答') >= 0 ||
      text.indexOf('解答') >= 0 ||
      text.indexOf('入力') >= 0 ||
      text.indexOf('本文') >= 0 ||
      text.indexOf('コメント') >= 0;
    return reportContext && submissionContext;
  }

  function labelFor(field) {
    var doc = field.ownerDocument;
    var labels = [
      field.getAttribute('name'),
      field.getAttribute('id'),
      field.getAttribute('aria-label'),
      field.getAttribute('title'),
      field.getAttribute('placeholder')
    ];
    if (field.id && doc.defaultView.CSS && doc.defaultView.CSS.escape) {
      var label = doc.querySelector(
        'label[for="' + doc.defaultView.CSS.escape(field.id) + '"]'
      );
      if (label) {
        labels.push(label.innerText || label.textContent || '');
      }
    }
    var row = field.closest('tr,div,p,li,section');
    if (row) {
      var rowClone = row.cloneNode(true);
      Array.prototype.slice.call(
        rowClone.querySelectorAll('textarea,input,select,button,[contenteditable]')
      ).forEach(function(node) {
        node.remove();
      });
      labels.push(rowClone.innerText || rowClone.textContent || '');
    }
    return compactText(labels.filter(Boolean).join(' ')).substring(0, 120);
  }

  function fieldKey(field, index) {
    return [
      field.tagName.toLowerCase(),
      (field.getAttribute('type') || '').toLowerCase(),
      labelFor(field),
      index
    ].join('|');
  }

  function fieldValue(field) {
    if (field.matches('[contenteditable]')) {
      return typeof field.innerText === 'string'
        ? field.innerText
        : (field.textContent || '');
    }
    return field.value || '';
  }

  function setContentEditableText(field, value) {
    var doc = field.ownerDocument;
    var lines = String(value || '').split(/\r\n?|\n/);
    field.textContent = '';
    for (var i = 0; i < lines.length; i += 1) {
      if (i > 0) {
        field.appendChild(doc.createElement('br'));
      }
      if (lines[i]) {
        field.appendChild(doc.createTextNode(lines[i]));
      }
    }
  }

  function setFieldValue(field, value) {
    var win = field.ownerDocument.defaultView || window;
    if (field.matches('[contenteditable]')) {
      setContentEditableText(field, value);
    } else {
      var proto = field.tagName.toLowerCase() === 'textarea'
        ? win.HTMLTextAreaElement.prototype
        : win.HTMLInputElement.prototype;
      var descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
      if (descriptor && descriptor.set) {
        descriptor.set.call(field, value);
      } else {
        field.value = value;
      }
    }
    try {
      field.dispatchEvent(new win.InputEvent('input', {
        bubbles: true,
        inputType: 'insertReplacementText',
        data: value
      }));
    } catch (e) {
      field.dispatchEvent(new win.Event('input', { bubbles: true }));
    }
    field.dispatchEvent(new win.Event('change', { bubbles: true }));
  }

  function hashString(text) {
    var hash = 2166136261;
    for (var i = 0; i < text.length; i += 1) {
      hash ^= text.charCodeAt(i);
      hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
    }
    return (hash >>> 0).toString(36);
  }

  function draftKey(doc, fields) {
    var path = '';
    try {
      path = doc.location.pathname || '';
    } catch (e) {
      path = '';
    }
    var signature = [
      path,
      doc.title || '',
      stablePageTextForKey(doc).substring(0, 4000),
      fields.map(labelFor).join('|')
    ].join('\n');
    return prefix + hashString(signature);
  }

  function readDraft(store, key) {
    if (!store) {
      return null;
    }
    try {
      var raw = store.getItem(key);
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      return null;
    }
  }

  function writeDraft(store, key, payload) {
    if (!store) {
      return false;
    }
    try {
      store.setItem(key, JSON.stringify(payload));
      return true;
    } catch (e) {
      return false;
    }
  }

  function removeDraft(store, key) {
    if (!store) {
      return false;
    }
    try {
      store.removeItem(key);
      return true;
    } catch (e) {
      return false;
    }
  }

  function cleanup(store) {
    if (!store) {
      return;
    }
    var now = Date.now();
    try {
      for (var i = store.length - 1; i >= 0; i -= 1) {
        var key = store.key(i);
        if (!key || key.indexOf(prefix) !== 0) {
          continue;
        }
        var draft = readDraft(store, key);
        if (!draft || !draft.savedAt || now - draft.savedAt > retentionMs) {
          store.removeItem(key);
        }
      }
    } catch (e) {
      // Ignore storage iteration failures.
    }
  }

  function ensureStatus(doc, store, key) {
    var status = doc.getElementById('mbg-report-draft-status');
    if (status) {
      status.__MBG_REPORT_DRAFT_STORE = store;
      status.__MBG_REPORT_DRAFT_KEY = key;
      return status;
    }
    var firstField = saveableFields(doc)[0];
    if (!firstField) {
      return null;
    }
    status = doc.createElement('div');
    status.id = 'mbg-report-draft-status';
    status.style.margin = '8px 0';
    status.style.padding = '6px 8px';
    status.style.border = '1px solid #8eb79a';
    status.style.background = '#eef8f0';
    status.style.color = '#234231';
    status.style.fontSize = '12px';
    status.style.display = 'flex';
    status.style.gap = '8px';
    status.style.alignItems = 'center';

    var label = doc.createElement('span');
    label.id = 'mbg-report-draft-status-label';
    label.textContent = '入力すると下書きを保存します';
    status.appendChild(label);

    var clearButton = doc.createElement('button');
    clearButton.type = 'button';
    clearButton.textContent = '下書きを削除';
    clearButton.style.fontSize = '12px';
    function clearStoredDraft() {
      var deleted = removeDraft(
        status.__MBG_REPORT_DRAFT_STORE,
        status.__MBG_REPORT_DRAFT_KEY
      );
      if (!deleted) {
        updateStatus(doc, '下書きを削除できませんでした', clearStoredDraft);
        return;
      }
      var win = doc.defaultView;
      var key = status.__MBG_REPORT_DRAFT_KEY;
      var suppressed = win.__MBG_REPORT_DRAFT_DELETED_KEYS ||
        (win.__MBG_REPORT_DRAFT_DELETED_KEYS = Object.create(null));
      suppressed[key] = true;
      var pending = win.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
      if (pending && pending.key === key) {
        win.clearTimeout(win.__MBG_REPORT_DRAFT_SAVE_TIMER);
        delete win.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
      }
      saveableFields(doc).forEach(function(field) {
        field.__MBG_REPORT_DRAFT_DIRTY = false;
      });
      updateStatus(doc, '下書きを削除しました');
    }
    clearButton.addEventListener('click', clearStoredDraft);
    var retryButton = doc.createElement('button');
    retryButton.id = 'mbg-report-draft-retry';
    retryButton.type = 'button';
    retryButton.textContent = '再試行';
    retryButton.style.display = 'none';
    retryButton.addEventListener('click', function() {
      if (status.__MBG_REPORT_DRAFT_RETRY) status.__MBG_REPORT_DRAFT_RETRY();
    });
    status.appendChild(clearButton);
    status.appendChild(retryButton);
    status.__MBG_REPORT_DRAFT_STORE = store;
    status.__MBG_REPORT_DRAFT_KEY = key;

    var form = firstField.closest('form');
    var anchor = form || firstField;
    anchor.parentNode.insertBefore(status, anchor);
    return status;
  }

  function removeStatus(doc) {
    var status = doc.getElementById('mbg-report-draft-status');
    if (status) {
      status.remove();
    }
  }

  function updateStatus(doc, text, retry) {
    var label = doc.getElementById('mbg-report-draft-status-label');
    if (label) {
      label.textContent = text;
    }
    var status = doc.getElementById('mbg-report-draft-status');
    var retryButton = doc.getElementById('mbg-report-draft-retry');
    if (status) status.__MBG_REPORT_DRAFT_RETRY = retry || null;
    if (retryButton) retryButton.style.display = retry ? '' : 'none';
  }

  function collectValues(fields) {
    return fields.map(function(field, index) {
      return {
        key: fieldKey(field, index),
        value: fieldValue(field)
      };
    });
  }

  function saveDraft(doc, store, key, fields) {
    var suppressed = doc.defaultView.__MBG_REPORT_DRAFT_DELETED_KEYS;
    if (suppressed && suppressed[key]) return true;
    store = store || storageFor(doc);
    var values = collectValues(fields);
    var hasContent = values.some(function(item) {
      return compactText(item.value).length > 0;
    });
    var saved = hasContent ? writeDraft(store, key, {
      savedAt: Date.now(),
      title: doc.title || '',
      url: (doc.location && doc.location.href) || '',
      fields: values
    }) : removeDraft(store, key);
    if (!saved) {
      updateStatus(doc, '下書きを保存できませんでした。入力内容をコピーして保管してください', function() {
        saveCurrentDraft(doc);
      });
      return false;
    }
    fields.forEach(function(field) {
      field.__MBG_REPORT_DRAFT_DIRTY = false;
    });
    updateStatus(doc, hasContent ? '下書きを保存しました' : '下書きは空です');
    return true;
  }

  function restoreDraft(doc, store, key, fields) {
    var draft = readDraft(store, key);
    if (!draft || !Array.isArray(draft.fields)) {
      return;
    }
    var byKey = {};
    draft.fields.forEach(function(item) {
      byKey[item.key] = item.value || '';
    });
    var restored = false;
    fields.forEach(function(field, index) {
      var value = byKey[fieldKey(field, index)];
      if (!value || field.__MBG_REPORT_DRAFT_DIRTY ||
          compactText(fieldValue(field)).length > 0) {
        return;
      }
      setFieldValue(field, value);
      restored = true;
    });
    if (restored) {
      ensureStatus(doc, store, key);
      updateStatus(doc, '保存済みの下書きを復元しました');
    }
  }

  function currentDraftContext(doc) {
    var fields = saveableFields(doc);
    if (!looksLikeReportSubmission(doc, fields)) {
      return null;
    }
    var store = storageFor(doc);
    return {
      fields: fields,
      store: store,
      key: draftKey(doc, fields)
    };
  }

  function saveCurrentDraft(doc) {
    var context = doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT ||
      currentDraftContext(doc);
    if (!context) {
      return;
    }
    if (saveDraft(doc, context.store, context.key, context.fields)) {
      if (doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT === context) {
        delete doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
      }
    } else {
      doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT = context;
    }
  }

  function bindDraft(doc) {
    var context = currentDraftContext(doc);
    if (!context) {
      removeStatus(doc);
      return false;
    }
    var fields = context.fields;
    var store = context.store;
    cleanup(store);
    var key = context.key;
    ensureStatus(doc, store, key);
    restoreDraft(doc, store, key, fields);

    function scheduleSave(field) {
      field.__MBG_REPORT_DRAFT_DIRTY = true;
      var pendingContext = currentDraftContext(doc);
      if (!pendingContext) {
        return;
      }
      var suppressed = doc.defaultView.__MBG_REPORT_DRAFT_DELETED_KEYS;
      if (suppressed) delete suppressed[pendingContext.key];
      var pendingFields = pendingContext.fields.slice();
      var pendingStore = pendingContext.store;
      var pendingKey = pendingContext.key;
      var pendingSnapshot = {
        fields: pendingFields,
        store: pendingStore,
        key: pendingKey
      };
      doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT = pendingSnapshot;
      doc.defaultView.clearTimeout(doc.defaultView.__MBG_REPORT_DRAFT_SAVE_TIMER);
      doc.defaultView.__MBG_REPORT_DRAFT_SAVE_TIMER = doc.defaultView.setTimeout(function() {
        if (doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT !== pendingSnapshot) return;
        var saved = saveDraft(doc, pendingStore, pendingKey, pendingFields);
        if (saved && doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT ===
            pendingSnapshot) {
          delete doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
        }
      }, 250);
    }

    fields.forEach(function(field) {
      if (field.__MBG_REPORT_DRAFT_BOUND) {
        return;
      }
      field.__MBG_REPORT_DRAFT_BOUND = true;
      field.addEventListener('input', function() { scheduleSave(field); });
      field.addEventListener('change', function() { scheduleSave(field); });
      field.addEventListener('keyup', function() { scheduleSave(field); });
    });

    Array.prototype.slice.call(doc.querySelectorAll('form')).forEach(function(form) {
      if (form.__MBG_REPORT_DRAFT_BOUND) {
        return;
      }
      form.__MBG_REPORT_DRAFT_BOUND = true;
      form.addEventListener('submit', function() {
        saveCurrentDraft(doc);
      }, true);
    });

    if (!doc.defaultView.__MBG_REPORT_DRAFT_BEFORE_UNLOAD_BOUND) {
      doc.defaultView.__MBG_REPORT_DRAFT_BEFORE_UNLOAD_BOUND = true;
      doc.defaultView.addEventListener('beforeunload', function() {
        saveCurrentDraft(doc);
      });
      doc.defaultView.addEventListener('pagehide', function() {
        saveCurrentDraft(doc);
      });
      doc.addEventListener('visibilitychange', function() {
        if (doc.visibilityState === 'hidden') {
          saveCurrentDraft(doc);
        }
      });
    }
    return true;
  }

  function apply() {
    var docs = documents();
    var applied = false;
    for (var i = 0; i < docs.length; i += 1) {
      try {
        applied = bindDraft(docs[i]) || applied;
      } catch (e) {
        // Keep other frames working even if one page shape is unexpected.
      }
    }
    return applied;
  }

  window.__MBG_REPORT_DRAFT_UPDATE = apply;
  apply();
  window.clearInterval(window.__MBG_REPORT_DRAFT_INTERVAL);
  window.__MBG_REPORT_DRAFT_INTERVAL = window.setInterval(apply, 1000);
})();
''';
  }
}
