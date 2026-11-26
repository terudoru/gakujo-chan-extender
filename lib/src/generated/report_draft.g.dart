// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/report_draft/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoReportDraftJs = r'''
"use strict";
(() => {
  // web_scripts/src/shared/page_watch.ts
  function collectPageDocuments(win) {
    var docs = [];
    function collect(current) {
      try {
        var doc = current.document;
        if (!doc || docs.indexOf(doc) >= 0 || doc.defaultView === null) return;
        docs.push(doc);
        for (var i = 0; i < current.frames.length; i += 1) {
          try {
            collect(current.frames[i]);
          } catch (_) {
          }
        }
      } catch (_) {
      }
    }
    collect(win);
    return docs;
  }
  function watchPage(win, callback, options) {
    var Observer = win.MutationObserver;
    if (typeof Observer !== "function") {
      var legacyTimer = win.setInterval(callback, options.legacyIntervalMs);
      return function() {
        win.clearInterval(legacyTimer);
      };
    }
    var entries = [];
    var state = win.__MBG_PAGE_WATCH_STATE || { running: 0, observers: [] };
    win.__MBG_PAGE_WATCH_STATE = state;
    var fallbacks = state.fallbacks || (state.fallbacks = {});
    var timer;
    var disposed = false;
    var running = false;
    function schedule() {
      if (disposed || running || state.running || timer !== void 0) return;
      timer = win.setTimeout(function() {
        timer = void 0;
        run();
      }, 100);
    }
    function sync(docs) {
      for (var i = entries.length - 1; i >= 0; i -= 1) {
        if (docs.indexOf(entries[i].doc) < 0) {
          remove(entries[i]);
          entries.splice(i, 1);
        }
      }
      docs.forEach(function(doc) {
        if (!doc.documentElement || entries.some(function(entry) {
          return entry.doc === doc;
        })) return;
        try {
          var observer = new Observer(function() {
            if (options.onMutation) options.onMutation(doc);
            schedule();
          });
          observer.observe(doc.documentElement, { childList: true, subtree: true, characterData: true, attributes: true });
          doc.addEventListener("load", schedule, true);
          doc.addEventListener("input", schedule, true);
          doc.addEventListener("change", schedule, true);
          entries.push({ doc, observer });
          state.observers.push(observer);
        } catch (_) {
        }
      });
    }
    function remove(entry) {
      entry.observer.disconnect();
      var index = state.observers.indexOf(entry.observer);
      if (index >= 0) state.observers.splice(index, 1);
      entry.doc.removeEventListener("load", schedule, true);
      entry.doc.removeEventListener("input", schedule, true);
      entry.doc.removeEventListener("change", schedule, true);
    }
    function run(docs) {
      if (disposed) return false;
      if (timer !== void 0) {
        win.clearTimeout(timer);
        timer = void 0;
      }
      sync(docs || collectPageDocuments(win));
      running = true;
      state.running += 1;
      var changed = false;
      try {
        callback();
      } catch (_) {
      } finally {
        state.observers.forEach(function(observer) {
          if (observer.takeRecords().length) changed = true;
        });
        state.running -= 1;
        running = false;
      }
      return changed;
    }
    sync(collectPageDocuments(win));
    var fallbackKey = String(options.fallbackMs);
    var fallback = fallbacks[fallbackKey];
    if (!fallback) {
      fallback = { timer: win.setInterval(function() {
        var docs;
        fallback.runs.slice().forEach(function(registeredRun) {
          if (!docs) docs = collectPageDocuments(win);
          if (registeredRun(docs)) docs = void 0;
        });
      }, options.fallbackMs), runs: [] };
      fallbacks[fallbackKey] = fallback;
    }
    fallback.runs.push(run);
    return function() {
      if (disposed) return;
      disposed = true;
      if (timer !== void 0) win.clearTimeout(timer);
      var index = fallback.runs.indexOf(run);
      if (index >= 0) fallback.runs.splice(index, 1);
      if (!fallback.runs.length) {
        win.clearInterval(fallback.timer);
        delete fallbacks[fallbackKey];
      }
      entries.forEach(remove);
      entries = [];
      if (!state.observers.length && !Object.keys(fallbacks).length) delete win.__MBG_PAGE_WATCH_STATE;
    };
  }

  // web_scripts/src/report_draft/storage_helpers.ts
  var retentionMs = 14 * 24 * 60 * 60 * 1e3;
  function isDraftKey(key) {
    return typeof key === "string" && /^mbg-report-draft:v[12]:/.test(key);
  }
  var migrationPrefix = "mbg-report-draft:migration:";
  function migrationSources(store, key) {
    var raw = store.getItem(migrationPrefix + key);
    if (!raw) return [];
    var sources = JSON.parse(raw);
    return Array.isArray(sources) ? sources.filter(function(source) {
      return isDraftKey(source) && source !== key;
    }) : [];
  }
  function rememberMigration(store, key, source) {
    if (!store) return false;
    try {
      var sources = migrationSources(store, key);
      if (sources.indexOf(source) < 0) sources.push(source);
      store.setItem(migrationPrefix + key, JSON.stringify(sources));
      return true;
    } catch (_) {
      return false;
    }
  }
  function cleanupMigrationSources(store, key) {
    migrationSources(store, key).forEach(function(source) {
      store.removeItem(source);
    });
    store.removeItem(migrationPrefix + key);
  }

  // web_scripts/src/report_draft/main.ts
  function reportDraft() {
    var version = 12;
    var prefix = "mbg-report-draft:v2:";
    var retentionMs2 = 14 * 24 * 60 * 60 * 1e3;
    if (window.__MBG_REPORT_DRAFT_VERSION === version) {
      if (window.__MBG_REPORT_DRAFT_UPDATE) {
        window.__MBG_REPORT_DRAFT_UPDATE();
      }
      return;
    }
    window.__MBG_REPORT_DRAFT_VERSION = version;
    function documents() {
      var result = [document];
      var frames = document.querySelectorAll("iframe,frame");
      for (var i = 0; i < frames.length; i += 1) {
        try {
          if (frames[i].contentWindow && frames[i].contentWindow.document) {
            result.push(frames[i].contentWindow.document);
          }
        } catch (e) {
        }
      }
      return result;
    }
    function compactText(text) {
      return String(text || "").replace(/\s+/g, " ").trim();
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
      if (style.display === "none" || style.visibility === "hidden") {
        return false;
      }
      return element.getClientRects().length > 0;
    }
    function isIgnoredInput(input, legacy) {
      var type = (input.getAttribute("type") || "text").toLowerCase();
      if (legacy && (type === "checkbox" || type === "radio") || [
        "button",
        "color",
        "file",
        "hidden",
        "image",
        "password",
        "range",
        "reset",
        "submit"
      ].indexOf(type) >= 0) {
        return true;
      }
      var metadata = [
        input.getAttribute("name"),
        input.getAttribute("id"),
        input.getAttribute("autocomplete"),
        input.getAttribute("aria-label")
      ].join(" ").toLowerCase();
      return metadata.indexOf("password") >= 0 || metadata.indexOf("login") >= 0 || metadata.indexOf("userid") >= 0 || metadata.indexOf("username") >= 0 || metadata.indexOf("ninshocode") >= 0;
    }
    function saveableFields(doc, legacy = false) {
      var candidates = legacy ? doc.querySelectorAll("textarea,input,[contenteditable]") : doc.querySelectorAll("textarea,input,select,[contenteditable]");
      var fields = Array.prototype.slice.call(candidates).filter(function(field) {
        if (!visible(field)) {
          return false;
        }
        if (field.matches("[contenteditable]")) {
          return field.getAttribute("contenteditable") !== "false";
        }
        if (legacy && field.tagName.toLowerCase() === "textarea") return true;
        if (!legacy && /^_/.test(field.getAttribute("name") || "")) {
          return false;
        }
        return !isIgnoredInput(field, legacy);
      });
      return fields;
    }
    function stripCounters(text) {
      return compactText(String(text || "").replace(/入力文字数[:：]?\s*[0-9０-９]+\s*\/\s*[0-9０-９]+\s*文字?/g, "").replace(/[0-9０-９]+\s*\/\s*[0-9０-９]+\s*文字/g, ""));
    }
    function removeCounterElements(root) {
      Array.prototype.slice.call(root.querySelectorAll("[id],[class]")).forEach(function(node) {
        if (/count/i.test((node.getAttribute("id") || "") + " " + (node.getAttribute("class") || ""))) node.remove();
      });
    }
    function textWithoutFields(root, legacy) {
      var clone = root.cloneNode(true);
      Array.prototype.slice.call(
        clone.querySelectorAll(
          "textarea,input,select,button,[contenteditable],#mbg-report-draft-status"
        )
      ).forEach(function(node) {
        node.remove();
      });
      if (!legacy) removeCounterElements(clone);
      return clone.innerText || clone.textContent || "";
    }
    function pageTextWithoutFields(doc, legacy = false) {
      return doc.body ? compactText(textWithoutFields(doc.body, legacy)) : "";
    }
    function stablePageTextForKey(doc, legacy = false) {
      var text = pageTextWithoutFields(doc, legacy);
      return (legacy ? text : stripCounters(text)).replace(/残り約\s*[0-9０-９]+\s*分/g, "").replace(/前回ログイン日時[:：]?\s*[0-9０-９]{4}年[0-9０-９]{1,2}月[0-9０-９]{1,2}日\s*[0-9０-９]{1,2}時[0-9０-９]{1,2}分/g, "").replace(/[0-9０-９]{4}年[0-9０-９]{1,2}月[0-9０-９]{1,2}日\s*[0-9０-９]{1,2}時[0-9０-９]{1,2}分/g, "").replace(/\s+/g, " ").trim();
    }
    function looksLikeReportSubmission(doc, fields) {
      if (!fields.length) {
        return false;
      }
      var url = "";
      try {
        url = doc.location.href || "";
      } catch (e) {
        url = "";
      }
      var hasDraftWorthyField = fields.some(function(field) {
        if (field.matches("[contenteditable]")) {
          return true;
        }
        var tagName = field.tagName.toLowerCase();
        if (tagName === "textarea" || fieldKind(field) !== "text") {
          return true;
        }
        if (tagName !== "input") {
          return false;
        }
        return /本文|コメント|回答|解答|内容|理由|備考/.test(labelFor(field));
      });
      if (!hasDraftWorthyField) {
        return false;
      }
      var text = compactText((doc.title || "") + " " + pageTextWithoutFields(doc));
      var reportContext = text.indexOf("レポート・小テスト・アンケート提出") >= 0 || /レポート提出(?!日)/.test(text) || /小テスト(?:提出(?!日)|回答|解答)/.test(text) || /アンケート(?:提出(?!期限)|回答)/.test(text) || /report|enq|questionnaire/i.test(url);
      var submissionContext = /提出(?!日|期限)/.test(text) || text.indexOf("回答") >= 0 || text.indexOf("解答") >= 0 || text.indexOf("入力") >= 0 || text.indexOf("本文") >= 0 || text.indexOf("コメント") >= 0;
      return reportContext && submissionContext;
    }
    function labelFor(field, legacy = false) {
      var _a;
      var doc = field.ownerDocument;
      var labels = [
        field.getAttribute("name"),
        field.getAttribute("id"),
        field.getAttribute("aria-label"),
        field.getAttribute("title"),
        field.getAttribute("placeholder")
      ];
      if (field.id && doc.defaultView.CSS && doc.defaultView.CSS.escape) {
        var label = doc.querySelector(
          'label[for="' + doc.defaultView.CSS.escape(field.id) + '"]'
        );
        if (label) {
          labels.push(label.innerText || label.textContent || "");
        }
      }
      var row = (_a = legacy ? field : field.parentElement) == null ? void 0 : _a.closest("tr,div,p,li,section");
      if (row) {
        labels.push(textWithoutFields(row, legacy));
      }
      var text = labels.filter(Boolean).join(" ");
      return (legacy ? compactText(text) : stripCounters(text)).substring(0, 120);
    }
    function fieldKind(field) {
      if (field.tagName.toLowerCase() === "select") return "select";
      var type = (field.getAttribute("type") || "").toLowerCase();
      return type === "radio" || type === "checkbox" ? type : "text";
    }
    function fieldIdentity(field) {
      var identity = field.getAttribute("name") || field.id || labelFor(field);
      return fieldKind(field) === "checkbox" ? identity + "=" + field.value : identity;
    }
    function fieldKey(field, index, fields) {
      var identity = fieldIdentity(field);
      var occurrence = fields.slice(0, index).filter(function(other) {
        return fieldIdentity(other) === identity;
      }).length;
      return [
        field.tagName.toLowerCase(),
        (field.getAttribute("type") || "").toLowerCase(),
        identity,
        occurrence
      ].join("|");
    }
    function radioGroup(field, fields) {
      var name = field.getAttribute("name");
      return name ? fields.filter(function(other) {
        return fieldKind(other) === "radio" && other.getAttribute("name") === name && other.form === field.form;
      }) : [field];
    }
    function fieldValue(field) {
      if (field.matches("[contenteditable]")) {
        return typeof field.innerText === "string" ? field.innerText : field.textContent || "";
      }
      if (fieldKind(field) === "checkbox") return field.checked;
      if (fieldKind(field) === "select") {
        return Array.prototype.slice.call(field.options).filter(function(option) {
          return option.selected;
        }).map(function(option) {
          return option.value;
        });
      }
      return field.value || "";
    }
    function isDefaultChoice(field) {
      if (fieldKind(field) === "checkbox") {
        return field.checked === field.defaultChecked;
      }
      var options = Array.prototype.slice.call(field.options);
      var defaults = options.filter(function(option) {
        return option.defaultSelected;
      });
      if (!field.multiple) {
        defaults = defaults.length ? defaults.slice(-1) : options.filter(function(option) {
          return !option.disabled && !(option.parentNode && option.parentNode.disabled);
        }).slice(0, field.size > 1 ? 0 : 1);
      }
      return options.every(function(option) {
        return option.selected === defaults.indexOf(option) >= 0;
      });
    }
    function observedFieldValue(field) {
      return JSON.stringify(fieldKind(field) === "radio" ? field.checked : fieldValue(field));
    }
    function setContentEditableText(field, value) {
      var doc = field.ownerDocument;
      var lines = String(value || "").split(/\r\n?|\n/);
      field.textContent = "";
      for (var i = 0; i < lines.length; i += 1) {
        if (i > 0) {
          field.appendChild(doc.createElement("br"));
        }
        if (lines[i]) {
          field.appendChild(doc.createTextNode(lines[i]));
        }
      }
    }
    function setFieldValue(field, value) {
      var win = field.ownerDocument.defaultView || window;
      if (field.matches("[contenteditable]")) {
        setContentEditableText(field, value);
      } else if (fieldKind(field) === "checkbox" || fieldKind(field) === "radio") {
        field.checked = value;
      } else if (fieldKind(field) === "select") {
        Array.prototype.slice.call(field.options).forEach(function(option) {
          option.selected = value.indexOf(option.value) >= 0;
        });
        if (!value.length) field.selectedIndex = -1;
      } else {
        var proto = field.tagName.toLowerCase() === "textarea" ? win.HTMLTextAreaElement.prototype : win.HTMLInputElement.prototype;
        var descriptor = Object.getOwnPropertyDescriptor(proto, "value");
        if (descriptor && descriptor.set) {
          descriptor.set.call(field, value);
        } else {
          field.value = value;
        }
      }
      try {
        field.dispatchEvent(new win.InputEvent("input", {
          bubbles: true,
          inputType: "insertReplacementText",
          data: typeof value === "string" ? value : null
        }));
      } catch (e) {
        field.dispatchEvent(new win.Event("input", { bubbles: true }));
      }
      field.dispatchEvent(new win.Event("change", { bubbles: true }));
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
    function draftKey(doc, fields, rawPath) {
      var identities = fields.map(function(field, index) {
        return fieldKey(field, index, fields);
      }).sort().join("\n");
      var cached = doc.__MBG_REPORT_DRAFT_IDENTITY;
      if (cached && cached.signature === identities && cached.fields.length === fields.length && cached.fields.every(function(field, index) {
        return field === fields[index];
      })) {
        return rawPath ? cached.rawKey : cached.key;
      }
      var path = "";
      try {
        path = doc.location.pathname || "";
      } catch (e) {
        path = "";
      }
      var signature = [
        path,
        doc.title || "",
        stablePageTextForKey(doc),
        identities
      ];
      var rawKey = prefix + hashString(signature.join("\n"));
      signature[0] = path.replace(/;jsessionid=[^;/]*/gi, "");
      var key = signature[0] === path ? rawKey : prefix + hashString(signature.join("\n"));
      doc.__MBG_REPORT_DRAFT_IDENTITY = {
        signature: identities,
        fields: fields.slice(),
        key,
        rawKey
      };
      return rawPath ? rawKey : key;
    }
    var legacyDraft = /* @__PURE__ */ (function() {
      var prefix2 = "mbg-report-draft:v1:";
      function fieldKey2(field, index) {
        return [
          field.tagName.toLowerCase(),
          (field.getAttribute("type") || "").toLowerCase(),
          labelFor(field, true),
          index
        ].join("|");
      }
      function zeroCounters(text) {
        return String(text || "").replace(/(入力文字数[:：]?\s*)[0-9０-９]+(\s*\/)/g, "$10$2").replace(/(^|[^0-9０-９\/])[0-9０-９]+(\s*\/\s*[0-9０-９]+\s*文字)/g, "$10$2");
      }
      function legacyDraftKeys(doc, fields) {
        var path = "";
        try {
          path = doc.location.pathname || "";
        } catch (e) {
          path = "";
        }
        var signature = [
          path,
          doc.title || "",
          stablePageTextForKey(doc, true).substring(0, 4e3),
          fields.map(function(field) {
            return labelFor(field, true);
          }).join("|")
        ].join("\n");
        var keys = [prefix2 + hashString(signature)];
        var pattern = /(入力文字数[:：]?\s*)[0-9０-９]+(\s*\/\s*)([0-9]+)/g;
        var counter = /(入力文字数[:：]?\s*)[0-9０-９]+(\s*\/\s*)([0-9]+)/.exec(signature);
        if (!counter) return keys;
        var max = Math.min(Number(counter[3]), 4e3);
        for (var count = 0; count <= max; count += 1) {
          var candidate = signature.replace(pattern, function(_, label, slash, limit) {
            return label + count + slash + limit;
          });
          if (candidate !== signature) keys.push(prefix2 + hashString(candidate));
        }
        return keys;
      }
      return {
        keys: legacyDraftKeys,
        fields: function(doc) {
          return saveableFields(doc, true);
        },
        fieldKey: fieldKey2,
        zeroCounters
      };
    })();
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
    function notifyDraftSaved() {
      try {
        var channel = window.GakujoMessageStars;
        if (channel && channel.postMessage) {
          channel.postMessage(JSON.stringify({ type: "reportDraftSaved" }));
        }
      } catch (_) {
      }
    }
    function writeDraft(store, key, payload) {
      if (!store) {
        return false;
      }
      try {
        store.setItem(key, JSON.stringify(payload));
        notifyDraftSaved();
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
        notifyDraftSaved();
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
          if (!draft || typeof draft.savedAt !== "number" || !isFinite(draft.savedAt) || !draft.savedAt || !Array.isArray(draft.fields) || now - draft.savedAt > retentionMs2) {
            store.removeItem(key);
          }
        }
      } catch (e) {
      }
    }
    function ensureStatus(doc, store, key) {
      var status = doc.getElementById("mbg-report-draft-status");
      if (status) {
        if (status.__MBG_REPORT_DRAFT_KEY !== key) {
          updateStatus(doc, "入力すると下書きを保存します");
        }
        status.__MBG_REPORT_DRAFT_STORE = store;
        status.__MBG_REPORT_DRAFT_KEY = key;
        return status;
      }
      var firstField = saveableFields(doc)[0];
      if (!firstField) {
        return null;
      }
      status = doc.createElement("div");
      status.id = "mbg-report-draft-status";
      status.style.margin = "8px 0";
      status.style.padding = "6px 8px";
      status.style.border = "1px solid #8eb79a";
      status.style.background = "#eef8f0";
      status.style.color = "#234231";
      status.style.fontSize = "12px";
      status.style.display = "flex";
      status.style.gap = "8px";
      status.style.alignItems = "center";
      status.style.flexWrap = "wrap";
      var label = doc.createElement("span");
      label.id = "mbg-report-draft-status-label";
      label.textContent = "入力すると下書きを保存します";
      status.appendChild(label);
      var clearButton = doc.createElement("button");
      clearButton.type = "button";
      clearButton.textContent = "下書きを削除";
      clearButton.style.fontSize = "12px";
      function clearStoredDraft() {
        var store2 = status.__MBG_REPORT_DRAFT_STORE;
        var key2 = status.__MBG_REPORT_DRAFT_KEY;
        var fields = saveableFields(doc);
        var rawKey = draftKey(doc, fields, true);
        var deleted = removeDraft(store2, key2);
        if (rawKey !== key2) {
          deleted = removeDraft(store2, rawKey) && deleted;
        }
        var found = doc.__MBG_REPORT_DRAFT_LEGACY_FOUND;
        if (found && found.key === key2 && found.legacyKey) {
          deleted = removeDraft(store2, found.legacyKey) && deleted;
        }
        try {
          if (store2 && key2) cleanupMigrationSources(store2, key2);
        } catch (_) {
          deleted = false;
        }
        if (!deleted) {
          updateStatus(doc, "下書きを削除できませんでした", clearStoredDraft);
          return;
        }
        var win = doc.defaultView;
        var suppressed = win.__MBG_REPORT_DRAFT_DELETED_KEYS || (win.__MBG_REPORT_DRAFT_DELETED_KEYS = /* @__PURE__ */ Object.create(null));
        suppressed[key2] = true;
        var pending = win.__MBG_REPORT_DRAFT_PENDING_CONTEXTS;
        if (pending && key2) {
          delete pending[key2];
          if (!Object.keys(pending).length) {
            win.clearTimeout(win.__MBG_REPORT_DRAFT_SAVE_TIMER);
            delete win.__MBG_REPORT_DRAFT_PENDING_CONTEXTS;
          }
        }
        fields.forEach(function(field) {
          field.__MBG_REPORT_DRAFT_DIRTY = false;
          delete field.__MBG_REPORT_DRAFT_CONFLICT;
        });
        updateStatus(doc, "下書きを削除しました");
      }
      clearButton.addEventListener("click", clearStoredDraft);
      var retryButton = doc.createElement("button");
      retryButton.id = "mbg-report-draft-retry";
      retryButton.type = "button";
      retryButton.textContent = "再試行";
      retryButton.style.display = "none";
      retryButton.addEventListener("click", function() {
        if (status.__MBG_REPORT_DRAFT_RETRY) status.__MBG_REPORT_DRAFT_RETRY();
      });
      var replaceButton = doc.createElement("button");
      replaceButton.id = "mbg-report-draft-replace";
      replaceButton.type = "button";
      replaceButton.textContent = "下書きで置き換える";
      replaceButton.style.display = "none";
      replaceButton.addEventListener("click", function() {
        if (status.__MBG_REPORT_DRAFT_REPLACE) status.__MBG_REPORT_DRAFT_REPLACE();
      });
      status.appendChild(clearButton);
      status.appendChild(retryButton);
      status.appendChild(replaceButton);
      status.__MBG_REPORT_DRAFT_STORE = store;
      status.__MBG_REPORT_DRAFT_KEY = key;
      var form = firstField.closest("form");
      var anchor = form || firstField;
      anchor.parentNode.insertBefore(status, anchor);
      return status;
    }
    function removeStatus(doc) {
      var status = doc.getElementById("mbg-report-draft-status");
      if (status) {
        status.remove();
      }
    }
    function updateStatus(doc, text, retry, replace) {
      var label = doc.getElementById("mbg-report-draft-status-label");
      if (label) {
        label.textContent = text;
      }
      var status = doc.getElementById("mbg-report-draft-status");
      var retryButton = doc.getElementById("mbg-report-draft-retry");
      var replaceButton = doc.getElementById("mbg-report-draft-replace");
      if (status) status.__MBG_REPORT_DRAFT_RETRY = retry || null;
      if (status) status.__MBG_REPORT_DRAFT_REPLACE = replace || null;
      if (retryButton) retryButton.style.display = retry ? "" : "none";
      if (replaceButton) replaceButton.style.display = replace ? "" : "none";
    }
    function savedTime(savedAt, withDate) {
      var date = new Date(savedAt);
      var time = ("0" + date.getHours()).slice(-2) + ":" + ("0" + date.getMinutes()).slice(-2);
      return withDate ? date.getMonth() + 1 + "/" + date.getDate() + " " + time : time;
    }
    function headingFor(doc) {
      var values = {};
      Array.prototype.slice.call(doc.querySelectorAll("tr")).forEach(function(row) {
        var cells = Array.prototype.slice.call(row.children).filter(function(cell) {
          return /^(TH|TD)$/i.test(cell.tagName);
        });
        if (cells.length < 2) return;
        cells.forEach(function(cell, index) {
          if (index !== 0 && cell.tagName.toUpperCase() !== "TH") return;
          var header = compactText(cell.innerText || cell.textContent);
          if (header === "科目名" || header === "タイトル") {
            values[header] = compactText(cells.slice(index + 1).map(function(valueCell) {
              return valueCell.innerText || valueCell.textContent || "";
            }).join(" "));
          }
        });
      });
      return [values["科目名"], values["タイトル"]].filter(Boolean).join(" / ") || doc.title || "";
    }
    function collectValues(fields) {
      return fields.map(function(field, index) {
        var kind = fieldKind(field);
        var value = fieldValue(field);
        var group = kind === "radio" ? radioGroup(field, fields) : [field];
        if (kind === "radio" && group[0] !== field) return null;
        if (field.__MBG_REPORT_DRAFT_CONFLICT && !group.some(function(other) {
          return other.__MBG_REPORT_DRAFT_TOUCHED;
        })) return field.__MBG_REPORT_DRAFT_CONFLICT;
        delete field.__MBG_REPORT_DRAFT_CONFLICT;
        if (kind === "radio") {
          var checked = group.filter(function(other) {
            return other.checked;
          })[0];
          value = checked ? checked.value : null;
        }
        return {
          key: fieldKey(field, index, fields),
          value,
          kind
        };
      }).filter(Boolean);
    }
    function saveDraft(doc, store, key, fields, showStatus, draft) {
      var suppressed = doc.defaultView.__MBG_REPORT_DRAFT_DELETED_KEYS;
      if (suppressed && suppressed[key]) return true;
      store = store || storageFor(doc);
      var values = draft ? draft.fields : collectValues(fields);
      var hasContent = values.some(function(item) {
        return item.kind !== "text" || compactText(item.value).length > 0;
      });
      var savedAt = Date.now();
      var saved = hasContent ? writeDraft(store, key, {
        savedAt,
        title: draft ? draft.title : doc.title || "",
        url: draft ? draft.url : doc.location && doc.location.href || "",
        heading: draft ? draft.heading : headingFor(doc),
        fields: values
      }) : removeDraft(store, key);
      if (!saved) {
        if (showStatus) updateStatus(doc, "下書きを保存できませんでした。入力内容をコピーして保管してください", function() {
          saveCurrentDraft(doc);
        });
        return false;
      }
      fields.forEach(function(field) {
        field.__MBG_REPORT_DRAFT_DIRTY = false;
        field.__MBG_REPORT_DRAFT_LAST_VALUE = observedFieldValue(field);
      });
      if (showStatus) updateStatus(doc, hasContent ? "下書きを保存しました（" + savedTime(savedAt, false) + "）" : "下書きは空です");
      return true;
    }
    function restoreDraft(doc, store, key, fields, force) {
      var pending = doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXTS;
      var context = pending && pending[key];
      var pendingDraft = context && context.draft;
      var draft = pendingDraft || readDraft(store, key);
      if (draft && store && !pendingDraft) {
        try {
          cleanupMigrationSources(store, key);
        } catch (_) {
        }
      }
      var legacyKey = null;
      if (!draft) {
        var rawKey = draftKey(doc, fields, true);
        if (rawKey !== key) {
          draft = readDraft(store, rawKey);
          if (draft) legacyKey = rawKey;
        }
      }
      if (!draft && doc.__MBG_REPORT_DRAFT_LEGACY_CHECKED !== key) {
        var legacyFields = legacyDraft.fields(doc);
        var oldDraft = null;
        var found = doc.__MBG_REPORT_DRAFT_LEGACY_FOUND;
        var candidates = found && found.key === key ? [found.legacyKey] : legacyDraft.keys(doc, legacyFields);
        candidates.some(function(candidate) {
          oldDraft = readDraft(store, candidate);
          legacyKey = oldDraft ? candidate : null;
          return !!oldDraft;
        });
        if (!oldDraft) doc.__MBG_REPORT_DRAFT_LEGACY_CHECKED = key;
        else doc.__MBG_REPORT_DRAFT_LEGACY_FOUND = { key, legacyKey };
        if (oldDraft && Array.isArray(oldDraft.fields)) {
          var oldByKey = /* @__PURE__ */ Object.create(null);
          oldDraft.fields.forEach(function(item) {
            if (item) oldByKey[legacyDraft.zeroCounters(item.key)] = item;
          });
          draft = {
            savedAt: oldDraft.savedAt,
            title: oldDraft.title,
            url: oldDraft.url,
            heading: headingFor(doc),
            fields: legacyFields.map(function(field, index) {
              var item = oldByKey[legacyDraft.zeroCounters(legacyDraft.fieldKey(field, index))];
              var currentIndex = fields.indexOf(field);
              return item && currentIndex >= 0 ? {
                key: fieldKey(field, currentIndex, fields),
                value: item.value,
                kind: "text"
              } : null;
            }).filter(Boolean)
          };
        }
      }
      if (!draft || !Array.isArray(draft.fields)) {
        return;
      }
      var byKey = /* @__PURE__ */ Object.create(null);
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
          var group = kind === "radio" ? radioGroup(field, fields) : [field];
          if (kind === "radio" && group[0] !== field) return;
          delete field.__MBG_REPORT_DRAFT_CONFLICT;
          if (!force && group.some(function(other) {
            return other.__MBG_REPORT_DRAFT_DIRTY || other.__MBG_REPORT_DRAFT_TOUCHED;
          })) return;
          var value = item.value;
          if (kind === "text") {
            if (typeof value !== "string" || value === fieldValue(field)) return;
            if (!force && compactText(fieldValue(field)).length > 0) {
              conflict = true;
              field.__MBG_REPORT_DRAFT_CONFLICT = item;
              return;
            }
            if (!force && !value) return;
          } else if (!force) {
            if (kind === "radio") {
              if (group.some(function(other) {
                return other.checked && !other.defaultChecked;
              })) return;
            } else if (!isDefaultChoice(field)) return;
          }
          if (kind === "radio") {
            if (value !== null && !group.some(function(other) {
              return other.value === value;
            })) return;
            var checked = group.filter(function(other) {
              return other.checked;
            })[0];
            if ((checked ? checked.value : null) === value) return;
            if (!force && group.some(function(other) {
              return other.defaultChecked;
            })) {
              conflict = true;
              field.__MBG_REPORT_DRAFT_CONFLICT = item;
              return;
            }
            group.forEach(function(other) {
              setFieldValue(other, other.value === value);
            });
          } else {
            if (kind === "checkbox" && typeof value !== "boolean") return;
            if (kind === "select" && (!Array.isArray(value) || value.some(function(saved) {
              return !Array.prototype.some.call(field.options, function(option) {
                return option.value === saved;
              });
            }))) return;
            if (JSON.stringify(fieldValue(field)) === JSON.stringify(value)) return;
            if (!force && (kind === "checkbox" && field.defaultChecked || kind === "select" && Array.prototype.some.call(field.options, function(option) {
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
      if (context && pendingDraft) {
        context.fields = fields.slice();
      }
      if (legacyKey && rememberMigration(store, key, legacyKey) && writeDraft(store, key, draft)) {
        try {
          cleanupMigrationSources(store, key);
        } catch (_) {
        }
        doc.__MBG_REPORT_DRAFT_LEGACY_CHECKED = key;
      }
      if (conflict) {
        ensureStatus(doc, store, key);
        updateStatus(
          doc,
          pendingDraft ? "未保存の下書きがあります" : "保存済みの下書きがあります（" + savedTime(draft.savedAt, true) + "）",
          pendingDraft ? function() {
            saveCurrentDraft(doc);
          } : null,
          function() {
            restoreDraft(doc, store, key, saveableFields(doc), true);
          }
        );
      } else if (pendingDraft) {
        ensureStatus(doc, store, key);
        updateStatus(
          doc,
          "未保存の下書きがあります。再試行してください",
          function() {
            saveCurrentDraft(doc);
          }
        );
      } else if (restored) {
        ensureStatus(doc, store, key);
        updateStatus(doc, "保存済みの下書きを復元しました（" + savedTime(draft.savedAt, true) + " 保存）");
      }
    }
    function currentDraftContext(doc) {
      var fields = saveableFields(doc);
      if (!looksLikeReportSubmission(doc, fields)) {
        return null;
      }
      var store = storageFor(doc);
      return {
        fields,
        store,
        key: draftKey(doc, fields)
      };
    }
    function snapshotContext(doc, context) {
      context.fields = context.fields.slice();
      context.draft = {
        savedAt: Date.now(),
        title: doc.title || "",
        url: doc.location && doc.location.href || "",
        heading: headingFor(doc),
        fields: collectValues(context.fields)
      };
      return context;
    }
    function saveCurrentDraft(doc) {
      var win = doc.defaultView;
      var pending = win.__MBG_REPORT_DRAFT_PENDING_CONTEXTS || /* @__PURE__ */ Object.create(null);
      var current = currentDraftContext(doc);
      var currentKey = current ? current.key : "";
      var currentFields = current ? current.fields : [];
      var hasPending = Object.keys(pending).length > 0;
      if (current && current.fields.some(function(field) {
        return field.__MBG_REPORT_DRAFT_DIRTY || field.__MBG_REPORT_DRAFT_TOUCHED && (pending[currentKey] || !hasPending || observedFieldValue(field) !== field.__MBG_REPORT_DRAFT_LAST_VALUE);
      })) {
        pending[current.key] = snapshotContext(doc, current);
      }
      if (!Object.keys(pending).length) return true;
      win.__MBG_REPORT_DRAFT_PENDING_CONTEXTS = pending;
      var saved = true;
      Object.keys(pending).forEach(function(key) {
        var context = pending[key];
        var isCurrent = key === currentKey && context.fields.length === currentFields.length && context.fields.every(function(field, index) {
          return field === currentFields[index];
        });
        if (saveDraft(doc, context.store, key, context.fields, isCurrent, context.draft)) {
          if (pending[key] === context) delete pending[key];
          if (isCurrent && context.fields.some(function(field) {
            return field.__MBG_REPORT_DRAFT_CONFLICT;
          })) {
            restoreDraft(doc, context.store, key, context.fields);
          }
        } else {
          saved = false;
        }
      });
      if (!Object.keys(pending).length) {
        win.clearTimeout(win.__MBG_REPORT_DRAFT_SAVE_TIMER);
        delete win.__MBG_REPORT_DRAFT_PENDING_CONTEXTS;
      }
      if (!saved) updateStatus(
        doc,
        "下書きを保存できませんでした。入力内容をコピーして保管してください",
        function() {
          saveCurrentDraft(doc);
        }
      );
      return saved;
    }
    function bindDraft(doc) {
      var context = currentDraftContext(doc);
      if (!context) {
        removeStatus(doc);
        return false;
      }
      var fields = context.fields;
      var store = context.store;
      doc.__MBG_REPORT_DRAFT_FLUSH = function() {
        return saveCurrentDraft(doc);
      };
      cleanup(store);
      var key = context.key;
      ensureStatus(doc, store, key);
      fields.forEach(function(field) {
        if (field.__MBG_REPORT_DRAFT_BOUND || field.matches("[contenteditable]")) return;
        var kind = fieldKind(field);
        var changed = kind === "radio" || kind === "checkbox" ? field.checked !== field.defaultChecked : kind === "select" ? !isDefaultChoice(field) : field.value !== field.defaultValue;
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
        var snapshot = snapshotContext(doc, pendingContext);
        var pending = doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXTS || (doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXTS = /* @__PURE__ */ Object.create(null));
        pending[snapshot.key] = snapshot;
        doc.defaultView.clearTimeout(doc.defaultView.__MBG_REPORT_DRAFT_SAVE_TIMER);
        doc.defaultView.__MBG_REPORT_DRAFT_SAVE_TIMER = doc.defaultView.setTimeout(function() {
          saveCurrentDraft(doc);
        }, 250);
      }
      fields.forEach(function(field) {
        if (field.__MBG_REPORT_DRAFT_BOUND) {
          return;
        }
        field.__MBG_REPORT_DRAFT_BOUND = true;
        field.__MBG_REPORT_DRAFT_LAST_VALUE = observedFieldValue(field);
        field.addEventListener("input", function() {
          scheduleSave(field);
        });
        function saveIfChanged() {
          if (observedFieldValue(field) !== field.__MBG_REPORT_DRAFT_LAST_VALUE) {
            scheduleSave(field);
          }
        }
        var isChoice = fieldKind(field) !== "text";
        field.addEventListener("change", isChoice ? function() {
          scheduleSave(field);
        } : saveIfChanged);
        field.addEventListener("keyup", saveIfChanged);
      });
      Array.prototype.slice.call(doc.querySelectorAll("form")).forEach(function(form) {
        if (form.__MBG_REPORT_DRAFT_BOUND) {
          return;
        }
        form.__MBG_REPORT_DRAFT_BOUND = true;
        form.addEventListener("submit", function() {
          saveCurrentDraft(doc);
        }, true);
      });
      if (!doc.defaultView.__MBG_REPORT_DRAFT_BEFORE_UNLOAD_BOUND) {
        doc.defaultView.__MBG_REPORT_DRAFT_BEFORE_UNLOAD_BOUND = true;
        doc.defaultView.addEventListener("beforeunload", function() {
          saveCurrentDraft(doc);
        });
        doc.defaultView.addEventListener("pagehide", function() {
          saveCurrentDraft(doc);
        });
        doc.addEventListener("visibilitychange", function() {
          if (doc.visibilityState === "hidden") {
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
        }
      }
      return applied;
    }
    window.__MBG_REPORT_DRAFT_UPDATE = apply;
    apply();
    window.clearInterval(window.__MBG_REPORT_DRAFT_INTERVAL);
    if (window.__MBG_REPORT_DRAFT_WATCH_DISPOSE) window.__MBG_REPORT_DRAFT_WATCH_DISPOSE();
    window.__MBG_REPORT_DRAFT_WATCH_DISPOSE = watchPage(window, apply, { fallbackMs: 5e3, legacyIntervalMs: 1e3 });
  }
  reportDraft();
})();
''';
