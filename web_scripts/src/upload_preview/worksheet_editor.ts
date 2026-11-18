import {penThickness, writeWorksheetPdf} from './worksheet_pdf.js';
import type {Edit, EditedPage, Point, Viewport, WorksheetPdfLibrary} from './worksheet_pdf.js';

type RenderTask = { promise: Promise<void>; cancel(): void };
type PdfPage = {
  getViewport(options: { scale: number }): Viewport;
  render(options: { canvasContext: CanvasRenderingContext2D; viewport: Viewport }): RenderTask;
};
type PdfDocument = { numPages: number; getPage(page: number): Promise<PdfPage> };
type PdfTask = { promise: Promise<PdfDocument>; destroy(): Promise<void> };

type EditorWindow = Window & {
  PDFLib?: WorksheetPdfLibrary;
  __MBG_UPLOAD_PREVIEW_EDIT_LIBRARY_LOADED?: () => void;
  '__MBG_UPLOAD_LIBRARY_READY_preview-edit'?: boolean;
};
type WorksheetEditorOptions = {
  document: Document;
  container?: HTMLElement;
  file: File;
  onExport(file: File): void | Promise<void>;
  onClose?(): void;
};

export const MAX_WORKSHEET_PDF_BYTES = 64 * 1024 * 1024;
const maxEdits = 150;
const maxPoints = 1024;
const penColor = '#173d91';
const fontSize = 13;

function loadLibrary(signal: AbortSignal): Promise<WorksheetPdfLibrary> {
  const owner = window as EditorWindow;
  const available = () => owner['__MBG_UPLOAD_LIBRARY_READY_preview-edit'] &&
    window.pdfjsLib && window.__MBG_PDF_WORKER_URL && owner.PDFLib;
  const existing = available();
  if (existing) return Promise.resolve(existing);
  return new Promise((resolve, reject) => {
    const channel = window.MbgUploadCompression;
    if (!channel || signal.aborted) { reject(new Error()); return; }
    const timer = window.setTimeout(failed, 30000);
    signal.addEventListener('abort', failed, {once: true});
    owner.__MBG_UPLOAD_PREVIEW_EDIT_LIBRARY_LOADED = loaded;
    try { channel.postMessage('preview-edit'); } catch (_) { failed(); }

    function cleanup() {
      window.clearTimeout(timer);
      signal.removeEventListener('abort', failed);
      if (owner.__MBG_UPLOAD_PREVIEW_EDIT_LIBRARY_LOADED === loaded) {
        delete owner.__MBG_UPLOAD_PREVIEW_EDIT_LIBRARY_LOADED;
      }
    }
    function failed() { cleanup(); reject(new Error()); }
    function loaded() {
      const library = available();
      cleanup();
      if (library) resolve(library);
      else reject(new Error());
    }
  });
}

function getPdf(data: ArrayBuffer, worker: Worker): PdfTask {
  const pdfWorker = window.pdfjsLib!.PDFWorker.fromPort({port: worker});
  function resource(name: string, maps: Record<string, string> | undefined) {
    if (!maps || !/^[A-Za-z0-9_.-]{1,80}$/.test(name) || !Object.prototype.hasOwnProperty.call(maps, name)) {
      throw new Error();
    }
    return Uint8Array.from(atob(maps[name]), character => character.charCodeAt(0));
  }
  class CMapReaderFactory {
    async fetch({name}: {name: string}) {
      return {cMapData: resource(name, window.__MBG_PDF_CMAPS), compressionType: 1};
    }
  }
  class StandardFontDataFactory {
    async fetch({filename}: {filename: string}) {
      return resource(filename, window.__MBG_PDF_STANDARD_FONTS);
    }
  }
  return window.pdfjsLib!.getDocument({
    data: new Uint8Array(data), worker: pdfWorker, CMapReaderFactory, StandardFontDataFactory,
    cMapPacked: true, useWorkerFetch: false, enableXfa: false, isEvalSupported: false,
    useSystemFonts: true, stopAtErrors: true, maxImageSize: 16_000_000,
  }) as PdfTask;
}

