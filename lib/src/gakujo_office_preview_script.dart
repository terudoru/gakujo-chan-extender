/// A bounded, text-only Office preview. Document content is inserted as text,
/// and macros, links, formulas and embedded objects are never executed.
class GakujoOfficePreviewScript {
  const GakujoOfficePreviewScript._();

  static const source = r'''
  var officeWaiters = [];
  window.__MBG_UPLOAD_PREVIEW_OFFICE_LIBRARY_LOADED = function() {
    var pending = officeWaiters.splice(0);
    pending.forEach(function(done) { done(); });
  };
  function officeLibrary(setCancel) {
    if (window.JSZip && window['__MBG_UPLOAD_LIBRARY_READY_preview-office']) return Promise.resolve();
    return new Promise(function(resolve, reject) {
      var channel = window.MbgUploadCompression;
      if (!channel || !channel.postMessage) { reject(new Error('文書プレビューを読み込めません')); return; }
      var timer = window.setTimeout(function() {
        var index = officeWaiters.indexOf(done);
        if (index >= 0) officeWaiters.splice(index, 1);
        setCancel(null); reject(new Error('文書プレビューの読み込みがタイムアウトしました'));
      }, 30000);
      function done() {
        window.clearTimeout(timer); setCancel(null);
        if (window.JSZip && window['__MBG_UPLOAD_LIBRARY_READY_preview-office']) resolve();
        else reject(new Error('文書プレビューを読み込めません'));
      }
      officeWaiters.push(done);
      setCancel(function() {
        window.clearTimeout(timer);
        var index = officeWaiters.indexOf(done);
        if (index >= 0) officeWaiters.splice(index, 1);
        resolve();
      });
      if (officeWaiters.length === 1) channel.postMessage('preview-office');
    });
  }
  function mbgCheckOfficeDirectory(buffer) {
    var bytes = new Uint8Array(buffer), view = new DataView(buffer), end = -1;
    for (var i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
      if (view.getUint32(i, true) === 0x06054b50) { end = i; break; }
    }
    if (end < 0 || end + 22 + view.getUint16(end + 20, true) !== bytes.length) throw new Error('文書のZIP構造を確認できません');
    var count = view.getUint16(end + 10, true), size = view.getUint32(end + 12, true), offset = view.getUint32(end + 16, true);
    if (view.getUint16(end + 4, true) !== 0 || view.getUint16(end + 6, true) !== 0 ||
        view.getUint16(end + 8, true) !== count || count === 0xffff || size === 0xffffffff ||
        offset === 0xffffffff || count > 5000 || offset + size > end) throw new Error('文書のZIP構造が大きすぎるか未対応です');
    var cursor = offset, limit = offset + size;
    for (var n = 0; n < count; n++) {
      if (cursor + 46 > limit || view.getUint32(cursor, true) !== 0x02014b50 ||
          view.getUint32(cursor + 20, true) === 0xffffffff || view.getUint32(cursor + 24, true) === 0xffffffff ||
          view.getUint32(cursor + 42, true) === 0xffffffff) throw new Error('文書のZIP構造が不正か未対応です');
      cursor += 46 + view.getUint16(cursor + 28, true) + view.getUint16(cursor + 30, true) + view.getUint16(cursor + 32, true);
      if (cursor > limit) throw new Error('文書のZIP構造が不正です');
    }
    if (cursor !== limit) throw new Error('文書のZIP構造が不正です');
  }
  function mbgOfficeEntry(entry, stopped) {
    return new Promise(function(resolve, reject) {
      var stream = entry.internalStream('uint8array'), parts = [], length = 0, failed = false;
      stream.on('data', function(chunk) {
        if (failed) return;
        length += chunk.length;
        if (stopped() || length > 4 * 1024 * 1024) {
          failed = true; stream.pause(); reject(new Error('文書内のデータが大きすぎるか中止されました')); return;
        }
        parts.push(chunk);
      });
      stream.on('error', function(error) { if (!failed) reject(error); });
      stream.on('end', function() {
        if (failed) return;
        if (stopped()) { reject(new Error('プレビューを中止しました')); return; }
        var bytes = new Uint8Array(length), offset = 0;
        parts.forEach(function(part) { bytes.set(part, offset); offset += part.length; });
        resolve(bytes);
      });
      stream.resume();
    });
  }
  function mbgOfficeText(buffer, extension, stopped) {
    mbgCheckOfficeDirectory(buffer);
    return window.JSZip.loadAsync(buffer).then(function(zip) {
      var entries = Object.keys(zip.files);
      if (entries.length > 5000) throw new Error('文書内のファイルが多すぎます');
      var selected;
      if (/^doc[xm]$/i.test(extension)) selected = ['word/document.xml'];
      else if (/^ppt[xm]$/i.test(extension)) selected = entries.filter(function(n) { return /^ppt\/slides\/slide\d+\.xml$/i.test(n); });
      else selected = entries.filter(function(n) { return /^xl\/worksheets\/sheet\d+\.xml$/i.test(n); });
      selected.sort(function(a, b) { return a.localeCompare(b, undefined, {numeric: true}); });
      if (!selected.length || selected.length > 100 || selected.some(function(n) { return !zip.files[n]; })) throw new Error('文書の本文を確認できません');
      var total = 0, output = [], shared = [];
      function xml(name) {
        var entry = zip.files[name], size = entry && entry._data && entry._data.uncompressedSize;
        if (!entry || !Number.isSafeInteger(size) || size < 0 || size > 4 * 1024 * 1024) throw new Error('文書内のデータが大きすぎます');
        return mbgOfficeEntry(entry, stopped).then(function(bytes) {
          total += bytes.length;
          if (total > 12 * 1024 * 1024) throw new Error('文書の展開サイズが大きすぎます');
          var text = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
          if (/<!DOCTYPE|<!ENTITY/i.test(text)) throw new Error('未対応の文書形式です');
          var result = new DOMParser().parseFromString(text, 'application/xml');
          if (result.getElementsByTagName('parsererror').length) throw new Error('文書の内容を読み込めません');
          return result;
        });
      }
      function elements(node, name) { return Array.prototype.slice.call(node.getElementsByTagNameNS('*', name)); }
      function paragraphText(node) { return elements(node, 't').map(function(x) { return x.textContent; }).join(''); }
      var preparation = Promise.resolve();
      if (/^xls[xm]$/i.test(extension) && zip.files['xl/sharedStrings.xml']) {
        preparation = xml('xl/sharedStrings.xml').then(function(document) {
          var strings = elements(document, 'si');
          if (strings.length > 50000) throw new Error('文書の項目が多すぎます');
          shared = strings.map(paragraphText);
        });
      }
      return preparation.then(function() {
        return selected.reduce(function(chain, name, index) {
          return chain.then(function() {
            if (stopped()) throw new Error('プレビューを中止しました');
            return xml(name).then(function(document) {
              var lines = [];
              if (/^xls[xm]$/i.test(extension)) {
                var rows = elements(document, 'row');
                if (rows.length > 10000) throw new Error('行が多すぎます');
                rows.forEach(function(row) {
                  var cells = elements(row, 'c');
                  if (cells.length > 1000) throw new Error('列が多すぎます');
                  lines.push(cells.map(function(cell) {
                    var values = elements(cell, 'v'), value = values.length ? values[0].textContent : paragraphText(cell);
                    return cell.getAttribute('t') === 's' ? (shared[Number(value)] || '') : value;
                  }).join('\t'));
                });
              } else {
                var paragraphs = elements(document, 'p');
                if (paragraphs.length > 50000) throw new Error('文書の項目が多すぎます');
                lines = paragraphs.map(paragraphText);
              }
              if (selected.length > 1) output.push((/^xls[xm]$/i.test(extension) ? 'シート ' : 'スライド ') + (index + 1));
              output.push(lines.join('\n'));
              if (output.join('\n').length > 1000000) throw new Error('表示できる文字数を超えました');
            });
          });
        }, Promise.resolve()).then(function() { return output.join('\n'); });
      });
    });
  }
''';
}
