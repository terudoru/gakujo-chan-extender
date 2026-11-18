// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/assignment_attachment/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoAssignmentAttachmentJs(Map<String, Object?> config) =>
    _gakujoAssignmentAttachmentJsPrefix +
    jsonEncode(config) +
    _gakujoAssignmentAttachmentJsSuffix;

const String _gakujoAssignmentAttachmentJsPrefix = r'''(function(__mbgConfig) {
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

  // web_scripts/src/shared/assignment_attachment.ts
  function acceptsAttachment(input, name, mime) {
    const filters = input.accept.toLowerCase().split(",").map((value) => value.trim()).filter(Boolean);
    const fileName = name.toLowerCase();
    const type = mime.toLowerCase();
    return !filters.length || filters.some((filter) => filter.startsWith(".") ? fileName.endsWith(filter) : filter.endsWith("/*") ? type.startsWith(filter.slice(0, -1)) : type === filter);
  }
  function setAssignmentAttachment(input, file, replace) {
    return setAssignmentAttachments(input, [file], replace);
  }
  function setAssignmentAttachments(input, files, replace) {
    var _a;
    const view = input.ownerDocument.defaultView;
    if (!view || !input.isConnected || input.type !== "file" || input.matches(":disabled") || !files.length || !input.multiple && files.length !== 1 || !files.every((file) => acceptsAttachment(input, file.name, file.type))) return false;
    const current = Array.from(input.files || []);
    if (replace && (files.length !== 1 || !current.includes(replace))) return false;
    const next = replace ? current.map((item) => item === replace ? files[0] : item) : input.multiple ? [...current, ...files] : files;
    try {
      const transfer = new view.DataTransfer();
      next.forEach((item) => transfer.items.add(item));
      if (transfer.files.length !== next.length) return false;
      input.files = transfer.files;
    } catch (_) {
      return false;
    }
    if (((_a = input.files) == null ? void 0 : _a.length) !== next.length) return false;
    input.dispatchEvent(new view.Event("input", { bubbles: true, composed: true }));
    input.dispatchEvent(new view.Event("change", { bubbles: true }));
    return true;
  }

  // web_scripts/src/assignment_attachment/desktop_drop.ts
  function isFileDrag(event) {
    var _a;
    return Array.from(((_a = event.dataTransfer) == null ? void 0 : _a.types) || []).includes("Files");
  }
  function createAttachmentDropZone(input) {
    const doc = input.ownerDocument;
    const zone = doc.createElement("span");
    const info = doc.createElement("span");
    const caption = doc.createElement("span");
    caption.textContent = "ファイルをここにドロップ";
    info.setAttribute("aria-live", "polite");
    info.style.cssText = "display:block";
    zone.setAttribute("data-mbg-attachment-drop", "");
    zone.style.cssText = "box-sizing:border-box;display:block;width:fit-content;max-width:100%;margin:6px 0;padding:8px 12px;border:1px dashed currentColor;border-radius:4px";
    zone.append(caption, info);
    function highlight(active) {
      zone.style.backgroundColor = active ? "rgba(41,110,234,.16)" : "";
    }
    zone.addEventListener("dragover", (event) => {
      if (!isFileDrag(event)) return;
      event.preventDefault();
      event.stopPropagation();
      const allowed = !input.matches(":disabled") && input.isConnected;
      event.dataTransfer.dropEffect = allowed ? "copy" : "none";
      highlight(allowed);
    });
    zone.addEventListener("dragleave", (event) => {
      if (event.relatedTarget instanceof Node && zone.contains(event.relatedTarget)) return;
      highlight(false);
    });
    zone.addEventListener("drop", (event) => {
      if (!isFileDrag(event)) return;
      event.preventDefault();
      event.stopPropagation();
      highlight(false);
      const transfer = event.dataTransfer;
      const files = Array.from(transfer.files);
      if (!files.length || Array.from(transfer.items || []).some((item) => {
        var _a, _b;
        return (_b = (_a = item.webkitGetAsEntry) == null ? void 0 : _a.call(item)) == null ? void 0 : _b.isDirectory;
      })) {
        info.textContent = "ファイルを選んでください。";
      } else if (!input.multiple && files.length > 1) {
        info.textContent = "この欄にはファイルを1つだけ添付できます。";
      } else if (files.some((file) => !acceptsAttachment(input, file.name, file.type))) {
        info.textContent = "この欄で使えるファイル形式を選んでください。";
      } else if (setAssignmentAttachments(input, files)) {
        info.textContent = files.length === 1 ? "ファイルを選択しました。" : files.length + "件のファイルを選択しました。";
      } else {
        info.textContent = "添付できませんでした。ファイル選択からやり直してください。";
      }
    });
    return zone;
  }

  // web_scripts/src/assignment_attachment/main.ts
  var MAX_BYTES = 64 * 1024 * 1024;
  var CHUNK_BYTES = 256 * 1024;
  function installAssignmentAttachment() {
    if (window.__MBG_ASSIGNMENT_ATTACHMENT) {
      window.__MBG_ASSIGNMENT_ATTACHMENT.setShared(__mbgConfig.shared);
      return;
    }
    let shared = __mbgConfig.shared;
    let request = null;
    let transfer = null;
    let requestAckTimer;
    const controls = /* @__PURE__ */ new WeakMap();
    const dropDocuments = /* @__PURE__ */ new WeakSet();
    function hiddenValues(form) {
      return JSON.stringify(Array.from(
        (form == null ? void 0 : form.querySelectorAll("input[type=hidden]")) || [],
        (field) => [field.name, field.value]
      ));
    }
    function current(candidate) {
      var _a;
      const { input } = candidate;
      const files = Array.from(input.files || []);
      return input.isConnected && !input.matches(":disabled") && input.type === "file" && ((_a = input.ownerDocument.defaultView) == null ? void 0 : _a.location.href) === candidate.location && input.form === candidate.form && hiddenValues(input.form) === candidate.formValues && files.length === candidate.files.length && files.every((file, index) => file === candidate.files[index]);
    }
    function start(input, kind) {
      const channel = window.MbgAssignmentAttachment;
      const view = input.ownerDocument.defaultView;
      if (!channel || !view || request && current(request) || !input.isConnected || input.matches(":disabled")) return;
      const id = Array.from(
        crypto.getRandomValues(new Uint8Array(16)),
        (byte) => byte.toString(16).padStart(2, "0")
      ).join("");
      request = {
        id,
        input,
        location: view.location.href,
        form: input.form,
        formValues: hiddenValues(input.form),
        files: Array.from(input.files || [])
      };
      window.clearTimeout(requestAckTimer);
      requestAckTimer = window.setTimeout(() => {
        if ((request == null ? void 0 : request.id) === id) transfer = request = null;
      }, 5e3);
      try {
        channel.postMessage(JSON.stringify({ id, kind, accept: input.accept.slice(0, 1024) }));
      } catch (_) {
        transfer = request = null;
      }
    }
    function attach(view) {
      try {
        const doc = view.document;
        if (__mbgConfig.drop && !dropDocuments.has(doc)) {
          dropDocuments.add(doc);
          doc.addEventListener("dragover", (event) => {
            if (!isFileDrag(event) || event.defaultPrevented) return;
            event.preventDefault();
            event.dataTransfer.dropEffect = "none";
          });
          doc.addEventListener("drop", (event) => {
            if (isFileDrag(event)) event.preventDefault();
          });
        }
        for (const input of Array.from(doc.querySelectorAll("input[type=file]"))) {
          let button2 = function(label, kind) {
            const element = doc.createElement("button");
            element.type = "button";
            element.textContent = label;
            element.setAttribute("data-mbg-" + kind + "-attachment", "");
            element.style.cssText = "margin:4px 8px;padding:6px 10px";
            element.addEventListener("click", (event) => {
              if (event.isTrusted) start(input, kind);
            });
            return element;
          };
          var button = button2;
          if (!input.parentNode) continue;
          let group = controls.get(input);
          if (!group) {
            group = doc.createElement("span");
            group.appendChild(button2("共有したファイルを添付", "share"));
            if (__mbgConfig.scan) group.appendChild(button2("撮ってPDFにする", "scan"));
            if (__mbgConfig.drop) group.appendChild(createAttachmentDropZone(input));
            controls.set(input, group);
          }
          group.querySelector("[data-mbg-share-attachment]").hidden = !shared;
          const scan = group.querySelector("[data-mbg-scan-attachment]");
          if (scan) scan.hidden = !acceptsAttachment(input, "答案.pdf", "application/pdf");
          const drop = group.querySelector("[data-mbg-attachment-drop]");
          if (drop) {
            const hidden = input.hidden || input.matches(":disabled");
            drop.hidden = hidden;
            drop.style.display = hidden ? "none" : "block";
          }
          if (group.previousSibling !== input) input.after(group);
        }
        for (let index = 0; index < view.frames.length; index++) attach(view.frames[index]);
      } catch (_) {
      }
    }
    window.__MBG_ASSIGNMENT_ATTACHMENT = {
      setShared(available) {
        if (shared !== available) {
          shared = available;
          attach(window);
        }
      },
      pending(id) {
        if ((request == null ? void 0 : request.id) !== id || !current(request)) return false;
        window.clearTimeout(requestAckTimer);
        return true;
      },
      begin(id, name, mime, size) {
        if ((request == null ? void 0 : request.id) !== id || !current(request) || !Number.isSafeInteger(size) || size < 1 || size > MAX_BYTES || !name || name.length > 250 || /[\u0000-\u001f/\\]/.test(name) || !acceptsAttachment(request.input, name, mime)) return false;
        transfer = { name, mime, size, received: 0, parts: [] };
        return true;
      },
      chunk(id, index, data) {
        if (!request || request.id !== id || !transfer || !current(request) || index !== transfer.parts.length || data.length > Math.ceil(CHUNK_BYTES / 3) * 4) return false;
        const raw = atob(data);
        if (!raw.length || raw.length > CHUNK_BYTES || transfer.received + raw.length > transfer.size) return false;
        transfer.parts.push(Uint8Array.from(raw, (character) => character.charCodeAt(0)));
        transfer.received += raw.length;
        return true;
      },
      finish(id) {
        if (!request || request.id !== id || !transfer) return false;
        const target = request;
        const file = transfer;
        transfer = request = null;
        if (file.received !== file.size || !current(target)) return false;
        return setAssignmentAttachment(target.input, new File(file.parts, file.name, { type: file.mime }));
      },
      cancel(id) {
        if ((request == null ? void 0 : request.id) === id) transfer = request = null;
      }
    };
    window.addEventListener("pagehide", () => {
      window.clearTimeout(requestAckTimer);
      transfer = request = null;
    });
    attach(window);
    watchPage(window, () => attach(window), { fallbackMs: 5e3, legacyIntervalMs: 1e3 });
  }
  installAssignmentAttachment();
})();
})(''';
const String _gakujoAssignmentAttachmentJsSuffix = r''');
''';