// Rasterize only the added text so the device can render Japanese with its
// existing fonts. Every original PDF page and every pen stroke remain intact.
function makeTextCanvas(doc: Document, text: string, widthLimit: number, heightLimit: number) {
  const canvas = doc.createElement('canvas');
  const context = canvas.getContext('2d');
  if (!context || widthLimit < fontSize) throw new Error();
  const density = 3;
  const padding = 2;
  const lineHeight = fontSize * 1.3;
  const font = fontSize + 'px sans-serif';
  context.font = font;
  const lines: string[] = [];
  for (const paragraph of text.split('\n')) {
    let line = '';
    for (const character of Array.from(paragraph)) {
      if (line && context.measureText(line + character).width > widthLimit - 2 * padding) {
        lines.push(line);
        line = '';
      }
      line += character;
    }
    lines.push(line);
  }
  const width = Math.ceil(Math.max(...lines.map(line => context.measureText(line).width)) + 2 * padding);
  const height = Math.ceil(lines.length * lineHeight + 2 * padding);
  if (width > widthLimit || height > heightLimit || width * height > 70000) throw new Error();
  canvas.width = width * density;
  canvas.height = height * density;
  context.scale(density, density);
  context.font = font;
  context.fillStyle = penColor;
  context.textBaseline = 'top';
  lines.forEach((line, index) => context.fillText(line, padding, padding + index * lineHeight));
  return {canvas, width, height};
}

