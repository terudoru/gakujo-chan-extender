// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/upload_preview/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoUploadPreviewJs(Map<String, Object?> config) =>
    _gakujoUploadPreviewJsPrefix +
    jsonEncode(config) +
    _gakujoUploadPreviewJsSuffix;

const String _gakujoUploadPreviewJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  var __defProp = Object.defineProperty;
  var __defProps = Object.defineProperties;
  var __getOwnPropDescs = Object.getOwnPropertyDescriptors;
  var __getOwnPropSymbols = Object.getOwnPropertySymbols;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __propIsEnum = Object.prototype.propertyIsEnumerable;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __spreadValues = (a, b) => {
    for (var prop in b || (b = {}))
      if (__hasOwnProp.call(b, prop))
        __defNormalProp(a, prop, b[prop]);
    if (__getOwnPropSymbols)
      for (var prop of __getOwnPropSymbols(b)) {
        if (__propIsEnum.call(b, prop))
          __defNormalProp(a, prop, b[prop]);
      }
    return a;
  };
  var __spreadProps = (a, b) => __defProps(a, __getOwnPropDescs(b));

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

  // web_scripts/src/shared/image_bounds.ts
  function mbgValidateImage(blob) {
    if (!blob || typeof blob.size !== "number" || blob.size > 128 * 1024 * 1024 || typeof blob.slice !== "function") {
      return Promise.reject(new Error("画像のサイズを確認できません"));
    }
    return blob.slice(0, Math.min(blob.size, 262144)).arrayBuffer().then(function(buffer) {
      var b = new Uint8Array(buffer), v = new DataView(buffer), w = 0, h = 0;
      function four(i2, s) {
        return i2 + s.length <= b.length && Array.prototype.every.call(s, function(c, n) {
          return b[i2 + n] === c.charCodeAt(0);
        });
      }
      if (b.length >= 24 && b[0] === 137 && four(1, "PNG\r\n\n") && v.getUint32(8, false) === 13 && four(12, "IHDR")) {
        w = v.getUint32(16, false);
        h = v.getUint32(20, false);
        var chunk = 8, seenData = false;
        while (chunk + 12 <= b.length) {
          var chunkSize = v.getUint32(chunk, false);
          if (four(chunk + 4, "acTL")) throw new Error("アニメーション画像には対応していません");
          if (four(chunk + 4, "IDAT")) {
            seenData = true;
            break;
          }
          if (chunkSize > b.length - chunk - 12) break;
          chunk += 12 + chunkSize;
        }
        if (!seenData) throw new Error("画像ヘッダーを確認できません");
      } else if (b.length >= 4 && b[0] === 255 && b[1] === 216) {
        var i = 2;
        while (i + 4 <= b.length) {
          if (b[i++] !== 255) break;
          while (i < b.length && b[i] === 255) i++;
          if (i >= b.length) break;
          var marker = b[i++];
          if (marker === 217 || marker === 218) break;
          if (marker === 1 || marker >= 208 && marker <= 215) continue;
          if (i + 2 > b.length) break;
          var size = v.getUint16(i, false);
          if (size < 2 || i + size > b.length) break;
          if (marker >= 192 && marker <= 195 || marker >= 197 && marker <= 199 || marker >= 201 && marker <= 203 || marker >= 205 && marker <= 207) {
            if (size >= 8) {
              h = v.getUint16(i + 3, false);
              w = v.getUint16(i + 5, false);
            }
            break;
          }
          i += size;
        }
      } else if (b.length >= 30 && four(0, "RIFF") && four(8, "WEBP")) {
        if (four(12, "VP8X")) {
          if ((b[20] & 2) !== 0) throw new Error("アニメーション画像には対応していません");
          w = 1 + b[24] + (b[25] << 8) + (b[26] << 16);
          h = 1 + b[27] + (b[28] << 8) + (b[29] << 16);
        } else if (four(12, "VP8L") && b[20] === 47) {
          w = 1 + ((b[21] | b[22] << 8) & 16383);
          h = 1 + ((b[22] >> 6 | b[23] << 2 | b[24] << 10) & 16383);
        } else if (four(12, "VP8 ") && b[23] === 157 && b[24] === 1 && b[25] === 42) {
          w = v.getUint16(26, true) & 16383;
          h = v.getUint16(28, true) & 16383;
        }
      }
      if (!w || !h || w > 1e4 || h > 1e4 || w * h > 16e6) {
        throw new Error("画像の形式またはピクセル数が安全な範囲を超えています");
      }
      return { width: w, height: h };
    });
  }

  // web_scripts/src/shared/assignment_attachment.ts
  function acceptsAttachment(input, name, mime) {
    const filters = input.accept.toLowerCase().split(",").map((value) => value.trim()).filter(Boolean);
    const fileName = name.toLowerCase();
    const type = mime.toLowerCase();
    return !filters.length || filters.some((filter) => filter.startsWith(".") ? fileName.endsWith(filter) : filter.endsWith("/*") ? type.startsWith(filter.slice(0, -1)) : type === filter);
  }
  function setAssignmentAttachment(input, file, replace) {
    var _a;
    const view = input.ownerDocument.defaultView;
    if (!view || !input.isConnected || input.type !== "file" || input.matches(":disabled") || !acceptsAttachment(input, file.name, file.type)) return false;
    const current = Array.from(input.files || []);
    if (replace && !current.includes(replace)) return false;
    const next = replace ? current.map((item) => item === replace ? file : item) : input.multiple ? [...current, file] : [file];
    try {
      const transfer = new view.DataTransfer();
      next.forEach((item) => transfer.items.add(item));
      input.files = transfer.files;
      if (((_a = input.files) == null ? void 0 : _a.length) !== next.length) return false;
    } catch (_) {
      return false;
    }
    input.dispatchEvent(new view.Event("input", { bubbles: true, composed: true }));
    input.dispatchEvent(new view.Event("change", { bubbles: true }));
    return true;
  }

  // web_scripts/src/upload_preview/worksheet_pdf.ts
  var penThickness = 1.6;
  function pdfPoint(viewport, point) {
    const [x, y] = viewport.convertToPdfPoint(point.x * viewport.width, point.y * viewport.height);
    return { x, y };
  }
  function worksheetTextPlacement(viewport, origin, width, height) {
    const left = pdfPoint(viewport, { x: origin.x, y: origin.y + height });
    const right = pdfPoint(viewport, { x: origin.x + width, y: origin.y + height });
    const top = pdfPoint(viewport, origin);
    return __spreadProps(__spreadValues({}, left), {
      width: Math.hypot(right.x - left.x, right.y - left.y),
      height: Math.hypot(top.x - left.x, top.y - left.y),
      degrees: Math.atan2(right.y - left.y, right.x - left.x) * 180 / Math.PI
    });
  }
  async function writeWorksheetPdf(library, source, editsByPage) {
    const output = await library.PDFDocument.load(source, { updateMetadata: false });
    const color = library.rgb(23 / 255, 61 / 255, 145 / 255);
    for (const [pageNumber, edited] of editsByPage) {
      const page = output.getPage(pageNumber - 1);
      for (const edit of edited.edits) {
        if (edit.kind === "text") {
          const image = await output.embedPng(edit.canvas.toDataURL("image/png"));
          const placement = worksheetTextPlacement(edited.viewport, edit.origin, edit.width, edit.height);
          page.drawImage(image, {
            x: placement.x,
            y: placement.y,
            width: placement.width,
            height: placement.height,
            rotate: library.degrees(placement.degrees)
          });
        } else {
          const points = edit.points.map((point) => pdfPoint(edited.viewport, point));
          if (points.length === 1) page.drawCircle(__spreadProps(__spreadValues({}, points[0]), { size: penThickness / 2, color }));
          for (let index = 1; index < points.length; index++) {
            page.drawLine({ start: points[index - 1], end: points[index], thickness: penThickness, color, lineCap: 1 });
          }
        }
      }
    }
    return output.save();
  }

  // web_scripts/src/upload_preview/worksheet_editor.ts
  var MAX_WORKSHEET_PDF_BYTES = 64 * 1024 * 1024;
  var maxEdits = 150;
  var maxPoints = 1024;
  var penColor = "#173d91";
  var fontSize = 13;
  function loadLibrary(signal) {
    const owner = window;
    const available = () => owner["__MBG_UPLOAD_LIBRARY_READY_preview-edit"] && window.pdfjsLib && window.__MBG_PDF_WORKER_URL && owner.PDFLib;
    const existing = available();
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const channel = window.MbgUploadCompression;
      if (!channel || signal.aborted) {
        reject(new Error());
        return;
      }
      const timer = window.setTimeout(failed, 3e4);
      signal.addEventListener("abort", failed, { once: true });
      owner.__MBG_UPLOAD_PREVIEW_EDIT_LIBRARY_LOADED = loaded;
      try {
        channel.postMessage("preview-edit");
      } catch (_) {
        failed();
      }
      function cleanup() {
        window.clearTimeout(timer);
        signal.removeEventListener("abort", failed);
        if (owner.__MBG_UPLOAD_PREVIEW_EDIT_LIBRARY_LOADED === loaded) {
          delete owner.__MBG_UPLOAD_PREVIEW_EDIT_LIBRARY_LOADED;
        }
      }
      function failed() {
        cleanup();
        reject(new Error());
      }
      function loaded() {
        const library = available();
        cleanup();
        if (library) resolve(library);
        else reject(new Error());
      }
    });
  }
  function getPdf(data, worker) {
    const pdfWorker = window.pdfjsLib.PDFWorker.fromPort({ port: worker });
    function resource(name, maps) {
      if (!maps || !/^[A-Za-z0-9_.-]{1,80}$/.test(name) || !Object.prototype.hasOwnProperty.call(maps, name)) {
        throw new Error();
      }
      return Uint8Array.from(atob(maps[name]), (character) => character.charCodeAt(0));
    }
    class CMapReaderFactory {
      async fetch({ name }) {
        return { cMapData: resource(name, window.__MBG_PDF_CMAPS), compressionType: 1 };
      }
    }
    class StandardFontDataFactory {
      async fetch({ filename }) {
        return resource(filename, window.__MBG_PDF_STANDARD_FONTS);
      }
    }
    return window.pdfjsLib.getDocument({
      data: new Uint8Array(data),
      worker: pdfWorker,
      CMapReaderFactory,
      StandardFontDataFactory,
      cMapPacked: true,
      useWorkerFetch: false,
      enableXfa: false,
      isEvalSupported: false,
      useSystemFonts: true,
      stopAtErrors: true,
      maxImageSize: 16e6
    });
  }
  function makeTextCanvas(doc, text, widthLimit, heightLimit) {
    const canvas = doc.createElement("canvas");
    const context = canvas.getContext("2d");
    if (!context || widthLimit < fontSize) throw new Error();
    const density = 3;
    const padding = 2;
    const lineHeight = fontSize * 1.3;
    const font = fontSize + "px sans-serif";
    context.font = font;
    const lines = [];
    for (const paragraph of text.split("\n")) {
      let line = "";
      for (const character of Array.from(paragraph)) {
        if (line && context.measureText(line + character).width > widthLimit - 2 * padding) {
          lines.push(line);
          line = "";
        }
        line += character;
      }
      lines.push(line);
    }
    const width = Math.ceil(Math.max(...lines.map((line) => context.measureText(line).width)) + 2 * padding);
    const height = Math.ceil(lines.length * lineHeight + 2 * padding);
    if (width > widthLimit || height > heightLimit || width * height > 7e4) throw new Error();
    canvas.width = width * density;
    canvas.height = height * density;
    context.scale(density, density);
    context.font = font;
    context.fillStyle = penColor;
    context.textBaseline = "top";
    lines.forEach((line, index) => context.fillText(line, padding, padding + index * lineHeight));
    return { canvas, width, height };
  }
  function openWorksheetEditor(options) {
    const { document: doc, file, container } = options;
    const overlay = doc.createElement("div");
    overlay.setAttribute("role", "dialog");
    overlay.setAttribute("aria-modal", "true");
    overlay.setAttribute("aria-label", "PDFに書き込む");
    overlay.setAttribute("data-mbg-worksheet-editor", "");
    overlay.style.cssText = "inset:0;z-index:2147483647;background:#eee;color:#161616;display:flex;flex-direction:column;font:16px sans-serif";
    overlay.style.position = container ? "absolute" : "fixed";
    const bar = doc.createElement("div");
    bar.style.cssText = "display:flex;flex-wrap:wrap;gap:5px;align-items:center;padding:8px;background:#fff";
    const status = doc.createElement("div");
    status.setAttribute("role", "status");
    status.style.cssText = "min-height:1em;padding:4px 8px;background:#fff;font:14px sans-serif";
    const content = doc.createElement("div");
    content.style.cssText = "overflow:auto;flex:1;min-height:0;padding:8px;overscroll-behavior:contain";
    const stage = doc.createElement("div");
    stage.style.cssText = "position:relative;line-height:0;margin:0 auto;background:#fff";
    const raster = doc.createElement("canvas");
    raster.style.cssText = "width:100%;height:100%;display:block";
    const ink = doc.createElement("canvas");
    ink.style.cssText = "position:absolute;inset:0;width:100%;height:100%";
    ink.setAttribute("aria-label", "PDFの編集面");
    stage.append(raster, ink);
    content.appendChild(stage);
    const abort = new AbortController();
    const pages = /* @__PURE__ */ new Map();
    let closed = false;
    let rendering = false;
    let exporting = false;
    let worker;
    let task;
    let render;
    let pdf;
    let library;
    let pageNumber = 1;
    let zoom = 1;
    let viewport;
    let tool = "view";
    let stroke;
    let textOrigin;
    let editCount = 0;
    let repaintFrame;
    function button(label, action) {
      const control = doc.createElement("button");
      control.type = "button";
      control.textContent = label;
      control.style.cssText = "font:inherit;padding:5px 8px;min-height:34px";
      control.addEventListener("click", action);
      return control;
    }
    const pageLabel = doc.createElement("span");
    const previous = button("前のページ", () => navigate(-1));
    const next = button("次のページ", () => navigate(1));
    const smaller = button("縮小", () => changeZoom(0.8));
    const larger = button("拡大", () => changeZoom(1.25));
    const view = button("閲覧", () => changeTool("view"));
    const pen = button("ペン", () => changeTool("pen"));
    const text = button("文字", () => changeTool("text"));
    const undo = button("元に戻す", undoLast);
    const save = button("書き込んだPDFを使う", () => {
      void exportPdf();
    });
    const close = button("閉じる", closeEditor);
    const discard = button("編集を破棄", () => dispose(true));
    const keepEditing = button("編集に戻る", () => showDiscard(false));
    discard.hidden = keepEditing.hidden = true;
    bar.append(previous, pageLabel, next, smaller, larger, view, pen, text, undo, save, close, discard, keepEditing);
    const textBar = doc.createElement("div");
    textBar.style.cssText = "display:none;gap:5px;align-items:center;padding:4px 8px;background:#fff;flex-wrap:wrap";
    const textInput = doc.createElement("textarea");
    textInput.rows = 2;
    textInput.maxLength = 200;
    textInput.setAttribute("aria-label", "PDFに挿入する文字");
    textInput.style.cssText = "font:16px sans-serif;min-width:0;flex:1";
    textBar.append(textInput, button("文字を挿入", insertText), button("キャンセル", resetText));
    overlay.append(bar, textBar, status, content);
    (container || doc.documentElement || doc.body).appendChild(overlay);
    close.focus();
    status.textContent = "PDFを読み込み中…";
    updateControls();
    void start();
    async function start() {
      try {
        if (file.size < 1 || file.size > MAX_WORKSHEET_PDF_BYTES) {
          status.textContent = "64 MiB以下のPDFに書き込めます。";
          return;
        }
        library = await loadLibrary(abort.signal);
        if (closed) return;
        const data = await file.arrayBuffer();
        if (closed) return;
        worker = new Worker(window.__MBG_PDF_WORKER_URL);
        task = getPdf(data, worker);
        const document2 = await task.promise;
        if (closed) return;
        if (document2.numPages < 1 || document2.numPages > 2e3) throw new Error();
        pdf = document2;
        await drawPage();
      } catch (_) {
        if (!closed) status.textContent = "このPDFは編集用に開けませんでした。";
      }
    }
    function closeEditor() {
      if (editCount) showDiscard(true);
      else dispose(true);
    }
    function showDiscard(show) {
      resetText();
      discard.hidden = keepEditing.hidden = !show;
      status.textContent = show ? "書き込んだ内容を破棄しますか？" : "";
      updateControls();
      (show ? keepEditing : close).focus();
    }
    function dispose(notify) {
      var _a;
      if (closed) return;
      closed = true;
      abort.abort();
      if (repaintFrame !== void 0) window.cancelAnimationFrame(repaintFrame);
      releaseStroke();
      try {
        render == null ? void 0 : render.cancel();
      } catch (_) {
      }
      if (task) void task.destroy().catch(() => {
      });
      if (worker) worker.terminate();
      overlay.remove();
      if (notify) (_a = options.onClose) == null ? void 0 : _a.call(options);
    }
    function updateControls() {
      var _a;
      const prompt = !discard.hidden;
      const blocked = rendering || exporting || prompt;
      previous.disabled = blocked || pageNumber === 1;
      next.disabled = blocked || !pdf || pageNumber >= pdf.numPages;
      smaller.disabled = blocked || !viewport || zoom <= 1;
      larger.disabled = blocked || !viewport || zoom >= 4;
      for (const [name, control] of [["view", view], ["pen", pen], ["text", text]]) {
        control.disabled = blocked || !viewport;
        control.setAttribute("aria-pressed", String(tool === name));
        control.style.fontWeight = tool === name ? "bold" : "normal";
      }
      undo.disabled = blocked || !((_a = pages.get(pageNumber)) == null ? void 0 : _a.edits.length);
      save.disabled = blocked || !editCount;
      close.disabled = exporting || prompt;
      ink.style.touchAction = blocked || tool === "view" ? "auto" : "none";
      ink.style.cursor = tool === "view" ? "auto" : "crosshair";
      pageLabel.textContent = pdf ? pageNumber + " / " + pdf.numPages : "";
    }
    function navigate(offset) {
      pageNumber += offset;
      resetText();
      content.scrollTop = 0;
      void drawPage();
    }
    function changeZoom(factor) {
      zoom = Math.max(1, Math.min(4, zoom * factor));
      resetText();
      void drawPage();
    }
    function changeTool(nextTool) {
      releaseStroke();
      scheduleRepaint();
      resetText();
      tool = nextTool;
      status.textContent = tool === "pen" ? "PDFの上をなぞって書き込めます。" : tool === "text" ? "文字を入れる位置を選んでください。" : "";
      updateControls();
    }
    async function drawPage() {
      if (!pdf || rendering || closed) return;
      releaseStroke();
      viewport = void 0;
      stage.style.visibility = "hidden";
      rendering = true;
      updateControls();
      try {
        const page = await pdf.getPage(pageNumber);
        if (closed) return;
        const base = page.getViewport({ scale: 1 });
        if (!Number.isFinite(base.width) || !Number.isFinite(base.height) || base.width <= 0 || base.height <= 0) throw new Error();
        const cssScale = Math.min(1.5, Math.max(180, content.clientWidth - 16) / base.width) * zoom;
        const scale = Math.min(
          cssScale * Math.min(2, window.devicePixelRatio || 1),
          Math.sqrt(8e6 / base.width / base.height),
          4096 / Math.max(base.width, base.height)
        );
        const scaled = page.getViewport({ scale });
        const context = raster.getContext("2d");
        if (!context) throw new Error();
        raster.width = ink.width = Math.max(1, Math.ceil(scaled.width));
        raster.height = ink.height = Math.max(1, Math.ceil(scaled.height));
        stage.style.width = Math.min(8192, base.width * cssScale) + "px";
        stage.style.height = Math.min(8192, base.height * cssScale) + "px";
        render = page.render({ canvasContext: context, viewport: scaled });
        await render.promise;
        if (closed) return;
        viewport = base;
        stage.style.visibility = "";
        repaint();
        status.textContent = "";
      } catch (_) {
        if (!closed) status.textContent = "ページを表示できませんでした。";
      } finally {
        rendering = false;
        if (!closed) updateControls();
      }
    }
    function getPoint(event) {
      const bounds = ink.getBoundingClientRect();
      return {
        x: Math.max(0, Math.min(1, (event.clientX - bounds.left) / Math.max(1, bounds.width))),
        y: Math.max(0, Math.min(1, (event.clientY - bounds.top) / Math.max(1, bounds.height)))
      };
    }
    function repaint() {
      var _a, _b;
      const context = ink.getContext("2d");
      if (!context || !viewport) return;
      context.clearRect(0, 0, ink.width, ink.height);
      context.strokeStyle = context.fillStyle = penColor;
      context.lineCap = context.lineJoin = "round";
      context.lineWidth = penThickness * ink.width / viewport.width;
      function paintPen(points) {
        context.beginPath();
        if (points.length === 1) {
          context.arc(points[0].x * ink.width, points[0].y * ink.height, context.lineWidth / 2, 0, Math.PI * 2);
          context.fill();
          return;
        }
        context.moveTo(points[0].x * ink.width, points[0].y * ink.height);
        for (let index = 1; index < points.length; index++) {
          context.lineTo(points[index].x * ink.width, points[index].y * ink.height);
        }
        context.stroke();
      }
      for (const edit of (_b = (_a = pages.get(pageNumber)) == null ? void 0 : _a.edits) != null ? _b : []) {
        if (edit.kind === "pen") paintPen(edit.points);
        else context.drawImage(
          edit.canvas,
          edit.origin.x * ink.width,
          edit.origin.y * ink.height,
          edit.width * ink.width,
          edit.height * ink.height
        );
      }
      if (stroke) paintPen(stroke.points);
    }
    function scheduleRepaint() {
      if (repaintFrame === void 0) {
        repaintFrame = window.requestAnimationFrame(() => {
          repaintFrame = void 0;
          if (!closed) repaint();
        });
      }
    }
    function addEdit(edit) {
      if (!viewport || editCount >= maxEdits) return;
      let page = pages.get(pageNumber);
      if (!page) {
        page = { viewport, edits: [] };
        pages.set(pageNumber, page);
      }
      page.edits.push(edit);
      editCount++;
      scheduleRepaint();
      updateControls();
    }
    function releaseStroke() {
      const current = stroke;
      if (!current) return;
      stroke = void 0;
      if (ink.hasPointerCapture(current.pointerId)) ink.releasePointerCapture(current.pointerId);
    }
    function undoLast() {
      const page = pages.get(pageNumber);
      if (!page || !page.edits.pop()) return;
      if (!page.edits.length) pages.delete(pageNumber);
      editCount--;
      scheduleRepaint();
      updateControls();
    }
    function resetText() {
      textOrigin = void 0;
      textInput.value = "";
      textBar.style.display = "none";
    }
    function insertText() {
      if (!viewport || !textOrigin || exporting || rendering) return;
      const value = textInput.value.trim();
      if (!value) {
        status.textContent = "文字を入力してください。";
        return;
      }
      try {
        const placed = makeTextCanvas(doc, value, (1 - textOrigin.x) * viewport.width, (1 - textOrigin.y) * viewport.height);
        addEdit({
          kind: "text",
          origin: textOrigin,
          canvas: placed.canvas,
          width: placed.width / viewport.width,
          height: placed.height / viewport.height
        });
        resetText();
        text.focus();
        status.textContent = "文字を挿入しました。";
      } catch (_) {
        status.textContent = "文字がページ内に収まる位置を選んでください。";
      }
    }
    async function exportPdf() {
      if (!library || exporting || rendering || !editCount) return;
      releaseStroke();
      resetText();
      exporting = true;
      status.textContent = "記入済みPDFを作成中…";
      updateControls();
      try {
        const buffer = await file.arrayBuffer();
        if (closed) return;
        const bytes = await writeWorksheetPdf(library, buffer, pages);
        if (closed) return;
        if (bytes.byteLength > MAX_WORKSHEET_PDF_BYTES) {
          status.textContent = "記入後のPDFが64 MiBを超えています。";
          return;
        }
        const originalName = file.name.replace(/[/\\\u0000-\u001f\u007f]/g, "_").replace(/\.pdf$/i, "").trim();
        const editedName = (originalName.slice(0, 100) || "答案") + "_記入済み.pdf";
        await options.onExport(new File([bytes], editedName, { type: "application/pdf" }));
        dispose(true);
      } catch (_) {
        if (!closed) status.textContent = "PDFを渡せませんでした。書き込んだ内容は残っています。";
      } finally {
        exporting = false;
        if (!closed) updateControls();
      }
    }
    overlay.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      event.stopPropagation();
      event.preventDefault();
      if (exporting) return;
      if (textOrigin) resetText();
      else if (!discard.hidden) showDiscard(false);
      else closeEditor();
    });
    ink.addEventListener("pointerdown", (event) => {
      if (!viewport || stroke || rendering || exporting || !discard.hidden || tool === "view" || event.button !== 0 || !event.isPrimary) return;
      if (editCount >= maxEdits) {
        status.textContent = "これ以上書き込みを追加できません。";
        return;
      }
      const point = getPoint(event);
      if (tool === "text") {
        textOrigin = point;
        textBar.style.display = "flex";
        textInput.focus();
        return;
      }
      event.preventDefault();
      stroke = { pointerId: event.pointerId, points: [point] };
      ink.setPointerCapture(event.pointerId);
      scheduleRepaint();
    });
    ink.addEventListener("pointermove", (event) => {
      if ((stroke == null ? void 0 : stroke.pointerId) !== event.pointerId || stroke.points.length >= maxPoints) return;
      const point = getPoint(event);
      const points = stroke.points;
      const last = points[points.length - 1];
      if (Math.hypot((point.x - last.x) * ink.width, (point.y - last.y) * ink.height) < 1) return;
      points.push(point);
      scheduleRepaint();
    });
    ink.addEventListener("pointerup", (event) => {
      if ((stroke == null ? void 0 : stroke.pointerId) !== event.pointerId) return;
      const { points } = stroke;
      releaseStroke();
      addEdit({ kind: "pen", points });
    });
    function discardStroke() {
      releaseStroke();
      scheduleRepaint();
    }
    ink.addEventListener("pointercancel", discardStroke);
    ink.addEventListener("lostpointercapture", discardStroke);
    return () => dispose(false);
  }

  // web_scripts/src/upload_preview/document_actions.ts
  var MAX_HASH_BYTES = 64 * 1024 * 1024;
  var CHUNK_BYTES = 256 * 1024;
  var nextRead = 0;
  var readers = /* @__PURE__ */ new Map();
  async function loadPdfReadingProgress(bytes) {
    var _a;
    const channel = window.MbgPdfReadingProgress;
    if (!channel || !((_a = globalThis.crypto) == null ? void 0 : _a.subtle) || bytes.byteLength > MAX_HASH_BYTES) return null;
    try {
      let flush2 = function() {
        window.clearTimeout(timer);
        timer = void 0;
        if (lastPage !== null && lastPage !== savedPage) {
          try {
            channel.postMessage(JSON.stringify({ key, page: lastPage }));
            savedPage = lastPage;
          } catch (_) {
          }
        }
      };
      var flush = flush2;
      const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
      const key = Array.from(digest, (value) => value.toString(16).padStart(2, "0")).join("");
      window.__MBG_PDF_READING_PROGRESS = (id, page) => {
        var _a2;
        return (_a2 = readers.get(id)) == null ? void 0 : _a2(page);
      };
      const request = nextRead = nextRead % 2147483647 + 1;
      const storedPage = await new Promise((resolve) => {
        const timer2 = window.setTimeout(() => {
          readers.delete(request);
          resolve(null);
        }, 1200);
        readers.set(request, (page) => {
          window.clearTimeout(timer2);
          readers.delete(request);
          resolve(page);
        });
        channel.postMessage(JSON.stringify({ key, request }));
      });
      const initialPage = typeof storedPage === "number" && Number.isInteger(storedPage) && storedPage >= 1 && storedPage <= 2e3 ? storedPage : null;
      let lastPage = initialPage;
      let savedPage = initialPage;
      let timer;
      return {
        initialPage: initialPage != null ? initialPage : 1,
        pageChanged(page) {
          if (!Number.isInteger(page) || page < 1 || page > 2e3 || page === lastPage) return;
          lastPage = page;
          window.clearTimeout(timer);
          timer = window.setTimeout(flush2, 500);
        },
        flush: flush2
      };
    } catch (_) {
      return null;
    }
  }
  async function saveWorksheetFile(file) {
    const channel = window.MbgWorksheetExport;
    if (!channel || window.__MBG_WORKSHEET_EXPORT || file.size > MAX_HASH_BYTES) throw new Error("保存機能を使えません");
    const id = Array.from(
      crypto.getRandomValues(new Uint8Array(16)),
      (byte) => byte.toString(16).padStart(2, "0")
    ).join("");
    const contents = new Uint8Array(await file.arrayBuffer());
    return new Promise((resolve, reject) => {
      const timer = window.setTimeout(() => finish(false), 3e5);
      function finish(ok) {
        window.clearTimeout(timer);
        delete window.__MBG_WORKSHEET_EXPORT;
        if (ok) resolve();
        else reject(new Error("PDFを保存できませんでした"));
      }
      window.__MBG_WORKSHEET_EXPORT = {
        chunk(candidate, offset) {
          if (candidate !== id || !Number.isSafeInteger(offset) || offset < 0 || offset >= file.size) return null;
          const bytes = contents.subarray(offset, offset + CHUNK_BYTES);
          let binary = "";
          for (let index = 0; index < bytes.length; index += 8192) {
            binary += String.fromCharCode(...bytes.subarray(index, index + 8192));
          }
          return btoa(binary);
        },
        reply(candidate, ok) {
          if (candidate === id) finish(ok === true);
        }
      };
      try {
        channel.postMessage(JSON.stringify({ id, name: file.name, size: file.size }));
      } catch (_) {
        finish(false);
      }
    });
  }

  // web_scripts/src/upload_preview/main.ts
  var MAX_PDF_PREVIEW_BYTES = 512 * 1024 * 1024;
  function uploadPreview() {
    var mbgCompactAndroid = __mbgConfig.compactAndroid;
    if (window.__MBG_UPLOAD_PREVIEW_INSTALLED) return;
    window.__MBG_UPLOAD_PREVIEW_INSTALLED = true;
    function mbgPreviewReport(state) {
      var channel = window.MbgPreviewNavigation;
      if (channel && channel.postMessage) channel.postMessage(state);
    }
    window.__MBG_PREVIEW_NAVIGATE = function(direction) {
      var preview = window.__MBG_ACTIVE_UPLOAD_PREVIEW;
      if (!preview || typeof preview.setVisible !== "function") return false;
      if (direction === "back" && preview.visible) preview.setVisible(false);
      else if (direction === "forward" && !preview.visible) preview.setVisible(true);
      else if (direction === "forward" && preview.visible) return true;
      else return false;
      return true;
    };
    window.__MBG_PREVIEW_ZOOM = function(factor) {
      var preview = window.__MBG_ACTIVE_UPLOAD_PREVIEW;
      if (!preview || !preview.visible || !preview.zoomBy || !Number.isFinite(factor) || factor <= 0) return false;
      preview.zoomBy(Math.max(0.75, Math.min(1.33, factor)));
      return true;
    };
    var waiters = [];
    window.__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED = function() {
      var pending = waiters.splice(0);
      pending.forEach(function(done) {
        done();
      });
    };
    function pdfLibrary(setCancel) {
      if (window.__MBG_PDF_PREVIEW_URL) return Promise.resolve();
      if (window.pdfjsLib && window.pdfjsViewer && window.__MBG_PDF_WORKER_URL && window.__MBG_PDF_VIEWER_CSS && window.__MBG_PDF_CMAPS && window.__MBG_PDF_STANDARD_FONTS) return Promise.resolve();
      return new Promise(function(resolve, reject) {
        var channel = window.MbgUploadCompression;
        if (!channel || !channel.postMessage) {
          reject(new Error("PDFプレビューを読み込めません"));
          return;
        }
        var timer = window.setTimeout(function() {
          var index = waiters.indexOf(done);
          if (index >= 0) waiters.splice(index, 1);
          setCancel(null);
          reject(new Error("PDFプレビューの読み込みがタイムアウトしました"));
        }, 3e4);
        function done() {
          window.clearTimeout(timer);
          setCancel(null);
          if (window.__MBG_PDF_PREVIEW_URL || window.pdfjsLib && window.pdfjsViewer && window.__MBG_PDF_WORKER_URL && window.__MBG_PDF_VIEWER_CSS && window.__MBG_PDF_CMAPS && window.__MBG_PDF_STANDARD_FONTS) resolve();
          else reject(new Error("PDFプレビューを読み込めません"));
        }
        waiters.push(done);
        setCancel(function() {
          window.clearTimeout(timer);
          var index = waiters.indexOf(done);
          if (index >= 0) waiters.splice(index, 1);
          resolve();
        });
        if (waiters.length === 1) channel.postMessage("preview");
      });
    }
    function mbgDisplayFileName(name) {
      if (!/%[0-9A-Fa-f]{2}/.test(name)) return name;
      try {
        return decodeURIComponent(name);
      } catch (_) {
        return name;
      }
    }
    function documents() {
      var result = [], seen = /* @__PURE__ */ new Set();
      function visit(doc) {
        if (!doc || seen.has(doc) || result.length >= 64) return;
        seen.add(doc);
        result.push(doc);
        var frames = doc.querySelectorAll("iframe,frame");
        for (var i = 0; i < frames.length && result.length < 64; i++) {
          try {
            visit(frames[i].contentWindow.document);
          } catch (e) {
          }
        }
      }
      visit(document);
      return result;
    }
    function show(input, file, onClosed, initiallyVisible, editOnOpen = false) {
      var owner = window;
      try {
        if (window.top && window.top.location.origin === window.location.origin) owner = window.top;
      } catch (_) {
      }
      var previousPreview = owner.__MBG_ACTIVE_UPLOAD_PREVIEW;
      var inheritedToken = previousPreview && previousPreview.__mbgToken;
      if (previousPreview && typeof previousPreview.close === "function") previousPreview.close();
      var doc = input.ownerDocument;
      var remote = input.type === "hidden";
      var progress = null;
      var stopEdit;
      var overlay = doc.createElement("div");
      overlay.setAttribute("role", "dialog");
      overlay.setAttribute("aria-modal", "true");
      overlay.setAttribute("aria-label", "ファイルのプレビュー");
      overlay.style.cssText = "position:fixed;inset:0;z-index:2147483647;background:#fff;color:#111;display:flex;flex-direction:column;font:16px sans-serif";
      var bar = doc.createElement("div");
      bar.style.cssText = "display:flex;gap:4px;align-items:center;box-sizing:border-box;height:48px;min-height:48px;padding:0 8px;flex-wrap:nowrap;background:#fff;border-bottom:1px solid #ddd";
      var flutterViewerActive = false;
      var sourceWindow = doc.defaultView || window;
      var viewport = sourceWindow.visualViewport;
      var rootViewport = window.visualViewport;
      var previewFrame = null;
      function displayedScale() {
        var scale = viewport && Number(viewport.scale);
        if (!(scale > 0)) scale = 1;
        if (sourceWindow === window) return scale;
        try {
          var rootScale = rootViewport && Number(rootViewport.scale);
          if (rootScale > 0) scale *= rootScale;
          var current = sourceWindow;
          for (var depth = 0; current !== window && depth < 64; depth++) {
            var element = current.frameElement;
            if (!element) break;
            if (element.offsetWidth && element.getBoundingClientRect) {
              var ratio = element.getBoundingClientRect().width / element.offsetWidth;
              if (ratio > 0 && isFinite(ratio)) scale *= ratio;
            }
            current = current.parent;
            if (!current) break;
          }
        } catch (_) {
        }
        return scale;
      }
      function resizeToolbar() {
        var scale = displayedScale();
        bar.style.zoom = String(scale > 0 ? Math.min(3, Math.max(1, 1 / scale)) : 1);
        var screen = sourceWindow.screen;
        var compact = !!(mbgCompactAndroid && previewFrame && viewport && screen && screen.width > screen.height && viewport.height * scale < 180);
        bar.style.display = flutterViewerActive || compact ? "none" : "flex";
        if (visual && textZoom) visual.style.zoom = bar.style.zoom;
        if (previewFrame) {
          var frameScale = scale > 0 ? Math.max(0.1, Math.min(5, scale)) : 1;
          previewFrame.style.width = frameScale * 100 + "%";
          previewFrame.style.height = frameScale * 100 + "%";
          previewFrame.style.transform = "scale(" + 1 / frameScale + ")";
          previewFrame.style.transformOrigin = "top left";
        }
        if (viewport && viewport.width > 0 && viewport.height > 0) {
          overlay.style.left = (viewport.offsetLeft || 0) + "px";
          overlay.style.top = (viewport.offsetTop || 0) + "px";
          overlay.style.width = viewport.width + "px";
          overlay.style.height = viewport.height + "px";
          overlay.style.right = "auto";
          overlay.style.bottom = "auto";
        }
      }
      resizeToolbar();
      if (viewport) {
        viewport.addEventListener("resize", resizeToolbar);
        viewport.addEventListener("scroll", resizeToolbar);
      }
      if (rootViewport && rootViewport !== viewport) {
        rootViewport.addEventListener("resize", resizeToolbar);
        rootViewport.addEventListener("scroll", resizeToolbar);
      }
      var title = doc.createElement("strong");
      title.textContent = mbgDisplayFileName(file.name);
      title.style.cssText = "flex:1 1 0;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap";
      var close = doc.createElement("button");
      close.type = "button";
      close.textContent = "×";
      close.setAttribute("aria-label", "閉じる");
      close.title = "閉じる";
      var previous = doc.createElement("button");
      previous.type = "button";
      previous.textContent = "前へ";
      var next = doc.createElement("button");
      next.type = "button";
      next.textContent = "次へ";
      var zoomOut = doc.createElement("button");
      zoomOut.type = "button";
      zoomOut.textContent = "縮小";
      var zoomIn = doc.createElement("button");
      zoomIn.type = "button";
      zoomIn.textContent = "拡大";
      var imageZoomLabel = doc.createElement("span");
      imageZoomLabel.hidden = true;
      imageZoomLabel.setAttribute("aria-label", "表示倍率");
      var count = doc.createElement("span");
      [previous, next, zoomOut, zoomIn, close].forEach(function(button) {
        button.style.cssText = "flex:none;padding:4px 6px";
      });
      bar.append(title, previous, count, next, zoomOut, imageZoomLabel, zoomIn, close);
      var body = doc.createElement("div");
      body.style.cssText = "overflow:auto;flex:1;text-align:center;padding:12px";
      var status = doc.createElement("p");
      status.textContent = "読み込み中…";
      body.appendChild(status);
      overlay.append(bar, body);
      (doc.documentElement || doc.body).appendChild(overlay);
      var gestureGeneration = 0;
      var closed = false, pdfStopped = false, worker = null, task = null, pdf = null, objectUrl = null, visual = null, zoom = 100, watchdog = null;
      var reader = null, cancelLibrary = null, pdfViewerCleanup = null, imageGestureCleanup = null;
      var textZoom = false;
      var detachWatcher = window.setInterval(function() {
        var detached = input.isConnected === false;
        try {
          if (sourceWindow !== window && (!sourceWindow.frameElement || sourceWindow.frameElement.isConnected === false)) detached = true;
        } catch (_) {
          detached = true;
        }
        if (detached) cleanup();
      }, 1e3);
      var preview = { close: cleanup, visible: initiallyVisible !== false, setVisible };
      if (inheritedToken) preview.__mbgToken = inheritedToken;
      owner.__MBG_ACTIVE_UPLOAD_PREVIEW = preview;
      function setVisible(visible) {
        if (closed) return;
        gestureGeneration++;
        preview.visible = visible;
        overlay.style.display = visible ? "flex" : "none";
        if (!visible && visual && /^(AUDIO|VIDEO)$/i.test(visual.tagName || "")) {
          try {
            visual.pause();
          } catch (_) {
          }
        }
        mbgPreviewReport(visible ? "visible" : "hidden");
      }
      setVisible(preview.visible);
      function stopPdf() {
        pdfStopped = true;
        if (watchdog) {
          window.clearTimeout(watchdog);
          watchdog = null;
        }
        if (cancelLibrary) {
          cancelLibrary();
          cancelLibrary = null;
        }
        if (reader) {
          try {
            reader.abort();
          } catch (e) {
          }
          reader = null;
        }
        if (visual && /^(AUDIO|VIDEO)$/i.test(visual.tagName || "")) {
          try {
            visual.pause();
            visual.removeAttribute("src");
            visual.load();
          } catch (e) {
          }
        }
        if (pdfViewerCleanup) {
          try {
            pdfViewerCleanup();
          } catch (_) {
          }
          pdfViewerCleanup = null;
        }
        if (task) {
          try {
            Promise.resolve(task.destroy()).catch(function() {
            });
          } catch (e) {
          }
          task = null;
        }
        if (worker) {
          worker.terminate();
          worker = null;
        }
        pdf = null;
      }
      function armWatchdog() {
        if (watchdog) window.clearTimeout(watchdog);
        watchdog = window.setTimeout(function() {
          stopPdf();
          flutterViewerActive = false;
          resizeToolbar();
          if (!closed) status.textContent = "プレビューがタイムアウトしました。元のファイルは変更されません。";
        }, 3e4);
      }
      function cleanup() {
        if (closed) return;
        closed = true;
        progress == null ? void 0 : progress.flush();
        stopEdit == null ? void 0 : stopEdit();
        if (imageGestureCleanup) {
          imageGestureCleanup();
          imageGestureCleanup = null;
        }
        stopPdf();
        if (objectUrl) URL.revokeObjectURL(objectUrl);
        overlay.remove();
        input.removeEventListener("change", cleanup);
        window.removeEventListener("pagehide", cleanup);
        if (viewport) {
          viewport.removeEventListener("resize", resizeToolbar);
          viewport.removeEventListener("scroll", resizeToolbar);
        }
        if (rootViewport && rootViewport !== viewport) {
          rootViewport.removeEventListener("resize", resizeToolbar);
          rootViewport.removeEventListener("scroll", resizeToolbar);
        }
        if (sourceWindow !== window) sourceWindow.removeEventListener("pagehide", cleanup);
        window.clearInterval(detachWatcher);
        if (owner.__MBG_ACTIVE_UPLOAD_PREVIEW === preview) {
          delete owner.__MBG_ACTIVE_UPLOAD_PREVIEW;
          mbgPreviewReport("none");
        }
        if (onClosed) onClosed();
      }
      close.addEventListener("click", cleanup);
      input.addEventListener("change", cleanup);
      window.addEventListener("pagehide", cleanup);
      if (sourceWindow !== window) sourceWindow.addEventListener("pagehide", cleanup);
      previous.hidden = next.hidden = true;
      function fail(error) {
        stopPdf();
        flutterViewerActive = false;
        resizeToolbar();
        if (!closed) status.textContent = "プレビューできません: " + (error.message || error);
      }
      function enableVisualZoom(element, isText) {
        visual = element;
        textZoom = isText;
        resizeToolbar();
        imageZoomLabel.hidden = false;
        imageZoomLabel.textContent = "100%";
        var gestures = mbgPreviewGestures(body, {
          min: 0.25,
          max: 5,
          getScale: function() {
            return zoom / 100;
          },
          generation: function() {
            return gestureGeneration;
          },
          setScale: function(scale) {
            setZoom(scale * 100);
          }
        });
        imageGestureCleanup = gestures;
        preview.zoomBy = gestures.zoomBy;
      }
      function openFlutterViewer(send, onFailure, onTimeout) {
        flutterViewerActive = true;
        resizeToolbar();
        var popup = !!window.__MBG_PDF_PREVIEW_POPUP;
        var frame = popup ? null : doc.createElement("iframe");
        var viewer = null, popupTimer = null;
        var sent = false;
        if (frame) {
          frame.setAttribute("title", "PDFプレビュー");
          frame.setAttribute("sandbox", "allow-scripts");
          frame.style.cssText = "width:100%;height:100%;border:0;display:block";
        }
        body.style.cssText = "position:relative;overflow:hidden;flex:1;min-height:0;padding:0";
        status.style.cssText = "position:absolute;z-index:1;top:0;left:0;right:0;text-align:center;pointer-events:none";
        zoomOut.hidden = zoomIn.hidden = true;
        function onViewerMessage(event) {
          var _a;
          if (closed || pdfStopped || event.source !== viewer) return;
          if (event.data === "mbg-preview-ready" && !sent) {
            sent = true;
            if (watchdog) window.clearTimeout(watchdog);
            watchdog = window.setTimeout(onTimeout || onFailure, 3e4);
            viewer.postMessage({ type: "mbg-preview-title", name: mbgDisplayFileName(file.name) }, "*");
            send(viewer);
          } else if (event.data === "mbg-preview-password-requested" && sent) {
            if (watchdog) {
              window.clearTimeout(watchdog);
              watchdog = null;
            }
            status.textContent = "";
          } else if (event.data === "mbg-preview-password-finished" && sent) {
            armWatchdog();
          } else if (event.data === "mbg-preview-loaded" && sent) {
            if (watchdog) {
              window.clearTimeout(watchdog);
              watchdog = null;
            }
            status.textContent = "";
          } else if (sent && ((_a = event.data) == null ? void 0 : _a.type) === "mbg-preview-page") {
            progress == null ? void 0 : progress.pageChanged(event.data.page);
          } else if (event.data === "mbg-preview-close") {
            cleanup();
          } else if (event.data === "mbg-preview-failed") {
            onFailure();
          }
        }
        sourceWindow.addEventListener("message", onViewerMessage);
        pdfViewerCleanup = function() {
          preview.zoomBy = void 0;
          sourceWindow.removeEventListener("message", onViewerMessage);
          if (popupTimer) window.clearInterval(popupTimer);
          if (frame) frame.remove();
          else if (viewer) {
            try {
              viewer.close();
            } catch (_) {
            }
          }
          previewFrame = null;
        };
        if (popup) {
          viewer = sourceWindow.open(window.__MBG_PDF_PREVIEW_URL, "_blank");
          if (!viewer) {
            onFailure();
            return;
          }
          if (!preview.visible) mbgPreviewReport("hidden");
          popupTimer = window.setInterval(function() {
            try {
              if (viewer.closed) cleanup();
            } catch (_) {
              cleanup();
            }
          }, 500);
        } else {
          previewFrame = frame;
          resizeToolbar();
          frame.src = window.__MBG_PDF_PREVIEW_URL;
          body.appendChild(frame);
          viewer = frame.contentWindow;
        }
        preview.zoomBy = function(factor) {
          if (sent && viewer) viewer.postMessage({ type: "mbg-preview-zoom", factor }, "*");
        };
      }
      function showRichPreview(payload, fallback) {
        if (!window.__MBG_PDF_PREVIEW_URL && !(window.MbgUploadCompression && window.MbgUploadCompression.postMessage)) {
          fallback();
          return;
        }
        var finished = false;
        function fallbackOnce() {
          if (closed || pdfStopped || finished) return;
          finished = true;
          if (watchdog) {
            window.clearTimeout(watchdog);
            watchdog = null;
          }
          if (cancelLibrary) {
            var cancel = cancelLibrary;
            cancelLibrary = null;
            cancel();
          }
          if (pdfViewerCleanup) {
            var dispose = pdfViewerCleanup;
            pdfViewerCleanup = null;
            dispose();
          }
          flutterViewerActive = false;
          resizeToolbar();
          body.style.cssText = "overflow:auto;flex:1;text-align:center;padding:12px";
          status.style.cssText = "";
          zoomOut.hidden = zoomIn.hidden = false;
          fallback();
        }
        if (watchdog) window.clearTimeout(watchdog);
        watchdog = window.setTimeout(fallbackOnce, 3e4);
        pdfLibrary(function(cancel) {
          cancelLibrary = cancel;
        }).then(function() {
          if (closed || pdfStopped || finished) return null;
          if (!window.__MBG_PDF_PREVIEW_URL) {
            fallbackOnce();
            return null;
          }
          return payload();
        }).then(function(message) {
          if (!message || closed || pdfStopped || finished) return;
          openFlutterViewer(function(viewer) {
            var image = message;
            if (image.data) viewer.postMessage(message, "*", [image.data]);
            else viewer.postMessage(message, "*");
          }, fallbackOnce);
        }).catch(fallbackOnce);
      }
      function showText(text, note) {
        function fallback() {
          if (watchdog) {
            window.clearTimeout(watchdog);
            watchdog = null;
          }
          var pre = doc.createElement("pre");
          pre.style.cssText = "white-space:pre-wrap;overflow-wrap:anywhere;text-align:left";
          pre.textContent = text;
          body.appendChild(pre);
          enableVisualZoom(pre, true);
          status.textContent = note || "";
        }
        if (text.length > 4e6) {
          fallback();
          return;
        }
        showRichPreview(function() {
          return Promise.resolve({ type: "mbg-preview-text", text, note });
        }, fallback);
      }
      var extension = (file.name.split(".").pop() || "").toLowerCase();
      if (file.type.indexOf("image/") === 0 || /^(jpg|jpeg|png|webp)$/.test(extension)) {
        mbgValidateImage(file).then(function() {
          if (closed) return;
          function fallback() {
            objectUrl = URL.createObjectURL(file);
            var image = doc.createElement("img");
            image.alt = file.name;
            image.style.cssText = "width:100%;height:auto";
            image.onerror = function() {
              fail(new Error("画像を開けません"));
            };
            image.src = objectUrl;
            body.appendChild(image);
            status.textContent = "";
            enableVisualZoom(image, false);
          }
          if (file.size > 64 * 1024 * 1024) {
            fallback();
            return;
          }
          showRichPreview(function() {
            return file.arrayBuffer().then(function(data) {
              var b = new Uint8Array(data);
              var mime = b[0] === 137 ? "image/png" : b[0] === 255 ? "image/jpeg" : "image/webp";
              return { type: "mbg-preview-image", data, mime };
            });
          }, fallback);
        }).catch(fail);
      } else if (file.type === "application/pdf" || extension === "pdf") {
        if (file.size > MAX_PDF_PREVIEW_BYTES) {
          fail(new Error("PDFが大きすぎます"));
          return;
        }
        if (editOnOpen) {
          editWorksheet(input, file);
          cleanup();
          return;
        }
        armWatchdog();
        if (file.size <= MAX_WORKSHEET_PDF_BYTES) {
          const edit = worksheetButton(doc, () => {
            if (stopEdit) return;
            stopEdit = openWorksheetEditor({
              document: doc,
              container: overlay,
              file,
              onExport: (result) => {
                if (remote) return saveWorksheetFile(result);
                if (!setAssignmentAttachment(input, result, file)) throw new Error("添付欄が変わりました");
              },
              onClose: () => {
                stopEdit = void 0;
                edit.focus();
              }
            });
          });
          bar.insertBefore(edit, close);
        }
        pdfLibrary(function(cancel) {
          cancelLibrary = cancel;
        }).then(function() {
          if (closed || pdfStopped) return null;
          if (window.__MBG_PDF_PREVIEW_URL) {
            flutterViewerActive = true;
            resizeToolbar();
          }
          return new Promise(function(resolve, reject) {
            reader = new FileReader();
            reader.onload = function() {
              var result = reader && reader.result;
              reader = null;
              resolve(result);
            };
            reader.onerror = function() {
              reader = null;
              reject(new Error("PDFを読み込めません"));
            };
            reader.onabort = function() {
              reader = null;
              resolve(null);
            };
            reader.readAsArrayBuffer(file);
          });
        }).then(async function(bytes) {
          if (closed || pdfStopped || !bytes) return null;
          if (remote) progress = await loadPdfReadingProgress(bytes);
          if (closed || pdfStopped) return null;
          if (window.__MBG_PDF_PREVIEW_URL) {
            openFlutterViewer(
              function(viewer) {
                const payload = progress ? { type: "mbg-preview-pdf", data: bytes, initialPage: progress.initialPage } : bytes;
                viewer.postMessage(payload, "*", [bytes]);
                bytes = null;
              },
              function() {
                fail(new Error("PDFを開けません"));
              },
              function() {
                stopPdf();
                flutterViewerActive = false;
                resizeToolbar();
                if (!closed) status.textContent = "プレビューがタイムアウトしました。元のファイルは変更されません。";
              }
            );
            return null;
          }
          worker = new Worker(window.__MBG_PDF_WORKER_URL);
          var pdfWorker = window.pdfjsLib.PDFWorker.fromPort({ port: worker });
          function CMapReaderFactory() {
          }
          CMapReaderFactory.prototype.fetch = function(request) {
            var name = request && request.name;
            var maps = window.__MBG_PDF_CMAPS;
            if (!name || !/^[A-Za-z0-9_-]{1,80}$/.test(name) || !maps || !Object.prototype.hasOwnProperty.call(maps, name)) {
              return Promise.reject(new Error("PDF文字データを読み込めません"));
            }
            var raw = atob(maps[name]), data = new Uint8Array(raw.length);
            for (var i = 0; i < raw.length; i++) data[i] = raw.charCodeAt(i);
            return Promise.resolve({ cMapData: data, compressionType: 1 });
          };
          function StandardFontDataFactory() {
          }
          StandardFontDataFactory.prototype.fetch = function(request) {
            var name = request && request.filename, fonts = window.__MBG_PDF_STANDARD_FONTS;
            if (!name || !/^[A-Za-z0-9_.-]{1,80}$/.test(name) || !fonts || !Object.prototype.hasOwnProperty.call(fonts, name)) {
              return Promise.reject(new Error("PDFフォントデータを読み込めません"));
            }
            var raw = atob(fonts[name]), data = new Uint8Array(raw.length);
            for (var i = 0; i < raw.length; i++) data[i] = raw.charCodeAt(i);
            return Promise.resolve(data);
          };
          task = window.pdfjsLib.getDocument({
            data: new Uint8Array(bytes),
            worker: pdfWorker,
            CMapReaderFactory,
            StandardFontDataFactory,
            cMapPacked: true,
            useWorkerFetch: false,
            enableXfa: false,
            isEvalSupported: false,
            useSystemFonts: true,
            stopAtErrors: true,
            maxImageSize: 16e6
          });
          return task.promise;
        }).then(function(result) {
          var _a;
          if (closed || pdfStopped || !result) return;
          if (result.numPages > 2e3) throw new Error("ページ数が安全な上限を超えています");
          pdf = result;
          pdfViewerCleanup = mbgCreatePdfViewer(
            doc,
            body,
            bar,
            status,
            pdf,
            previous,
            next,
            count,
            zoomOut,
            zoomIn,
            function() {
              if (watchdog) {
                window.clearTimeout(watchdog);
                watchdog = null;
              }
            },
            function() {
              return gestureGeneration;
            },
            function(zoomBy) {
              preview.zoomBy = zoomBy;
            },
            (_a = progress == null ? void 0 : progress.initialPage) != null ? _a : 1,
            (page) => progress == null ? void 0 : progress.pageChanged(page)
          );
        }).catch(fail);
      } else if (/^(mp3|m4a|wav|ogg|opus|mp4|m4v|webm)$/i.test(extension) || /^(audio\/(mpeg|mp4|wav|ogg|opus)|video\/(mp4|webm))$/i.test(file.type)) {
        if (file.size > 64 * 1024 * 1024) {
          fail(new Error("メディアファイルが大きすぎます"));
          return;
        }
        var isVideo = /^(mp4|m4v|webm)$/i.test(extension) || /^video\//i.test(file.type);
        var media = doc.createElement(isVideo ? "video" : "audio");
        media.controls = true;
        media.preload = "metadata";
        media.style.cssText = "max-width:100%;max-height:80vh";
        media.onerror = function() {
          fail(new Error("このメディアを開けません"));
        };
        media.onloadedmetadata = function() {
          if (isVideo && (!media.videoWidth || !media.videoHeight || media.videoWidth > 1e4 || media.videoHeight > 1e4 || media.videoWidth * media.videoHeight > 16e6)) {
            fail(new Error("動画のサイズが安全な範囲を超えています"));
          }
        };
        objectUrl = URL.createObjectURL(file);
        media.src = objectUrl;
        body.appendChild(media);
        visual = media;
        status.textContent = "";
        zoomOut.hidden = zoomIn.hidden = true;
      } else if (/^(docx|docm|xlsx|xlsm|pptx|pptm)$/i.test(extension)) {
        if (file.size > 32 * 1024 * 1024) {
          fail(new Error("文書が大きすぎます"));
          return;
        }
        armWatchdog();
        officeLibrary(function(cancel) {
          cancelLibrary = cancel;
        }).then(function() {
          if (closed || pdfStopped) return null;
          return new Promise(function(resolve, reject) {
            reader = new FileReader();
            reader.onload = function() {
              var result = reader && reader.result;
              reader = null;
              resolve(result);
            };
            reader.onerror = function() {
              reader = null;
              reject(new Error("文書を読み込めません"));
            };
            reader.onabort = function() {
              reader = null;
              resolve(null);
            };
            reader.readAsArrayBuffer(file);
          });
        }).then(function(bytes) {
          if (closed || pdfStopped || !bytes) return null;
          return mbgOfficeText(bytes, extension, function() {
            return closed || pdfStopped;
          });
        }).then(function(text) {
          if (closed || pdfStopped || text === null) return;
          showText(text, "テキストのみ表示しています。書式・画像・数式の表示は元の文書と異なります。");
        }).catch(fail);
      } else if (/^(txt|csv|tsv|md|log|json|xml|yaml|yml)$/i.test(extension) || /^text\/(plain|csv|tab-separated-values)$/i.test(file.type) || /^application\/(json|xml)$/i.test(file.type)) {
        if (file.size > 4 * 1024 * 1024) {
          fail(new Error("テキストが大きすぎます"));
          return;
        }
        reader = new FileReader();
        reader.onload = function() {
          var bytes = reader && reader.result;
          reader = null;
          if (closed || pdfStopped) return;
          var text;
          try {
            var data = new Uint8Array(bytes), encoding = "utf-8";
            if (data.length >= 2 && data[0] === 255 && data[1] === 254) encoding = "utf-16le";
            else if (data.length >= 2 && data[0] === 254 && data[1] === 255) encoding = "utf-16be";
            try {
              text = new TextDecoder(encoding, { fatal: true }).decode(data);
            } catch (error) {
              if (encoding !== "utf-8") throw error;
              text = new TextDecoder("shift_jis", { fatal: true }).decode(data);
            }
          } catch (_) {
            fail(new Error("テキストの文字コードを読み取れません"));
            return;
          }
          showText(text);
        };
        reader.onerror = function() {
          reader = null;
          fail(new Error("テキストを読み込めません"));
        };
        reader.onabort = function() {
          reader = null;
        };
        reader.readAsArrayBuffer(file);
      } else {
        status.textContent = "この形式のプレビューには対応していません。";
      }
      function setZoom(value) {
        if (pdf) return;
        zoom = Math.max(25, Math.min(500, value));
        if (visual) {
          if (textZoom) visual.style.fontSize = zoom + "%";
          else visual.style.width = zoom + "%";
          imageZoomLabel.textContent = Math.round(zoom) + "%";
        }
      }
      zoomOut.addEventListener("click", function() {
        setZoom(zoom / 1.2);
      });
      zoomIn.addEventListener("click", function() {
        setZoom(zoom * 1.2);
      });
      close.focus();
    }
    let disposeStandaloneEditor;
    function worksheetButton(doc, open) {
      const button = doc.createElement("button");
      button.type = "button";
      button.textContent = "PDFに書き込む";
      button.setAttribute("data-mbg-worksheet", "");
      button.style.cssText = "flex:none;margin:4px;padding:6px 8px";
      button.addEventListener("click", open);
      return button;
    }
    function isEditablePdf(file) {
      return file.size <= MAX_WORKSHEET_PDF_BYTES && (file.type === "application/pdf" || /\.pdf$/i.test(file.name));
    }
    window.addEventListener("pagehide", () => disposeStandaloneEditor == null ? void 0 : disposeStandaloneEditor());
    function editWorksheet(input, file) {
      if (!isEditablePdf(file)) return;
      disposeStandaloneEditor == null ? void 0 : disposeStandaloneEditor();
      disposeStandaloneEditor = openWorksheetEditor({
        document: input.ownerDocument,
        file,
        onExport: (result) => {
          if (input.type === "hidden") return saveWorksheetFile(result);
          if (!setAssignmentAttachment(input, result, file)) throw new Error("添付欄が変わりました");
        },
        onClose: () => {
          disposeStandaloneEditor = void 0;
        }
      });
    }
    function attach() {
      documents().forEach(function(doc) {
        var _a;
        var inputs = doc.querySelectorAll('input[type="file"]');
        for (var i = 0; i < inputs.length; i++) {
          var input = inputs[i];
          if (input.__mbgPreviewButton && input.__mbgPreviewButton.isConnected) continue;
          if (!input.parentNode) continue;
          var button = doc.createElement("button");
          button.type = "button";
          button.textContent = "選択したファイルをプレビュー";
          button.setAttribute("data-mbg-upload-preview", "true");
          button.style.cssText = "margin:4px 8px;padding:6px 10px";
          input.parentNode.insertBefore(button, input.nextSibling);
          input.__mbgPreviewButton = button;
          const edit = worksheetButton(doc, () => {
            const files = Array.from(input.files || []);
            const pdfs = files.filter(isEditablePdf);
            if (pdfs.length === 1 && !input.__mbgUploadCompressionPending) editWorksheet(input, pdfs[0]);
          });
          (_a = button.parentNode) == null ? void 0 : _a.insertBefore(edit, button.nextSibling);
          const showEdit = () => {
            edit.hidden = Array.from(input.files || []).filter(isEditablePdf).length !== 1;
          };
          showEdit();
          (function(target, control) {
            var list = null;
            target.addEventListener("change", function() {
              if (list) {
                list.remove();
                list = null;
              }
              showEdit();
            });
            control.addEventListener("click", function() {
              if (list) {
                list.remove();
                list = null;
              }
              if (target.__mbgUploadCompressionPending) {
                control.textContent = "圧縮が終わるまでお待ちください";
                return;
              }
              var files = target.files || [];
              if (!files.length) {
                control.textContent = "先にファイルを選択してください";
                return;
              }
              control.textContent = "選択したファイルをプレビュー";
              if (files.length === 1) {
                show(target, files[0]);
                return;
              }
              var doc2 = target.ownerDocument;
              list = doc2.createElement("div");
              Array.prototype.forEach.call(files, function(file) {
                var choice = doc2.createElement("button");
                choice.type = "button";
                choice.textContent = file.name;
                choice.setAttribute("data-mbg-upload-preview", "true");
                choice.addEventListener("click", function() {
                  list.remove();
                  show(target, file);
                });
                list.appendChild(choice);
              });
              control.after(list);
            });
          })(input, button);
        }
        mbgAttachSubmittedPreviews(doc);
      });
    }
    function mbgSubmittedFileRequest(anchor) {
      try {
        if (!anchor || !anchor.ownerDocument || !/^javascript:\s*void\s*\(\s*0\s*\)\s*;?$/i.test(anchor.getAttribute("href") || "")) return null;
        var handler = anchor.getAttribute("onclick") || "";
        var match = /^\s*(?:return\s+)?callFileDownLoad\s*\(\s*(['"])answerDownLoad\1\s*,\s*(['"]?)(\d{1,9})\2\s*,\s*(['"]?)(\d{1,9})\4\s*,\s*(['"])([^'"\\\r\n]{0,256})\6\s*\)\s*;?\s*$/i.exec(handler);
        if (!match) return null;
        var page = new URL(anchor.ownerDocument.location.href);
        if (page.origin !== "https://gakujo.iess.niigata-u.ac.jp" || page.username || page.password || page.pathname.toLowerCase() !== "/campusweb/campussquare.do") return null;
        var flow = page.searchParams.getAll("_flowExecutionKey");
        if (flow.length !== 1 || !flow[0] || flow[0].length > 1024) return null;
        var url = new URL("/campusweb/campussquare.do", page.origin);
        url.searchParams.set("_flowExecutionKey", flow[0]);
        url.searchParams.set("_eventId", "answerDownLoad");
        url.searchParams.set("questionSort", match[3]);
        url.searchParams.set("tempNo", match[5]);
        url.searchParams.set("ansTempId", match[7]);
        var name = (anchor.textContent || "").replace(/\s+/g, " ").trim();
        return { url: url.href, method: "GET", fileName: name.slice(0, 240), formFields: {} };
      } catch (_) {
        return null;
      }
    }
    var mbgRejectedPreviewAnchors = /* @__PURE__ */ new WeakMap();
    function mbgAttachSubmittedPreviews(doc) {
      var _a;
      var anchors = doc.querySelectorAll('a[href], button, input[type="submit"], input[type="button"]');
      for (var i = 0; i < anchors.length; i++) {
        var anchor = anchors[i];
        if (anchor.__mbgSubmittedPreviewButton && anchor.__mbgSubmittedPreviewButton.isConnected) continue;
        if (!anchor.parentNode) continue;
        var signature = null;
        if (String(anchor.tagName || "").toLowerCase() === "a") {
          signature = (anchor.getAttribute("href") || "") + "\n" + (anchor.getAttribute("onclick") || "") + "\n" + anchor.ownerDocument.location.href;
          if (mbgRejectedPreviewAnchors.get(anchor) === signature) continue;
        }
        const remote = mbgRemoteFileRequest(anchor);
        if (!remote) {
          if (signature !== null) mbgRejectedPreviewAnchors.set(anchor, signature);
          continue;
        }
        if (signature !== null) mbgRejectedPreviewAnchors.delete(anchor);
        var button = doc.createElement("button");
        button.type = "button";
        button.textContent = "プレビューを見る";
        button.setAttribute("data-mbg-submitted-preview", "true");
        button.style.cssText = "margin:4px 8px;padding:6px 10px";
        anchor.parentNode.insertBefore(button, anchor.nextSibling);
        anchor.__mbgSubmittedPreviewButton = button;
        if (/\.pdf(?:$|[?#])/i.test(remote.fileName) || /\.pdf(?:$|[?#])/i.test(remote.url)) {
          const edit = worksheetButton(doc, () => {
            var _a2;
            const request = mbgRemoteFileRequest(anchor);
            if (request) (_a2 = window.__MBG_OPEN_REMOTE_PREVIEW) == null ? void 0 : _a2.call(window, request, true);
          });
          (_a = button.parentNode) == null ? void 0 : _a.insertBefore(edit, button.nextSibling);
        }
        (function(target, control) {
          control.addEventListener("click", function() {
            var request = mbgRemoteFileRequest(target);
            if (!request || !window.__MBG_OPEN_REMOTE_PREVIEW(request)) {
              control.textContent = "プレビューできません";
              return;
            }
            control.textContent = "プレビューを見る";
          });
        })(anchor, button);
      }
    }
    function mbgRemoteFileRequest(anchor) {
      try {
        if ((anchor.getAttribute("id") || "").startsWith("mbg-") || anchor.getAttributeNames().some(function(name) {
          return name.startsWith("data-mbg-");
        })) return null;
        var page = new URL(anchor.ownerDocument.location.href);
        if (page.origin !== "https://gakujo.iess.niigata-u.ac.jp" || page.username || page.password) return null;
        if (String(anchor.tagName || "").toLowerCase() !== "a") {
          if (anchor.getAttribute("onclick")) return null;
          var form = anchor.form;
          if (!form) return null;
          var method = (anchor.getAttribute("formmethod") || form.getAttribute("method") || "GET").toUpperCase();
          var enctype = (anchor.getAttribute("formenctype") || form.getAttribute("enctype") || "application/x-www-form-urlencoded").toLowerCase();
          var target = anchor.getAttribute("formtarget") || form.getAttribute("target") || "_self";
          if (!/^(GET|POST)$/.test(method) || method === "POST" && enctype !== "application/x-www-form-urlencoded" || !/^_self$/i.test(target)) return null;
          var action = anchor.getAttribute("formaction") || form.getAttribute("action") || page.href;
          var fields = {}, unsafe = false, data = new FormData(form);
          if (anchor.name) data.set(anchor.name, anchor.value || "");
          data.forEach(function(value, key) {
            if (typeof value !== "string" || /^(?:__proto__|constructor|prototype)$/.test(key) || Object.prototype.hasOwnProperty.call(fields, key)) unsafe = true;
            else fields[key] = value;
          });
          if (unsafe) return null;
          var formRequest = {
            url: new URL(action, page.href).href,
            method,
            fileName: String(anchor.textContent || anchor.value || "").trim().slice(0, 240),
            formFields: fields
          };
          return mbgValidateRemotePreviewRequest(formRequest) ? formRequest : null;
        }
        var submitted = mbgSubmittedFileRequest(anchor);
        if (submitted) return submitted;
        var href = (anchor.getAttribute("href") || "").trim();
        if (!href || /^javascript:/i.test(href) || href.charAt(0) === "#") return null;
        var request = {
          url: new URL(href, page.href).href,
          method: "GET",
          fileName: String(anchor.textContent || "").replace(/\s+/g, " ").trim().slice(0, 240),
          formFields: {}
        };
        return mbgValidateRemotePreviewRequest(request) ? request : null;
      } catch (_) {
        return null;
      }
    }
    function mbgValidateRemotePreviewRequest(request) {
      if (window.location.origin !== "https://gakujo.iess.niigata-u.ac.jp") return false;
      var url;
      try {
        url = new URL(request.url, window.location.href);
      } catch (_) {
        return false;
      }
      if (url.origin !== window.location.origin || url.username || url.password) return false;
      var method = String(request.method || "").toUpperCase();
      if (method !== "GET" && method !== "POST") return false;
      var fields = request.formFields || {}, strong = false, workflow = false;
      var fileRefer = false, fileId = false;
      function inspect(value, key) {
        var named = /^_eventId_(.*)$/i.exec(key);
        if (/^_eventId$/i.test(key) || named) {
          var action = named ? named[1] : String(value);
          if (/download/i.test(action)) strong = true;
          if (/(confirm|entry|submit|save|regist|update|delete|back|clear|cancel|next|prev|complete|finish|reset)/i.test(action) || action.trim() && !/download/i.test(action)) workflow = true;
        }
        if (/^(file.?download|download.?file|downloadType)$/i.test(key)) strong = true;
        if (/^_flowId$/i.test(key) && /filerefer/i.test(String(value))) fileRefer = true;
        if (/^fileId$/i.test(key) && String(value).trim()) fileId = true;
      }
      url.searchParams.forEach(inspect);
      Object.keys(fields).forEach(function(key) {
        inspect(fields[key], key);
      });
      if (/\.(pdf|png|jpe?g|webp|txt|csv|tsv|md|log|json|xml|ya?ml|mp3|m4a|wav|ogg|opus|mp4|m4v|webm|docx|docm|xlsx|xlsm|pptx|pptm)(?:$|[?#])/i.test(url.pathname)) strong = true;
      if (fileRefer && fileId) strong = true;
      if (!strong || workflow) return false;
      var keys = Object.keys(fields);
      if (keys.length > 100 || keys.some(function(key) {
        return key.length > 1024 || String(fields[key]).length > 16384;
      })) return false;
      return true;
    }
    window.__MBG_OPEN_REMOTE_PREVIEW = function(request, editOnOpen) {
      if (!mbgValidateRemotePreviewRequest(request)) return false;
      var url = new URL(request.url, window.location.href);
      var method = String(request.method || "").toUpperCase();
      var fields = request.formFields || {}, keys = Object.keys(fields);
      var previous = window.__MBG_ACTIVE_UPLOAD_PREVIEW;
      if (previous && typeof previous.close === "function") previous.close();
      var doc = document, overlay = doc.createElement("div");
      overlay.setAttribute("role", "dialog");
      overlay.setAttribute("aria-modal", "true");
      overlay.setAttribute("aria-label", "ファイルのプレビュー");
      overlay.style.cssText = "position:fixed;inset:0;z-index:2147483647;background:#fff;color:#111;padding:24px;font:16px sans-serif";
      var status = doc.createElement("p");
      status.textContent = "ファイルを読み込み中…";
      var close = doc.createElement("button");
      close.type = "button";
      close.textContent = "閉じる";
      overlay.append(status, close);
      (doc.documentElement || doc.body).appendChild(overlay);
      var controller = new AbortController(), closed = false;
      var timeout = window.setTimeout(function() {
        controller.abort();
        if (!closed) status.textContent = "読み込みがタイムアウトしました。";
      }, 3e4);
      var operation = { close: cleanup, visible: true, setVisible };
      window.__MBG_ACTIVE_UPLOAD_PREVIEW = operation;
      function setVisible(visible) {
        if (closed) return;
        operation.visible = visible;
        overlay.style.display = visible ? "block" : "none";
        mbgPreviewReport(visible ? "visible" : "hidden");
      }
      setVisible(true);
      function cleanup(preserveState) {
        if (closed) return;
        closed = true;
        controller.abort();
        window.clearTimeout(timeout);
        window.removeEventListener("pagehide", cleanup);
        overlay.remove();
        if (window.__MBG_ACTIVE_UPLOAD_PREVIEW === operation) {
          delete window.__MBG_ACTIVE_UPLOAD_PREVIEW;
          if (preserveState !== true) mbgPreviewReport("none");
        }
      }
      close.addEventListener("click", cleanup);
      window.addEventListener("pagehide", cleanup);
      close.focus();
      var options = {
        method,
        credentials: "same-origin",
        redirect: "error",
        cache: "no-store",
        signal: controller.signal
      };
      if (method === "GET") {
        keys.forEach(function(key) {
          url.searchParams.set(key, String(fields[key]));
        });
      } else {
        var body = new URLSearchParams();
        keys.forEach(function(key) {
          body.append(key, String(fields[key]));
        });
        options.body = body.toString();
        options.headers = { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" };
      }
      fetch(url.href, options).then(function(response) {
        if (!response.ok || !response.url || new URL(response.url).origin !== window.location.origin) {
          throw new Error("ファイルを取得できません");
        }
        var type = (response.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
        if (type === "text/html" || type === "application/xhtml+xml") throw new Error("ファイルではなくページが返されました");
        var length = response.headers.get("content-length");
        if (length && (!/^\d+$/.test(length) || Number(length) > MAX_PDF_PREVIEW_BYTES)) throw new Error("ファイルが大きすぎます");
        if (!response.body || !response.body.getReader) throw new Error("この環境では安全に読み込めません");
        var disposition = response.headers.get("content-disposition") || "";
        var extended = /(?:^|;)\s*filename\*\s*=\s*UTF-8''([^;]+)/i.exec(disposition);
        var plain = /(?:^|;)\s*filename\s*=\s*(?:"([^"]*)"|([^;]*))/i.exec(disposition);
        var suggested = plain ? (plain[1] || plain[2] || "").trim() : "";
        if (extended) {
          try {
            suggested = decodeURIComponent(extended[1].trim());
          } catch (_) {
          }
        }
        var reader = response.body.getReader(), parts = [], size = 0;
        function next() {
          return reader.read().then(function(item) {
            if (closed) return null;
            if (item.done) return { parts, type, name: suggested };
            size += item.value.byteLength;
            if (size > MAX_PDF_PREVIEW_BYTES) {
              controller.abort();
              throw new Error("ファイルが大きすぎます");
            }
            parts.push(item.value);
            return next();
          });
        }
        return next();
      }).then(function(result) {
        if (closed || !result) return;
        var name = String(result.name || request.fileName || "").trim() || "ファイル";
        var header = [], remaining = 1024;
        result.parts.some(function(part) {
          var take = Math.min(remaining, part.length);
          for (var i = 0; i < take; i++) header.push(part[i]);
          remaining -= take;
          return remaining === 0;
        });
        var first = new Uint8Array(header);
        var prefix = String.fromCharCode.apply(null, first);
        if (/^(?:\xEF\xBB\xBF)?\s*(?:<!doctype\s+html|<html)(?:\s|>)/i.test(prefix)) throw new Error("ファイルではなくページが返されました");
        var type = result.type;
        if (prefix.indexOf("%PDF-") === 0) type = "application/pdf";
        else if (first.length >= 3 && first[0] === 255 && first[1] === 216 && first[2] === 255) type = "image/jpeg";
        else if (first.length >= 8 && first[0] === 137 && prefix.slice(1, 4) === "PNG") type = "image/png";
        else if (prefix.slice(0, 4) === "RIFF" && prefix.slice(8, 12) === "WEBP") type = "image/webp";
        var file = new File(result.parts, name, { type });
        var extension = (name.split(".").pop() || "").toLowerCase();
        var isImage = type.indexOf("image/") === 0 || /^(jpg|jpeg|png|webp)$/.test(extension);
        if (file.size > 64 * 1024 * 1024 && (isImage || type !== "application/pdf" && extension !== "pdf")) {
          throw new Error("ファイルが大きすぎます");
        }
        var anchor = doc.createElement("input");
        anchor.type = "hidden";
        doc.body.appendChild(anchor);
        var visible = operation.visible;
        var token = operation.__mbgToken;
        if (editOnOpen && !isEditablePdf(file)) {
          anchor.remove();
          throw new Error("書き込めるPDFを読み込めませんでした");
        }
        cleanup(true);
        show(anchor, file, function() {
          anchor.remove();
        }, visible, editOnOpen);
        var shown = window.__MBG_ACTIVE_UPLOAD_PREVIEW;
        if (token && shown && !shown.__mbgToken) shown.__mbgToken = token;
      }).catch(function(error) {
        window.clearTimeout(timeout);
        if (!closed && error.name !== "AbortError") status.textContent = "プレビューできません: " + (error.message || error);
      });
      return true;
    };
    var officeWaiters = [];
    window.__MBG_UPLOAD_PREVIEW_OFFICE_LIBRARY_LOADED = function() {
      var pending = officeWaiters.splice(0);
      pending.forEach(function(done) {
        done();
      });
    };
    function officeLibrary(setCancel) {
      if (window.JSZip && window["__MBG_UPLOAD_LIBRARY_READY_preview-office"]) return Promise.resolve();
      return new Promise(function(resolve, reject) {
        var channel = window.MbgUploadCompression;
        if (!channel || !channel.postMessage) {
          reject(new Error("文書プレビューを読み込めません"));
          return;
        }
        var timer = window.setTimeout(function() {
          var index = officeWaiters.indexOf(done);
          if (index >= 0) officeWaiters.splice(index, 1);
          setCancel(null);
          reject(new Error("文書プレビューの読み込みがタイムアウトしました"));
        }, 3e4);
        function done() {
          window.clearTimeout(timer);
          setCancel(null);
          if (window.JSZip && window["__MBG_UPLOAD_LIBRARY_READY_preview-office"]) resolve();
          else reject(new Error("文書プレビューを読み込めません"));
        }
        officeWaiters.push(done);
        setCancel(function() {
          window.clearTimeout(timer);
          var index = officeWaiters.indexOf(done);
          if (index >= 0) officeWaiters.splice(index, 1);
          resolve();
        });
        if (officeWaiters.length === 1) channel.postMessage("preview-office");
      });
    }
    function mbgCheckOfficeDirectory(buffer) {
      var bytes = new Uint8Array(buffer), view = new DataView(buffer), end = -1;
      for (var i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
        if (view.getUint32(i, true) === 101010256) {
          end = i;
          break;
        }
      }
      if (end < 0 || end + 22 + view.getUint16(end + 20, true) !== bytes.length) throw new Error("文書の構造を確認できません");
      var count = view.getUint16(end + 10, true), size = view.getUint32(end + 12, true), offset = view.getUint32(end + 16, true);
      if (view.getUint16(end + 4, true) !== 0 || view.getUint16(end + 6, true) !== 0 || view.getUint16(end + 8, true) !== count || count === 65535 || size === 4294967295 || offset === 4294967295 || count > 5e3 || offset + size > end) throw new Error("文書の構造が大きすぎるか、対応していない形式です");
      var cursor = offset, limit = offset + size;
      for (var n = 0; n < count; n++) {
        if (cursor + 46 > limit || view.getUint32(cursor, true) !== 33639248 || view.getUint32(cursor + 20, true) === 4294967295 || view.getUint32(cursor + 24, true) === 4294967295 || view.getUint32(cursor + 42, true) === 4294967295) throw new Error("文書の構造が正しくないか、対応していない形式です");
        cursor += 46 + view.getUint16(cursor + 28, true) + view.getUint16(cursor + 30, true) + view.getUint16(cursor + 32, true);
        if (cursor > limit) throw new Error("文書の構造が正しくありません");
      }
      if (cursor !== limit) throw new Error("文書の構造が正しくありません");
    }
    function mbgOfficeEntry(entry, stopped) {
      return new Promise(function(resolve, reject) {
        var stream = entry.internalStream("uint8array"), parts = [], length = 0, failed = false;
        stream.on("data", function(chunk) {
          if (failed) return;
          length += chunk.length;
          if (stopped() || length > 4 * 1024 * 1024) {
            failed = true;
            stream.pause();
            reject(new Error("文書内のデータが大きすぎるか中止されました"));
            return;
          }
          parts.push(chunk);
        });
        stream.on("error", function(error) {
          if (!failed) reject(error);
        });
        stream.on("end", function() {
          if (failed) return;
          if (stopped()) {
            reject(new Error("プレビューを中止しました"));
            return;
          }
          var bytes = new Uint8Array(length), offset = 0;
          parts.forEach(function(part) {
            bytes.set(part, offset);
            offset += part.length;
          });
          resolve(bytes);
        });
        stream.resume();
      });
    }
    function mbgOfficeText(buffer, extension, stopped) {
      mbgCheckOfficeDirectory(buffer);
      return window.JSZip.loadAsync(buffer).then(function(zip) {
        var entries = Object.keys(zip.files);
        if (entries.length > 5e3) throw new Error("文書内のファイルが多すぎます");
        var selected;
        if (/^doc[xm]$/i.test(extension)) selected = ["word/document.xml"];
        else if (/^ppt[xm]$/i.test(extension)) selected = entries.filter(function(n) {
          return /^ppt\/slides\/slide\d+\.xml$/i.test(n);
        });
        else selected = entries.filter(function(n) {
          return /^xl\/worksheets\/sheet\d+\.xml$/i.test(n);
        });
        selected.sort(function(a, b) {
          return a.localeCompare(b, void 0, { numeric: true });
        });
        if (!selected.length || selected.length > 100 || selected.some(function(n) {
          return !zip.files[n];
        })) throw new Error("文書の本文を確認できません");
        var total = 0, output = [], shared = [];
        function xml(name) {
          var entry = zip.files[name], size = entry && entry._data && entry._data.uncompressedSize;
          if (!entry || !Number.isSafeInteger(size) || size < 0 || size > 4 * 1024 * 1024) throw new Error("文書内のデータが大きすぎます");
          return mbgOfficeEntry(entry, stopped).then(function(bytes) {
            total += bytes.length;
            if (total > 12 * 1024 * 1024) throw new Error("文書の展開サイズが大きすぎます");
            var text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
            if (/<!DOCTYPE|<!ENTITY/i.test(text)) throw new Error("未対応の文書形式です");
            var result = new DOMParser().parseFromString(text, "application/xml");
            if (result.getElementsByTagName("parsererror").length) throw new Error("文書の内容を読み込めません");
            return result;
          });
        }
        function elements(node, name) {
          return Array.prototype.slice.call(node.getElementsByTagNameNS("*", name));
        }
        function paragraphText(node) {
          return elements(node, "t").map(function(x) {
            return x.textContent;
          }).join("");
        }
        var preparation = Promise.resolve();
        if (/^xls[xm]$/i.test(extension) && zip.files["xl/sharedStrings.xml"]) {
          preparation = xml("xl/sharedStrings.xml").then(function(document2) {
            var strings = elements(document2, "si");
            if (strings.length > 5e4) throw new Error("文書の項目が多すぎます");
            shared = strings.map(paragraphText);
          });
        }
        return preparation.then(function() {
          return selected.reduce(function(chain, name, index) {
            return chain.then(function() {
              if (stopped()) throw new Error("プレビューを中止しました");
              return xml(name).then(function(document2) {
                var lines = [];
                if (/^xls[xm]$/i.test(extension)) {
                  var rows = elements(document2, "row");
                  if (rows.length > 1e4) throw new Error("行が多すぎます");
                  rows.forEach(function(row) {
                    var cells = elements(row, "c");
                    if (cells.length > 1e3) throw new Error("列が多すぎます");
                    lines.push(cells.map(function(cell) {
                      var values = elements(cell, "v"), value = values.length ? values[0].textContent : paragraphText(cell);
                      return cell.getAttribute("t") === "s" ? shared[Number(value)] || "" : value;
                    }).join("	"));
                  });
                } else {
                  var paragraphs = elements(document2, "p");
                  if (paragraphs.length > 5e4) throw new Error("文書の項目が多すぎます");
                  lines = paragraphs.map(paragraphText);
                }
                if (selected.length > 1) output.push((/^xls[xm]$/i.test(extension) ? "シート " : "スライド ") + (index + 1));
                output.push(lines.join("\n"));
                if (output.join("\n").length > 1e6) throw new Error("表示できる文字数を超えました");
              });
            });
          }, Promise.resolve()).then(function() {
            return output.join("\n");
          });
        });
      });
    }
    function mbgPreviewGestures(node, callbacks) {
      var start = null, pinch = null, pending = null, frame = null;
      var blocked = false, generation = 0, oldTouchAction = node.style.touchAction;
      function currentGeneration() {
        return callbacks.generation ? callbacks.generation() : 0;
      }
      function hasSelection() {
        var _a, _b;
        var selection = (_b = (_a = node.ownerDocument).getSelection) == null ? void 0 : _b.call(_a);
        return selection && !selection.isCollapsed;
      }
      function canSwipe() {
        return !!(callbacks.previous || callbacks.next) && callbacks.getScale() <= 1.001 && node.scrollWidth <= node.clientWidth + 1 && !hasSelection();
      }
      function updateTouchAction() {
        node.style.touchAction = canSwipe() ? "pan-y" : "pan-x pan-y";
      }
      updateTouchAction();
      function distance(a, b) {
        return Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
      }
      function centre(a, b) {
        return { x: (a.clientX + b.clientX) / 2, y: (a.clientY + b.clientY) / 2 };
      }
      function applyScale(value, point) {
        var old = callbacks.getScale();
        if (!Number.isFinite(old) || old <= 0 || !Number.isFinite(value)) return;
        var next = Math.max(callbacks.min, Math.min(callbacks.max, value));
        var rect = node.getBoundingClientRect(), x = point.x - rect.left, y = point.y - rect.top;
        var left = node.scrollLeft, top = node.scrollTop;
        callbacks.setScale(next);
        updateTouchAction();
        node.scrollLeft = (left + x) * next / old - x;
        node.scrollTop = (top + y) * next / old - y;
      }
      function flush() {
        frame = null;
        if (generation !== currentGeneration()) {
          onCancel();
          return;
        }
        if (pending) {
          var value = pending;
          pending = null;
          applyScale(value.scale, value.point);
        }
      }
      function onStart(event) {
        if (event.target && event.target.closest && event.target.closest("a,button,input,textarea,select,audio,video")) {
          onCancel();
          blocked = true;
          return;
        }
        if (event.touches.length > 2) {
          onCancel();
          blocked = true;
          return;
        }
        if (event.touches.length === 2) {
          onCancel();
          blocked = true;
          generation = currentGeneration();
          var length = distance(event.touches[0], event.touches[1]);
          pinch = length > 0 ? { distance: length, scale: callbacks.getScale() } : null;
          start = null;
        } else if (event.touches.length === 1 && !blocked) {
          generation = currentGeneration();
          if (!canSwipe()) {
            start = null;
            return;
          }
          var touch = event.touches[0];
          start = { id: touch.identifier, x: touch.clientX, y: touch.clientY, time: Date.now(), left: node.scrollLeft, top: node.scrollTop };
          pinch = null;
        }
      }
      function onMove(event) {
        if (generation !== currentGeneration()) {
          onCancel();
          blocked = true;
          return;
        }
        if (start) {
          var touch = event.touches[0];
          if (event.touches.length !== 1 || !touch || touch.identifier !== start.id || node.scrollLeft !== start.left || node.scrollTop !== start.top || !canSwipe()) {
            start = null;
          } else {
            var dx = Math.abs(touch.clientX - start.x), dy = Math.abs(touch.clientY - start.y);
            if (dy > 12 && dy * 1.5 >= dx) start = null;
          }
        }
        if (!pinch || event.touches.length !== 2) return;
        if (event.cancelable) event.preventDefault();
        pending = {
          scale: pinch.scale * distance(event.touches[0], event.touches[1]) / pinch.distance,
          point: centre(event.touches[0], event.touches[1])
        };
        if (frame === null) frame = window.requestAnimationFrame(flush);
      }
      function onEnd(event) {
        if (generation !== currentGeneration()) {
          onCancel();
          blocked = !!event.touches.length;
          return;
        }
        if (pinch) {
          if (frame !== null) {
            window.cancelAnimationFrame(frame);
            frame = null;
          }
          if (pending) flush();
          if (event.touches.length < 2) {
            pinch = null;
            start = null;
          }
          blocked = !!event.touches.length;
          return;
        }
        if (!event.touches.length) blocked = false;
        if (!start || event.touches.length || !event.changedTouches.length) return;
        var touch = event.changedTouches[0], dx = touch.clientX - start.x, dy = touch.clientY - start.y;
        if (touch.identifier === start.id && canSwipe() && node.scrollLeft === start.left && node.scrollTop === start.top && Date.now() - start.time < 900 && Math.abs(dx) >= 80 && Math.abs(dx) > Math.abs(dy) * 1.5) {
          if (dx < 0 && callbacks.next) callbacks.next();
          else if (dx > 0 && callbacks.previous) callbacks.previous();
        }
        start = null;
      }
      function onCancel() {
        start = pinch = pending = null;
        blocked = false;
        if (frame !== null) {
          window.cancelAnimationFrame(frame);
          frame = null;
        }
      }
      function onWheel(event) {
        if (!event.ctrlKey && !event.metaKey) return;
        onCancel();
        generation = currentGeneration();
        if (event.cancelable) event.preventDefault();
        var multiplier = Math.max(0.75, Math.min(1.33, Math.exp(-event.deltaY * 0.01)));
        applyScale(callbacks.getScale() * multiplier, { x: event.clientX, y: event.clientY });
      }
      node.addEventListener("touchstart", onStart, { passive: true });
      node.addEventListener("touchmove", onMove, { passive: false });
      node.addEventListener("touchend", onEnd, { passive: true });
      node.addEventListener("touchcancel", onCancel, { passive: true });
      node.addEventListener("wheel", onWheel, { passive: false });
      var cleanup = Object.assign(function() {
        onCancel();
        node.style.touchAction = oldTouchAction;
        node.removeEventListener("touchstart", onStart);
        node.removeEventListener("touchmove", onMove);
        node.removeEventListener("touchend", onEnd);
        node.removeEventListener("touchcancel", onCancel);
        node.removeEventListener("wheel", onWheel);
      }, { updateTouchAction, zoomBy: function(factor) {
        onCancel();
        generation = currentGeneration();
        var rect = node.getBoundingClientRect();
        applyScale(callbacks.getScale() * factor, { x: rect.left + node.clientWidth / 2, y: rect.top + node.clientHeight / 2 });
      } });
      return cleanup;
    }
    function mbgCreatePdfViewer(doc, body, bar, status, pdf, previous, next, count, zoomOut, zoomIn, onFirstPage, generation, registerZoom, initialPage, onPage) {
      var host = doc.createElement("div");
      host.style.cssText = "position:absolute;inset:0";
      var root = host.attachShadow({ mode: "closed" });
      var style = doc.createElement("style");
      style.textContent = window.__MBG_PDF_VIEWER_CSS;
      var container = doc.createElement("div");
      container.style.cssText = "position:absolute;inset:0;overflow:auto;background:#e5e5e5";
      var pages = doc.createElement("div");
      pages.className = "pdfViewer";
      container.appendChild(pages);
      root.append(style, container);
      body.appendChild(host);
      body.style.cssText = "position:relative;flex:1;min-height:0";
      bar.appendChild(status);
      status.style.cssText = "font-size:12px;margin:0;color:#555";
      status.textContent = "ページを読み込み中…";
      var search = doc.createElement("input");
      search.type = "search";
      search.placeholder = "文書内を検索";
      search.setAttribute("aria-label", "文書内を検索");
      search.maxLength = 256;
      var findPrevious = doc.createElement("button");
      findPrevious.type = "button";
      findPrevious.textContent = "前の検索結果";
      var findNext = doc.createElement("button");
      findNext.type = "button";
      findNext.textContent = "次の検索結果";
      var matches = doc.createElement("span");
      matches.setAttribute("aria-live", "polite");
      var pageInput = doc.createElement("input");
      pageInput.type = "number";
      pageInput.min = "1";
      pageInput.max = String(pdf.numPages);
      pageInput.style.cssText = "width:4.5em";
      pageInput.setAttribute("aria-label", "ページ番号");
      var go = doc.createElement("button");
      go.type = "button";
      go.textContent = "ページ移動";
      var zoomLabel = doc.createElement("span");
      zoomLabel.setAttribute("aria-label", "表示倍率");
      var fit = doc.createElement("button");
      fit.type = "button";
      fit.textContent = "幅に合わせる";
      bar.insertBefore(pageInput, zoomOut);
      bar.insertBefore(go, zoomOut);
      bar.insertBefore(search, zoomOut);
      bar.insertBefore(findPrevious, zoomOut);
      bar.insertBefore(findNext, zoomOut);
      bar.insertBefore(matches, zoomOut);
      bar.insertBefore(zoomLabel, zoomOut);
      bar.insertBefore(fit, zoomOut);
      var events = new window.pdfjsViewer.EventBus();
      var links = new window.pdfjsViewer.PDFLinkService({ eventBus: events });
      links.externalLinkEnabled = false;
      var finder = new window.pdfjsViewer.PDFFindController({ eventBus: events, linkService: links });
      var viewer = new window.pdfjsViewer.PDFViewer({
        container,
        viewer: pages,
        eventBus: events,
        linkService: links,
        findController: finder,
        // Annotation icons must never resolve against the university page or an
        // address supplied by a PDF. The fragment absorbs PDF.js's icon name.
        imageResourcesPath: 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="20" height="20"%3E%3Ccircle cx="10" cy="10" r="7" fill="%23555"/%3E%3C/svg%3E#',
        annotationMode: window.pdfjsLib.AnnotationMode.ENABLE,
        maxCanvasPixels: 2e6
      });
      links.setViewer(viewer);
      links.setDocument(pdf, null);
      finder.setDocument(pdf);
      function updatePage() {
        var current = viewer.currentPageNumber || 1;
        count.textContent = current + " / " + pdf.numPages;
        pageInput.value = String(current);
        previous.disabled = current <= 1;
        next.disabled = current >= pdf.numPages;
      }
      var ready = false;
      events.on("pagesinit", function() {
        viewer.currentScaleValue = "page-width";
        if (initialPage > 1 && initialPage <= pdf.numPages) viewer.currentPageNumber = initialPage;
        updatePage();
        ready = true;
      });
      events.on("pagechanging", function() {
        updatePage();
        if (ready) onPage(viewer.currentPageNumber);
      });
      events.on("scalechanging", function(event) {
        zoomLabel.textContent = Math.round(event.scale * 100) + "%";
      });
      events.on("pagerendered", function(event) {
        if (event.error) {
          status.textContent = /maximum allowed size/i.test(String(event.error.message || event.error)) ? "画像が大きすぎるため、このページを表示できません" : "ページを表示できません";
        } else {
          status.textContent = "大きな画像は表示されない場合があります";
        }
        onFirstPage();
      });
      function updateMatches(event) {
        var value = event.matchesCount || {};
        matches.textContent = search.value ? (value.current || 0) + " / " + (value.total || 0) : "";
      }
      var alternatives = [], alternative = 0;
      events.on("updatefindmatchescount", updateMatches);
      events.on("updatefindcontrolstate", function(event) {
        if (event.rawQuery === alternatives[alternative] && event.state === 1 && alternative + 1 < alternatives.length) {
          alternative++;
          dispatchFind(false, false);
          return;
        }
        updateMatches(event);
      });
      function searchAlternatives(query) {
        if (!/[\u0590-\u08ff\ufb1d-\ufeff]/.test(query)) return [query];
        var forms = [
          query,
          query.replace(/[يى]/g, "ی").replace(/ك/g, "ک"),
          query.replace(/ی/g, "ي").replace(/ک/g, "ك")
        ];
        var result = [];
        forms.forEach(function(form) {
          var units;
          if (typeof Intl !== "undefined" && Intl.Segmenter) {
            units = Array.from(new Intl.Segmenter(void 0, { granularity: "grapheme" }).segment(form), function(x) {
              return x.segment;
            });
          } else {
            units = Array.from(form);
          }
          [form, units.reverse().join("")].forEach(function(value) {
            if (result.indexOf(value) < 0) result.push(value);
          });
        });
        return result;
      }
      function dispatchFind(again, backwards) {
        events.dispatch("find", {
          source: search,
          type: again ? "again" : "",
          query: alternatives[alternative],
          caseSensitive: false,
          entireWord: false,
          highlightAll: true,
          findPrevious: backwards,
          matchDiacritics: false
        });
      }
      function find(again, backwards) {
        if (!again || !alternatives.length) {
          alternatives = searchAlternatives(search.value);
          alternative = 0;
        }
        dispatchFind(again, backwards);
      }
      search.addEventListener("input", function() {
        find(false, false);
      });
      search.addEventListener("keydown", function(event) {
        if (event.key === "Enter") {
          event.preventDefault();
          find(true, !!event.shiftKey);
        }
      });
      bar.parentNode.addEventListener("keydown", function(event) {
        if ((event.ctrlKey || event.metaKey) && String(event.key).toLowerCase() === "f") {
          event.preventDefault();
          search.focus();
        }
      });
      function goToPage() {
        var page = Number(pageInput.value);
        if (Number.isInteger(page) && page >= 1 && page <= pdf.numPages) viewer.currentPageNumber = page;
        else updatePage();
      }
      pageInput.addEventListener("keydown", function(event) {
        if (event.key === "Enter") {
          event.preventDefault();
          goToPage();
        }
      });
      go.addEventListener("click", goToPage);
      findPrevious.addEventListener("click", function() {
        find(true, true);
      });
      findNext.addEventListener("click", function() {
        find(true, false);
      });
      previous.addEventListener("click", function() {
        if (viewer.currentPageNumber > 1) viewer.currentPageNumber--;
      });
      next.addEventListener("click", function() {
        if (viewer.currentPageNumber < pdf.numPages) viewer.currentPageNumber++;
      });
      zoomOut.addEventListener("click", function() {
        viewer.currentScale = Math.max(0.25, viewer.currentScale / 1.25);
      });
      zoomIn.addEventListener("click", function() {
        viewer.currentScale = Math.min(4, viewer.currentScale * 1.25);
      });
      fit.addEventListener("click", function() {
        viewer.currentScaleValue = "page-width";
      });
      var removeGestures = mbgPreviewGestures(container, {
        min: 0.25,
        max: 4,
        getScale: function() {
          return viewer.currentScale;
        },
        generation,
        setScale: function(value) {
          viewer.currentScale = value;
        },
        previous: function() {
          if (viewer.currentPageNumber > 1) viewer.currentPageNumber--;
        },
        next: function() {
          if (viewer.currentPageNumber < pdf.numPages) viewer.currentPageNumber++;
        }
      });
      events.on("scalechanging", removeGestures.updateTouchAction);
      events.on("pagesinit", removeGestures.updateTouchAction);
      registerZoom(removeGestures.zoomBy);
      previous.hidden = next.hidden = false;
      updatePage();
      viewer.setDocument(pdf);
      return function() {
        removeGestures();
        try {
          viewer.setDocument(null);
          links.setDocument(null, null);
        } catch (_) {
        }
        host.remove();
      };
    }
    attach();
    window.__MBG_UPLOAD_PREVIEW_WATCH_DISPOSE = watchPage(window, attach, { fallbackMs: 5e3, legacyIntervalMs: 1e3 });
  }
  uploadPreview();
})();
})(''';
const String _gakujoUploadPreviewJsSuffix = r''');
''';
