export function validateOfficeDirectory(buffer: ArrayBuffer) {
  var bytes = new Uint8Array(buffer);
  var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  var end = -1;
  var min = Math.max(0, bytes.length - 65557);
  for (var p = bytes.length - 22; p >= min; p--) {
    if (view.getUint32(p, true) === 0x06054b50) { end = p; break; }
  }
  if (end < 0 ||
      end + 22 + view.getUint16(end + 20, true) !== bytes.length) {
    throw new Error('文書の構造を確認できません');
  }
  var count = view.getUint16(end + 10, true);
  var size = view.getUint32(end + 12, true);
  var offset = view.getUint32(end + 16, true);
  if (view.getUint16(end + 4, true) !== 0 ||
      view.getUint16(end + 6, true) !== 0 ||
      view.getUint16(end + 8, true) !== count ||
      count === 0xffff || size === 0xffffffff || offset === 0xffffffff ||
      count > 5000 || offset + size > end) {
    throw new Error('文書の構造が大きすぎるか、対応していない形式です');
  }
  var cursor = offset, limit = offset + size;
  for (var i = 0; i < count; i++) {
    if (cursor + 46 > limit || view.getUint32(cursor, true) !== 0x02014b50 ||
        view.getUint32(cursor + 20, true) === 0xffffffff ||
        view.getUint32(cursor + 24, true) === 0xffffffff ||
        view.getUint32(cursor + 42, true) === 0xffffffff) {
      throw new Error('文書の構造が正しくないか、対応していない形式です');
    }
    cursor += 46 + view.getUint16(cursor + 28, true) +
      view.getUint16(cursor + 30, true) + view.getUint16(cursor + 32, true);
    if (cursor > limit) throw new Error('文書の構造が正しくありません');
  }
  if (cursor !== limit) throw new Error('文書の構造が正しくありません');
}

export function readBoundedOfficeStream(
  stream: MbgZipStream,
  cancelled: () => boolean,
  limit: number,
  cancelledMessage: string,
  oversizedMessage: string,
  earlyCancelMessage = cancelledMessage,
) {
  return new Promise<Uint8Array<ArrayBuffer>>(function(resolve, reject) {
    var parts: Uint8Array<ArrayBuffer>[] = [], length = 0, failed = false;
    stream.on('data', function(chunk) {
      if (failed) return;
      length += chunk.length;
      if (cancelled() || length > limit) {
        failed = true;
        stream.pause();
        reject(new Error(cancelled() ? earlyCancelMessage : oversizedMessage));
        return;
      }
      parts.push(chunk);
    });
    stream.on('error', function(error) { if (!failed) reject(error); });
    stream.on('end', function() {
      if (failed) return;
      if (cancelled()) { reject(new Error(cancelledMessage)); return; }
      var bytes = new Uint8Array(length), offset = 0;
      parts.forEach(function(part) { bytes.set(part, offset); offset += part.length; });
      resolve(bytes);
    });
    stream.resume();
  });
}