export function openWorksheetEditor(options: WorksheetEditorOptions): () => void {
  const {document: doc, file, container} = options;
  const overlay = doc.createElement('div');
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', 'PDFに書き込む');
  overlay.setAttribute('data-mbg-worksheet-editor', '');
  overlay.style.cssText = 'inset:0;z-index:2147483647;background:#eee;color:#161616;display:flex;flex-direction:column;font:16px sans-serif';
  overlay.style.position = container ? 'absolute' : 'fixed';
  const bar = doc.createElement('div');
  bar.style.cssText = 'display:flex;flex-wrap:wrap;gap:5px;align-items:center;padding:8px;background:#fff';
  const status = doc.createElement('div');
  status.setAttribute('role', 'status');
  status.style.cssText = 'min-height:1em;padding:4px 8px;background:#fff;font:14px sans-serif';
  const content = doc.createElement('div');
  content.style.cssText = 'overflow:auto;flex:1;min-height:0;padding:8px;overscroll-behavior:contain';
  const stage = doc.createElement('div');
  stage.style.cssText = 'position:relative;line-height:0;margin:0 auto;background:#fff';
  const raster = doc.createElement('canvas');
  raster.style.cssText = 'width:100%;height:100%;display:block';
  const ink = doc.createElement('canvas');
  ink.style.cssText = 'position:absolute;inset:0;width:100%;height:100%';
  ink.setAttribute('aria-label', 'PDFの編集面');
  stage.append(raster, ink);
  content.appendChild(stage);
  const abort = new AbortController();
  const pages = new Map<number, EditedPage>();

  let closed = false;
  let rendering = false;
  let exporting = false;
  let worker: Worker | undefined;
  let task: PdfTask | undefined;
  let render: RenderTask | undefined;
  let pdf: PdfDocument | undefined;
  let library: WorksheetPdfLibrary | undefined;
  let pageNumber = 1;
  let zoom = 1;
  let viewport: Viewport | undefined;
  let tool: 'view' | 'pen' | 'text' = 'view';
  let stroke: {pointerId: number; points: Point[]} | undefined;
  let textOrigin: Point | undefined;
  let editCount = 0;
  let repaintFrame: number | undefined;

  function button(label: string, action: () => void) {
    const control = doc.createElement('button');
    control.type = 'button';
    control.textContent = label;
    control.style.cssText = 'font:inherit;padding:5px 8px;min-height:34px';
    control.addEventListener('click', action);
    return control;
  }
  const pageLabel = doc.createElement('span');
  const previous = button('前のページ', () => navigate(-1));
  const next = button('次のページ', () => navigate(1));
  const smaller = button('縮小', () => changeZoom(.8));
  const larger = button('拡大', () => changeZoom(1.25));
  const view = button('閲覧', () => changeTool('view'));
  const pen = button('ペン', () => changeTool('pen'));
  const text = button('文字', () => changeTool('text'));
  const undo = button('元に戻す', undoLast);
  const save = button('書き込んだPDFを使う', () => { void exportPdf(); });
  const close = button('閉じる', closeEditor);
  const discard = button('編集を破棄', () => dispose(true));
  const keepEditing = button('編集に戻る', () => showDiscard(false));
  discard.hidden = keepEditing.hidden = true;
  bar.append(previous, pageLabel, next, smaller, larger, view, pen, text, undo, save, close, discard, keepEditing);

  const textBar = doc.createElement('div');
  textBar.style.cssText = 'display:none;gap:5px;align-items:center;padding:4px 8px;background:#fff;flex-wrap:wrap';
  const textInput = doc.createElement('textarea');
  textInput.rows = 2;
  textInput.maxLength = 200;
  textInput.setAttribute('aria-label', 'PDFに挿入する文字');
  textInput.style.cssText = 'font:16px sans-serif;min-width:0;flex:1';
  textBar.append(textInput, button('文字を挿入', insertText), button('キャンセル', resetText));
  overlay.append(bar, textBar, status, content);
  (container || doc.documentElement || doc.body).appendChild(overlay);
  close.focus();
  status.textContent = 'PDFを読み込み中…';
  updateControls();
  void start();

  async function start() {
    try {
      if (file.size < 1 || file.size > MAX_WORKSHEET_PDF_BYTES) {
        status.textContent = '64 MiB以下のPDFに書き込めます。';
        return;
      }
      library = await loadLibrary(abort.signal);
      if (closed) return;
      const data = await file.arrayBuffer();
      if (closed) return;
      worker = new Worker(window.__MBG_PDF_WORKER_URL!);
      task = getPdf(data, worker);
      const document = await task.promise;
      if (closed) return;
      if (document.numPages < 1 || document.numPages > 2000) throw new Error();
      pdf = document;
      await drawPage();
    } catch (_) {
      if (!closed) status.textContent = 'このPDFは編集用に開けませんでした。';
    }
  }

  function closeEditor() {
    if (editCount) showDiscard(true);
    else dispose(true);
  }

  function showDiscard(show: boolean) {
    resetText();
    discard.hidden = keepEditing.hidden = !show;
    status.textContent = show ? '書き込んだ内容を破棄しますか？' : '';
    updateControls();
    (show ? keepEditing : close).focus();
  }

  function dispose(notify: boolean) {
    if (closed) return;
    closed = true;
    abort.abort();
    if (repaintFrame !== undefined) window.cancelAnimationFrame(repaintFrame);
    releaseStroke();
    try { render?.cancel(); } catch (_) {}
    if (task) void task.destroy().catch(() => {});
    if (worker) worker.terminate();
    overlay.remove();
    if (notify) options.onClose?.();
  }

  function updateControls() {
    const prompt = !discard.hidden;
    const blocked = rendering || exporting || prompt;
    previous.disabled = blocked || pageNumber === 1;
    next.disabled = blocked || !pdf || pageNumber >= pdf.numPages;
    smaller.disabled = blocked || !viewport || zoom <= 1;
    larger.disabled = blocked || !viewport || zoom >= 4;
    for (const [name, control] of [['view', view], ['pen', pen], ['text', text]] as const) {
      control.disabled = blocked || !viewport;
      control.setAttribute('aria-pressed', String(tool === name));
      control.style.fontWeight = tool === name ? 'bold' : 'normal';
    }
    undo.disabled = blocked || !pages.get(pageNumber)?.edits.length;
    save.disabled = blocked || !editCount;
    close.disabled = exporting || prompt;
    ink.style.touchAction = blocked || tool === 'view' ? 'auto' : 'none';
    ink.style.cursor = tool === 'view' ? 'auto' : 'crosshair';
    pageLabel.textContent = pdf ? pageNumber + ' / ' + pdf.numPages : '';
  }

  function navigate(offset: number) {
    pageNumber += offset;
    resetText();
    content.scrollTop = 0;
    void drawPage();
  }

  function changeZoom(factor: number) {
    zoom = Math.max(1, Math.min(4, zoom * factor));
    resetText();
    void drawPage();
  }

  function changeTool(nextTool: typeof tool) {
    releaseStroke();
    scheduleRepaint();
    resetText();
    tool = nextTool;
    status.textContent = tool === 'pen' ? 'PDFの上をなぞって書き込めます。' :
      tool === 'text' ? '文字を入れる位置を選んでください。' : '';
    updateControls();
  }

  async function drawPage() {
    if (!pdf || rendering || closed) return;
    releaseStroke();
    viewport = undefined;
    stage.style.visibility = 'hidden';
    rendering = true;
    updateControls();
    try {
      const page = await pdf.getPage(pageNumber);
      if (closed) return;
      const base = page.getViewport({scale: 1});
      if (!Number.isFinite(base.width) || !Number.isFinite(base.height) || base.width <= 0 || base.height <= 0) throw new Error();
      const cssScale = Math.min(1.5, Math.max(180, content.clientWidth - 16) / base.width) * zoom;
      const scale = Math.min(
        cssScale * Math.min(2, window.devicePixelRatio || 1),
        Math.sqrt(8_000_000 / base.width / base.height),
        4096 / Math.max(base.width, base.height),
      );
      const scaled = page.getViewport({scale});
      const context = raster.getContext('2d');
      if (!context) throw new Error();
      raster.width = ink.width = Math.max(1, Math.ceil(scaled.width));
      raster.height = ink.height = Math.max(1, Math.ceil(scaled.height));
      stage.style.width = Math.min(8192, base.width * cssScale) + 'px';
      stage.style.height = Math.min(8192, base.height * cssScale) + 'px';
      render = page.render({canvasContext: context, viewport: scaled});
      await render.promise;
      if (closed) return;
      viewport = base;
      stage.style.visibility = '';
      repaint();
      status.textContent = '';
    } catch (_) {
      if (!closed) status.textContent = 'ページを表示できませんでした。';
    } finally {
      rendering = false;
      if (!closed) updateControls();
    }
  }

  function getPoint(event: PointerEvent) {
    const bounds = ink.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(1, (event.clientX - bounds.left) / Math.max(1, bounds.width))),
      y: Math.max(0, Math.min(1, (event.clientY - bounds.top) / Math.max(1, bounds.height))),
    };
  }

  function repaint() {
    const context = ink.getContext('2d');
    if (!context || !viewport) return;
    context.clearRect(0, 0, ink.width, ink.height);
    context.strokeStyle = context.fillStyle = penColor;
    context.lineCap = context.lineJoin = 'round';
    context.lineWidth = penThickness * ink.width / viewport.width;
    function paintPen(points: Point[]) {
      context!.beginPath();
      if (points.length === 1) {
        context!.arc(points[0].x * ink.width, points[0].y * ink.height, context!.lineWidth / 2, 0, Math.PI * 2);
        context!.fill();
        return;
      }
      context!.moveTo(points[0].x * ink.width, points[0].y * ink.height);
      for (let index = 1; index < points.length; index++) {
        context!.lineTo(points[index].x * ink.width, points[index].y * ink.height);
      }
      context!.stroke();
    }
    for (const edit of pages.get(pageNumber)?.edits ?? []) {
      if (edit.kind === 'pen') paintPen(edit.points);
      else context.drawImage(edit.canvas, edit.origin.x * ink.width, edit.origin.y * ink.height,
        edit.width * ink.width, edit.height * ink.height);
    }
    if (stroke) paintPen(stroke.points);
  }

  function scheduleRepaint() {
    if (repaintFrame === undefined) {
      repaintFrame = window.requestAnimationFrame(() => {
        repaintFrame = undefined;
        if (!closed) repaint();
      });
    }
  }

  function addEdit(edit: Edit) {
    if (!viewport || editCount >= maxEdits) return;
    let page = pages.get(pageNumber);
    if (!page) {
      page = {viewport, edits: []};
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
    stroke = undefined;
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
    textOrigin = undefined;
    textInput.value = '';
    textBar.style.display = 'none';
  }

  function insertText() {
    if (!viewport || !textOrigin || exporting || rendering) return;
    const value = textInput.value.trim();
    if (!value) { status.textContent = '文字を入力してください。'; return; }
    try {
      const placed = makeTextCanvas(doc, value, (1 - textOrigin.x) * viewport.width, (1 - textOrigin.y) * viewport.height);
      addEdit({kind: 'text', origin: textOrigin, canvas: placed.canvas,
        width: placed.width / viewport.width, height: placed.height / viewport.height});
      resetText();
      text.focus();
      status.textContent = '文字を挿入しました。';
    } catch (_) {
      status.textContent = '文字がページ内に収まる位置を選んでください。';
    }
  }

  async function exportPdf() {
    if (!library || exporting || rendering || !editCount) return;
    releaseStroke();
    resetText();
    exporting = true;
    status.textContent = '記入済みPDFを作成中…';
    updateControls();
    try {
      const buffer = await file.arrayBuffer();
      if (closed) return;
      const bytes = await writeWorksheetPdf(library, buffer, pages);
      if (closed) return;
      if (bytes.byteLength > MAX_WORKSHEET_PDF_BYTES) {
        status.textContent = '記入後のPDFが64 MiBを超えています。';
        return;
      }
      const originalName = file.name.replace(/[/\\\u0000-\u001f\u007f]/g, '_').replace(/\.pdf$/i, '').trim();
      const editedName = (originalName.slice(0, 100) || '答案') + '_記入済み.pdf';
      await options.onExport(new File([bytes], editedName, {type: 'application/pdf'}));
      dispose(true);
    } catch (_) {
      if (!closed) status.textContent = 'PDFを渡せませんでした。書き込んだ内容は残っています。';
    } finally {
      exporting = false;
      if (!closed) updateControls();
    }
  }

  overlay.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    event.stopPropagation();
    event.preventDefault();
    if (exporting) return;
    if (textOrigin) resetText();
    else if (!discard.hidden) showDiscard(false);
    else closeEditor();
  });
  ink.addEventListener('pointerdown', event => {
    if (!viewport || stroke || rendering || exporting || !discard.hidden ||
        tool === 'view' || event.button !== 0 || !event.isPrimary) return;
    if (editCount >= maxEdits) { status.textContent = 'これ以上書き込みを追加できません。'; return; }
    const point = getPoint(event);
    if (tool === 'text') {
      textOrigin = point;
      textBar.style.display = 'flex';
      textInput.focus();
      return;
    }
    event.preventDefault();
    stroke = {pointerId: event.pointerId, points: [point]};
    ink.setPointerCapture(event.pointerId);
    scheduleRepaint();
  });
  ink.addEventListener('pointermove', event => {
    if (stroke?.pointerId !== event.pointerId || stroke.points.length >= maxPoints) return;
    const point = getPoint(event);
    const points = stroke.points;
    const last = points[points.length - 1];
    if (Math.hypot((point.x - last.x) * ink.width, (point.y - last.y) * ink.height) < 1) return;
    points.push(point);
    scheduleRepaint();
  });
  ink.addEventListener('pointerup', event => {
    if (stroke?.pointerId !== event.pointerId) return;
    const {points} = stroke;
    releaseStroke();
    addEdit({kind: 'pen', points});
  });
  function discardStroke() { releaseStroke(); scheduleRepaint(); }
  ink.addEventListener('pointercancel', discardStroke);
  ink.addEventListener('lostpointercapture', discardStroke);
  return () => dispose(false);
}
