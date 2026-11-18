import { watchPage } from '../shared/page_watch.js';
import { acceptsAttachment, setAssignmentAttachment } from '../shared/assignment_attachment.js';

declare const __mbgConfig: { scan: boolean; shared: boolean };
const MAX_BYTES = 64 * 1024 * 1024;
const CHUNK_BYTES = 256 * 1024;

interface Request {
  id: string;
  input: HTMLInputElement;
  location: string;
  form: HTMLFormElement | null;
  formValues: string;
  files: File[];
}
interface Transfer {
  name: string;
  mime: string;
  size: number;
  received: number;
  parts: Uint8Array<ArrayBuffer>[];
}
interface AttachmentApi {
  setShared(available: boolean): void;
  pending(id: string): boolean;
  begin(id: string, name: string, mime: string, size: number): boolean;
  chunk(id: string, index: number, data: string): boolean;
  finish(id: string): boolean;
  cancel(id: string): void;
}
declare global {
  interface Window {
    __MBG_ASSIGNMENT_ATTACHMENT?: AttachmentApi;
    MbgAssignmentAttachment?: {postMessage(data: string): void};
  }
}

function installAssignmentAttachment() {
  if (window.__MBG_ASSIGNMENT_ATTACHMENT) {
    window.__MBG_ASSIGNMENT_ATTACHMENT.setShared(__mbgConfig.shared);
    return;
  }
  let shared = __mbgConfig.shared;
  let request: Request | null = null;
  let transfer: Transfer | null = null;
  let requestAckTimer: number | undefined;
  const controls = new WeakMap<HTMLInputElement, HTMLSpanElement>();

  function hiddenValues(form: HTMLFormElement | null): string {
    return JSON.stringify(Array.from(form?.querySelectorAll<HTMLInputElement>('input[type=hidden]') || [],
      field => [field.name, field.value]));
  }

  function current(candidate: Request): boolean {
    const { input } = candidate;
    const files = Array.from(input.files || []);
    return input.isConnected && !input.matches(':disabled') && input.type === 'file' &&
      input.ownerDocument.defaultView?.location.href === candidate.location &&
      input.form === candidate.form && hiddenValues(input.form) === candidate.formValues &&
      files.length === candidate.files.length &&
      files.every((file, index) => file === candidate.files[index]);
  }

  function start(input: HTMLInputElement, kind: 'scan' | 'share') {
    const channel = window.MbgAssignmentAttachment;
    const view = input.ownerDocument.defaultView;
    if (!channel || !view || (request && current(request)) || !input.isConnected || input.matches(':disabled')) return;
    const id = Array.from(crypto.getRandomValues(new Uint8Array(16)),
      byte => byte.toString(16).padStart(2, '0')).join('');
    request = {id, input, location: view.location.href, form: input.form,
      formValues: hiddenValues(input.form), files: Array.from(input.files || [])};
    window.clearTimeout(requestAckTimer);
    requestAckTimer = window.setTimeout(() => {
      if (request?.id === id) transfer = request = null;
    }, 5000);
    try { channel.postMessage(JSON.stringify({id, kind, accept: input.accept.slice(0, 1024)})); }
    catch (_) { transfer = request = null; }
  }

  function attach(view: Window) {
    try {
      const doc = view.document;
      for (const input of Array.from(doc.querySelectorAll<HTMLInputElement>('input[type=file]'))) {
        if (!input.parentNode) continue;
        let group = controls.get(input);
        if (!group) {
          group = doc.createElement('span');
          group.appendChild(button('共有したファイルを添付', 'share'));
          if (__mbgConfig.scan) group.appendChild(button('撮ってPDFにする', 'scan'));
          controls.set(input, group);
        }
        group.querySelector<HTMLButtonElement>('[data-mbg-share-attachment]')!.hidden = !shared;
        const scan = group.querySelector<HTMLButtonElement>('[data-mbg-scan-attachment]');
        if (scan) scan.hidden = !acceptsAttachment(input, '答案.pdf', 'application/pdf');
        if (group.previousSibling !== input) input.after(group);
        function button(label: string, kind: 'scan' | 'share') {
          const element = doc.createElement('button');
          element.type = 'button';
          element.textContent = label;
          element.setAttribute('data-mbg-' + kind + '-attachment', '');
          element.style.cssText = 'margin:4px 8px;padding:6px 10px';
          element.addEventListener('click', event => { if (event.isTrusted) start(input, kind); });
          return element;
        }
      }
      for (let index = 0; index < view.frames.length; index++) attach(view.frames[index]);
    } catch (_) {}
  }

  window.__MBG_ASSIGNMENT_ATTACHMENT = {
    setShared(available) { if (shared !== available) { shared = available; attach(window); } },
    pending(id) {
      if (request?.id !== id || !current(request)) return false;
      window.clearTimeout(requestAckTimer);
      return true;
    },
    begin(id, name, mime, size) {
      if (request?.id !== id || !current(request) || !Number.isSafeInteger(size) ||
          size < 1 || size > MAX_BYTES || !name || name.length > 250 ||
          /[\u0000-\u001f/\\]/.test(name) || !acceptsAttachment(request.input, name, mime)) return false;
      transfer = {name, mime, size, received: 0, parts: []};
      return true;
    },
    chunk(id, index, data) {
      if (!request || request.id !== id || !transfer || !current(request) ||
          index !== transfer.parts.length || data.length > Math.ceil(CHUNK_BYTES / 3) * 4) return false;
      const raw = atob(data);
      if (!raw.length || raw.length > CHUNK_BYTES || transfer.received + raw.length > transfer.size) return false;
      transfer.parts.push(Uint8Array.from(raw, character => character.charCodeAt(0)));
      transfer.received += raw.length;
      return true;
    },
    finish(id) {
      if (!request || request.id !== id || !transfer) return false;
      const target = request;
      const file = transfer;
      transfer = request = null;
      if (file.received !== file.size || !current(target)) return false;
      return setAssignmentAttachment(target.input, new File(file.parts, file.name, {type: file.mime}));
    },
    cancel(id) { if (request?.id === id) transfer = request = null; },
  };
  window.addEventListener('pagehide', () => {
    window.clearTimeout(requestAckTimer);
    transfer = request = null;
  });
  attach(window);
  watchPage(window, () => attach(window), {fallbackMs: 5000, legacyIntervalMs: 1000});
}
installAssignmentAttachment();
