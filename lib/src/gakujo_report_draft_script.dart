import 'dart:convert';

class GakujoReportDraftScript {
  const GakujoReportDraftScript._();

  static String build() {
    return r'''
(function() {
  var version = 9;
  var prefix = 'mbg-report-draft:v2:';
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
      'button', 'color', 'file', 'hidden', 'image', 'password',
      'range', 'reset', 'submit'
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
      doc.querySelectorAll('textarea,input,select,[contenteditable]')
    ).filter(function(field) {
      if (!visible(field)) {
        return false;
      }
      if (field.matches('[contenteditable]')) {
        return field.getAttribute('contenteditable') !== 'false';
      }
      // Web Flow controls such as the list's _displayCount are not answers.
      if (/^_/.test(field.getAttribute('name') || '')) {
        return false;
      }
      return !isIgnoredInput(field);
    });
    return fields;
  }

  function stripCounters(text) {
    return compactText(String(text || '')
      .replace(/入力文字数[:：]?\s*[0-9０-９]+\s*\/\s*[0-9０-９]+\s*文字?/g, '')
      .replace(/[0-9０-９]+\s*\/\s*[0-9０-９]+\s*文字/g, ''));
  }

  function removeCounterElements(root) {
    Array.prototype.slice.call(root.querySelectorAll('[id],[class]'))
      .forEach(function(node) {
        if (/count/i.test((node.getAttribute('id') || '') + ' ' +
            (node.getAttribute('class') || ''))) node.remove();
      });
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
    removeCounterElements(clone);
    return compactText(clone.innerText || clone.textContent || '');
  }

  function stablePageTextForKey(doc) {
    return stripCounters(pageTextWithoutFields(doc))
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
      if (tagName === 'textarea' || fieldKind(field) !== 'text') {
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
      removeCounterElements(rowClone);
      labels.push(rowClone.innerText || rowClone.textContent || '');
    }
    return stripCounters(labels.filter(Boolean).join(' ')).substring(0, 120);
  }

  function fieldKind(field) {
    if (field.tagName.toLowerCase() === 'select') return 'select';
    var type = (field.getAttribute('type') || '').toLowerCase();
    return type === 'radio' || type === 'checkbox' ? type : 'text';
  }

  function fieldIdentity(field) {
    var identity = field.getAttribute('name') || field.id || labelFor(field);
    return fieldKind(field) === 'checkbox'
      ? identity + '=' + field.value : identity;
  }

  function fieldKey(field, index, fields) {
    var identity = fieldIdentity(field);
    var occurrence = fields.slice(0, index).filter(function(other) {
      return fieldIdentity(other) === identity;
    }).length;
    return [
      field.tagName.toLowerCase(),
      (field.getAttribute('type') || '').toLowerCase(),
      identity,
      occurrence
    ].join('|');
  }

  function radioGroup(field, fields) {
    var name = field.getAttribute('name');
    return name ? fields.filter(function(other) {
      return fieldKind(other) === 'radio' &&
        other.getAttribute('name') === name && other.form === field.form;
    }) : [field];
  }

  function fieldValue(field) {
    if (field.matches('[contenteditable]')) {
      return typeof field.innerText === 'string'
        ? field.innerText
        : (field.textContent || '');
    }
    if (fieldKind(field) === 'checkbox') return field.checked;
    if (fieldKind(field) === 'select') {
      return Array.prototype.slice.call(field.options).filter(function(option) {
        return option.selected;
      }).map(function(option) { return option.value; });
    }
    return field.value || '';
  }

  function isDefaultChoice(field) {
    if (fieldKind(field) === 'checkbox') {
      return field.checked === field.defaultChecked;
    }
    var options = Array.prototype.slice.call(field.options);
    var defaults = options.filter(function(option) { return option.defaultSelected; });
    if (!field.multiple) {
      defaults = defaults.length ? defaults.slice(-1) : options.filter(function(option) {
        return !option.disabled && !(option.parentNode && option.parentNode.disabled);
      }).slice(0, field.size > 1 ? 0 : 1);
    }
    return options.every(function(option) {
      return option.selected === (defaults.indexOf(option) >= 0);
    });
  }

  function observedFieldValue(field) {
    return JSON.stringify(fieldKind(field) === 'radio' ? field.checked : fieldValue(field));
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
    } else if (fieldKind(field) === 'checkbox' || fieldKind(field) === 'radio') {
      field.checked = value;
    } else if (fieldKind(field) === 'select') {
      Array.prototype.slice.call(field.options).forEach(function(option) {
        option.selected = value.indexOf(option.value) >= 0;
      });
      if (!value.length) field.selectedIndex = -1;
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
        data: typeof value === 'string' ? value : null
      }));
    } catch (e) {
      field.dispatchEvent(new win.Event('input', { bubbles: true }));
    }
    field.dispatchEvent(new win.Event('change', { bubbles: true }));
    field.__MBG_REPORT_DRAFT_LAST_VALUE = observedFieldValue(field);
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
    var identities = fields.map(function(field, index) {
      return fieldKey(field, index, fields);
    }).sort().join('\n');
    var cached = doc.__MBG_REPORT_DRAFT_IDENTITY;
    if (cached && cached.signature === identities &&
        cached.fields.length === fields.length &&
        cached.fields.every(function(field, index) { return field === fields[index]; })) {
      return cached.key;
    }
    var path = '';
    try {
      path = doc.location.pathname || '';
    } catch (e) {
      path = '';
    }
    var signature = [
      path,
      doc.title || '',
      stablePageTextForKey(doc),
      identities
    ].join('\n');
    var key = prefix + hashString(signature);
    doc.__MBG_REPORT_DRAFT_IDENTITY = {
      signature: identities, fields: fields.slice(), key: key
    };
    return key;
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
        if (!key || !/^mbg-report-draft:v[12]:/.test(key)) {
          continue;
        }
        var draft = readDraft(store, key);
        if (!draft || typeof draft.savedAt !== 'number' ||
            !isFinite(draft.savedAt) || !draft.savedAt ||
            !Array.isArray(draft.fields) || now - draft.savedAt > retentionMs) {
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
      if (status.__MBG_REPORT_DRAFT_KEY !== key) {
        updateStatus(doc, '入力すると下書きを保存します');
      }
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
    status.style.flexWrap = 'wrap';

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
        delete field.__MBG_REPORT_DRAFT_CONFLICT;
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
    var replaceButton = doc.createElement('button');
    replaceButton.id = 'mbg-report-draft-replace';
    replaceButton.type = 'button';
    replaceButton.textContent = '下書きで置き換える';
    replaceButton.style.display = 'none';
    replaceButton.addEventListener('click', function() {
      if (status.__MBG_REPORT_DRAFT_REPLACE) status.__MBG_REPORT_DRAFT_REPLACE();
    });
    status.appendChild(clearButton);
    status.appendChild(retryButton);
    status.appendChild(replaceButton);
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

  function updateStatus(doc, text, retry, replace) {
    var label = doc.getElementById('mbg-report-draft-status-label');
    if (label) {
      label.textContent = text;
    }
    var status = doc.getElementById('mbg-report-draft-status');
    var retryButton = doc.getElementById('mbg-report-draft-retry');
    var replaceButton = doc.getElementById('mbg-report-draft-replace');
    if (status) status.__MBG_REPORT_DRAFT_RETRY = retry || null;
    if (status) status.__MBG_REPORT_DRAFT_REPLACE = replace || null;
    if (retryButton) retryButton.style.display = retry ? '' : 'none';
    if (replaceButton) replaceButton.style.display = replace ? '' : 'none';
  }

  function savedTime(savedAt, withDate) {
    var date = new Date(savedAt);
    var time = ('0' + date.getHours()).slice(-2) + ':' +
      ('0' + date.getMinutes()).slice(-2);
    return withDate ? (date.getMonth() + 1) + '/' + date.getDate() + ' ' + time : time;
  }

  function headingFor(doc) {
    var values = {};
    Array.prototype.slice.call(doc.querySelectorAll('tr')).forEach(function(row) {
      var cells = Array.prototype.slice.call(row.children).filter(function(cell) {
        return /^(TH|TD)$/i.test(cell.tagName);
      });
      if (cells.length < 2) return;
      cells.forEach(function(cell, index) {
        if (index !== 0 && cell.tagName.toUpperCase() !== 'TH') return;
        var header = compactText(cell.innerText || cell.textContent);
        if (header === '科目名' || header === 'タイトル') {
          values[header] = compactText(cells.slice(index + 1).map(function(valueCell) {
            return valueCell.innerText || valueCell.textContent || '';
          }).join(' '));
        }
      });
    });
    return [values['科目名'], values['タイトル']].filter(Boolean).join(' / ') ||
      doc.title || '';
  }

  function collectValues(fields) {
    return fields.map(function(field, index) {
      var kind = fieldKind(field);
      var value = fieldValue(field);
      var group = kind === 'radio' ? radioGroup(field, fields) : [field];
      if (kind === 'radio' && group[0] !== field) return null;
      // An edit elsewhere must not replace an unresolved local answer.
      if (field.__MBG_REPORT_DRAFT_CONFLICT && !group.some(function(other) {
        return other.__MBG_REPORT_DRAFT_TOUCHED;
      })) return field.__MBG_REPORT_DRAFT_CONFLICT;
      delete field.__MBG_REPORT_DRAFT_CONFLICT;
      if (kind === 'radio') {
        var checked = group.filter(function(other) { return other.checked; })[0];
        value = checked ? checked.value : null;
      }
      return {
        key: fieldKey(field, index, fields),
        value: value,
        kind: kind
      };
    }).filter(Boolean);
  }

  function saveDraft(doc, store, key, fields) {
    var suppressed = doc.defaultView.__MBG_REPORT_DRAFT_DELETED_KEYS;
    if (suppressed && suppressed[key]) return true;
    store = store || storageFor(doc);
    var values = collectValues(fields);
    var hasContent = values.some(function(item) {
      return item.kind !== 'text' || compactText(item.value).length > 0;
    });
    var savedAt = Date.now();
    var saved = hasContent ? writeDraft(store, key, {
      savedAt: savedAt,
      title: doc.title || '',
      url: (doc.location && doc.location.href) || '',
      heading: headingFor(doc),
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
      field.__MBG_REPORT_DRAFT_LAST_VALUE = observedFieldValue(field);
    });
    updateStatus(doc, hasContent
      ? '下書きを保存しました（' + savedTime(savedAt, false) + '）' : '下書きは空です');
    if (fields.some(function(field) { return field.__MBG_REPORT_DRAFT_CONFLICT; })) {
      restoreDraft(doc, store, key, fields);
    }
    return true;
  }

  function restoreDraft(doc, store, key, fields, force) {
    var draft = readDraft(store, key);
    if (!draft || !Array.isArray(draft.fields)) {
      return;
    }
    var byKey = Object.create(null);
    draft.fields.forEach(function(item) {
      if (item) byKey[item.key] = item;
    });
    var restored = false;
    var conflict = false;
    doc.__MBG_REPORT_DRAFT_RESTORING = true;
    try {
      fields.forEach(function(field, index) {
        var item = byKey[fieldKey(field, index, fields)];
        var kind = fieldKind(field);
        if (!item || item.kind !== kind) return;
        var group = kind === 'radio' ? radioGroup(field, fields) : [field];
        if (kind === 'radio' && group[0] !== field) return;
        delete field.__MBG_REPORT_DRAFT_CONFLICT;
        if (!force && group.some(function(other) {
          return other.__MBG_REPORT_DRAFT_DIRTY || other.__MBG_REPORT_DRAFT_TOUCHED;
        })) return;
        var value = item.value;
        if (kind === 'text') {
          if (typeof value !== 'string' || value === fieldValue(field)) return;
          if (!force && compactText(fieldValue(field)).length > 0) {
            conflict = true;
            field.__MBG_REPORT_DRAFT_CONFLICT = item;
            return;
          }
          if (!force && !value) return;
        } else if (!force) {
          if (kind === 'radio') {
            if (group.some(function(other) {
              return other.checked && !other.defaultChecked;
            })) return;
          } else if (!isDefaultChoice(field)) return;
        }
        if (kind === 'radio') {
          if (value !== null && !group.some(function(other) {
            return other.value === value;
          })) return;
          var checked = group.filter(function(other) { return other.checked; })[0];
          if ((checked ? checked.value : null) === value) return;
          if (!force && group.some(function(other) { return other.defaultChecked; })) {
            conflict = true;
            field.__MBG_REPORT_DRAFT_CONFLICT = item;
            return;
          }
          group.forEach(function(other) { setFieldValue(other, other.value === value); });
        } else {
          if (kind === 'checkbox' && typeof value !== 'boolean') return;
          if (kind === 'select' && (!Array.isArray(value) || value.some(function(saved) {
            return !Array.prototype.some.call(field.options, function(option) {
              return option.value === saved;
            });
          }))) return;
          if (JSON.stringify(fieldValue(field)) === JSON.stringify(value)) return;
          if (!force && (kind === 'checkbox' && field.defaultChecked ||
              kind === 'select' && Array.prototype.some.call(field.options, function(option) {
                return option.defaultSelected;
              }))) {
            conflict = true;
            field.__MBG_REPORT_DRAFT_CONFLICT = item;
            return;
          }
          setFieldValue(field, value);
        }
        restored = true;
      });
    } finally {
      doc.__MBG_REPORT_DRAFT_RESTORING = false;
    }
    if (conflict) {
      ensureStatus(doc, store, key);
      updateStatus(doc, '保存済みの下書きがあります（' + savedTime(draft.savedAt, true) + '）',
        null, function() { restoreDraft(doc, store, key, saveableFields(doc), true); });
    } else if (restored) {
      ensureStatus(doc, store, key);
      updateStatus(doc, '保存済みの下書きを復元しました（' +
        savedTime(draft.savedAt, true) + ' 保存）');
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
    if (!doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT &&
        !context.fields.some(function(field) { return field.__MBG_REPORT_DRAFT_TOUCHED; })) {
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
    // Inspect only before the first restore; restored values are not user edits.
    fields.forEach(function(field) {
      if (field.__MBG_REPORT_DRAFT_BOUND || field.matches('[contenteditable]')) return;
      var kind = fieldKind(field);
      var changed = kind === 'radio' || kind === 'checkbox'
        ? field.checked !== field.defaultChecked
        : kind === 'select' ? !isDefaultChoice(field)
        : field.value !== field.defaultValue;
      if (changed) {
        field.__MBG_REPORT_DRAFT_DIRTY = true;
        field.__MBG_REPORT_DRAFT_TOUCHED = true;
      }
    });
    restoreDraft(doc, store, key, fields);

    function scheduleSave(field) {
      if (doc.__MBG_REPORT_DRAFT_RESTORING) return;
      field.__MBG_REPORT_DRAFT_LAST_VALUE = observedFieldValue(field);
      field.__MBG_REPORT_DRAFT_DIRTY = true;
      field.__MBG_REPORT_DRAFT_TOUCHED = true;
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
      field.__MBG_REPORT_DRAFT_LAST_VALUE = observedFieldValue(field);
      field.addEventListener('input', function() { scheduleSave(field); });
      function saveIfChanged() {
        if (observedFieldValue(field) !== field.__MBG_REPORT_DRAFT_LAST_VALUE) {
          scheduleSave(field);
        }
      }
      // Picking a choice is an edit even when it lands back on the default;
      // for text, change and keyup (arrows, shortcuts) only count when the
      // value actually moved.
      var isChoice = fieldKind(field) !== 'text';
      field.addEventListener('change', isChoice ?
        function() { scheduleSave(field); } : saveIfChanged);
      field.addEventListener('keyup', saveIfChanged);
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

  static String buildList() {
    return _buildStorageAction(r'''
  var entries = Object.create(null);
  var now = Date.now();
  draftDocuments().forEach(function(doc) {
    try {
      var store = doc.defaultView.localStorage;
      for (var i = store.length - 1; i >= 0; i -= 1) {
        var key = store.key(i);
        if (!isDraftKey(key)) continue;
        var draft = null;
        try { draft = JSON.parse(store.getItem(key)); } catch (_) {}
        if (!draft || typeof draft.savedAt !== 'number' ||
            !isFinite(draft.savedAt) || !draft.savedAt ||
            !Array.isArray(draft.fields) || now - draft.savedAt > retentionMs) {
          store.removeItem(key);
          continue;
        }
        var version = key.indexOf('mbg-report-draft:v2:') === 0 ? 2 : 1;
        var text = draft.fields.filter(function(item) {
          return item && (version === 1 || item.kind === 'text') &&
            typeof item.value === 'string';
        }).map(function(item) { return item.value; }).join('\n\n');
        var entry = {
          key: key,
          version: version,
          savedAt: draft.savedAt,
          heading: String((version === 1 ? draft.title : draft.heading) || draft.title || ''),
          preview: text.substring(0, 120),
          text: text
        };
        if (!entries[key] || entries[key].savedAt < entry.savedAt) entries[key] = entry;
      }
    } catch (e) {
      // Other same-origin documents may still have accessible storage.
    }
  });
  return JSON.stringify(Object.keys(entries).map(function(key) {
    return entries[key];
  }).sort(function(a, b) { return b.savedAt - a.savedAt; }));
''');
  }

  static String buildDelete(String key) {
    const action = r'''
  if (!isDraftKey(key)) return false;
  var removed = false;
  var failed = false;
  draftDocuments().forEach(function(doc) {
    try {
      doc.defaultView.localStorage.removeItem(key);
      var win = doc.defaultView;
      var suppressed = win.__MBG_REPORT_DRAFT_DELETED_KEYS ||
        (win.__MBG_REPORT_DRAFT_DELETED_KEYS = Object.create(null));
      suppressed[key] = true;
      var pending = win.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
      if (pending && pending.key === key) {
        win.clearTimeout(win.__MBG_REPORT_DRAFT_SAVE_TIMER);
        delete win.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
      }
      var status = doc.getElementById('mbg-report-draft-status');
      if (status && status.__MBG_REPORT_DRAFT_KEY === key) {
        Array.prototype.forEach.call(
          doc.querySelectorAll('textarea,input,select,[contenteditable]'),
          function(field) { delete field.__MBG_REPORT_DRAFT_CONFLICT; }
        );
        var label = doc.getElementById('mbg-report-draft-status-label');
        if (label) label.textContent = '下書きを削除しました';
        ['mbg-report-draft-retry', 'mbg-report-draft-replace'].forEach(function(id) {
          var button = doc.getElementById(id);
          if (button) button.style.display = 'none';
        });
        status.__MBG_REPORT_DRAFT_RETRY = null;
        status.__MBG_REPORT_DRAFT_REPLACE = null;
      }
      removed = true;
    } catch (e) {
      failed = true;
    }
  });
  return removed && !failed;
''';
    return _buildStorageAction('var key = ${jsonEncode(key)};\n$action');
  }

  static String _buildStorageAction(String action) {
    return '''
(function() {
$_storageHelpers
$action
})();
''';
  }

  static const _storageHelpers = r'''
  var retentionMs = 14 * 24 * 60 * 60 * 1000;
  function isDraftKey(key) {
    return typeof key === 'string' && /^mbg-report-draft:v[12]:/.test(key);
  }
  function draftDocuments() {
    var docs = [document];
    try {
      var frame = document.querySelector('iframe#main-frame-if');
      if (frame && frame.contentWindow && frame.contentWindow.document) {
        docs.push(frame.contentWindow.document);
      }
    } catch (e) {
      // Cross-origin frames cannot be inspected.
    }
    return docs;
  }
''';
}
