export const MAX_PDF_BYTES = 64 * 1024 * 1024;

export interface QpdfWorkerRequest {
  bytes: ArrayBuffer;
  target: number;
  moduleUrl: string;
  wasmUrl: string;
}

export type QpdfWorkerResponse =
  | {type: 'progress'; quality: number | null}
  | {type: 'result'; bytes: ArrayBuffer; quality: number | null}
  | {type: 'error'; message: string};
