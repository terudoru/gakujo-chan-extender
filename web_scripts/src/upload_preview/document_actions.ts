declare global {
  interface Window {
    MbgPdfReadingProgress?: {postMessage(data: string): void};
    __MBG_PDF_READING_PROGRESS?: (id: number, page: number | null) => void;
    MbgWorksheetExport?: {postMessage(data: string): void};
    __MBG_WORKSHEET_EXPORT?: {
      chunk(id: string, offset: number): string | null;
      reply(id: string, result: boolean): void;
    };
  }
}

const MAX_HASH_BYTES = 64 * 1024 * 1024;
const CHUNK_BYTES = 256 * 1024;
let nextRead = 0;
const readers = new Map<number, (page: number | null) => void>();

export async function loadPdfReadingProgress(bytes: ArrayBuffer) {
  const channel = window.MbgPdfReadingProgress;
  if (!channel || !globalThis.crypto?.subtle || bytes.byteLength > MAX_HASH_BYTES) return null;
  try {
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    const key = Array.from(digest, value => value.toString(16).padStart(2, '0')).join('');
    window.__MBG_PDF_READING_PROGRESS = (id, page) => readers.get(id)?.(page);
    const request = nextRead = (nextRead % 0x7fffffff) + 1;
    const storedPage = await new Promise<number | null>(resolve => {
      const timer = window.setTimeout(() => { readers.delete(request); resolve(null); }, 1200);
      readers.set(request, page => {
        window.clearTimeout(timer);
        readers.delete(request);
        resolve(page);
      });
      channel.postMessage(JSON.stringify({key, request}));
    });
    const initialPage = typeof storedPage === 'number' && Number.isInteger(storedPage) && storedPage >= 1 && storedPage <= 2000 ? storedPage : null;
    let lastPage = initialPage;
    let savedPage = initialPage;
    let timer: number | undefined;
    function flush() {
      window.clearTimeout(timer);
      timer = undefined;
      if (lastPage !== null && lastPage !== savedPage) {
        try {
          channel!.postMessage(JSON.stringify({key, page: lastPage}));
          savedPage = lastPage;
        } catch (_) {
          // Preview cleanup must still stop the worker and release the file.
        }
      }
    }
    return {
      initialPage: initialPage ?? 1,
      pageChanged(page: number) {
        if (!Number.isInteger(page) || page < 1 || page > 2000 || page === lastPage) return;
        lastPage = page;
        window.clearTimeout(timer);
        timer = window.setTimeout(flush, 500);
      },
      flush,
    };
  } catch (_) { return null; }
}

export async function saveWorksheetFile(file: File): Promise<void> {
  const channel = window.MbgWorksheetExport;
  if (!channel || window.__MBG_WORKSHEET_EXPORT || file.size > MAX_HASH_BYTES) throw new Error('保存機能を使えません');
  const id = Array.from(crypto.getRandomValues(new Uint8Array(16)),
    byte => byte.toString(16).padStart(2, '0')).join('');
  const contents = new Uint8Array(await file.arrayBuffer());
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => finish(false), 300000);
    function finish(ok: boolean) {
      window.clearTimeout(timer);
      delete window.__MBG_WORKSHEET_EXPORT;
      if (ok) resolve();
      else reject(new Error('PDFを保存できませんでした'));
    }
    window.__MBG_WORKSHEET_EXPORT = {
      chunk(candidate, offset) {
        if (candidate !== id || !Number.isSafeInteger(offset) || offset < 0 || offset >= file.size) return null;
        const bytes = contents.subarray(offset, offset + CHUNK_BYTES);
        let binary = '';
        for (let index = 0; index < bytes.length; index += 8192) {
          binary += String.fromCharCode(...bytes.subarray(index, index + 8192));
        }
        return btoa(binary);
      },
      reply(candidate, ok) { if (candidate === id) finish(ok === true); },
    };
    try { channel.postMessage(JSON.stringify({id, name: file.name, size: file.size})); }
    catch (_) { finish(false); }
  });
}
