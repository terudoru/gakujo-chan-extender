import 'gakujo_upload_compression_libraries.dart';
import 'gakujo_image_bounds_script.dart';

/// Shrinks files chosen in Gakujo file inputs that exceed the 5 MB upload
/// limit, before the page sees them. Every file keeps its name and format:
///
/// - JPEG, PNG and WebP images are re-encoded in the same format.
/// - PDFs retain their structure and have embedded images compressed with qpdf.
/// - Word, PowerPoint and Excel files keep their content and have their
///   embedded pictures re-encoded.
///
/// PDF and Office support uses bundled libraries that the app injects on
/// request through [GakujoUploadCompressionLibraries.channelName].
class GakujoUploadCompressionScript {
  const GakujoUploadCompressionScript._();

  static const limitBytes = 5000000;

  static String build() {
    return '''
(function() {
  var version = 2;
  var libraryChannelName = '${GakujoUploadCompressionLibraries.channelName}';
  ${GakujoImageBoundsScript.source}
'''
        r'''
  window.__MBG_UPLOAD_COMPRESSION_ENABLED = true;
  if (window.__MBG_UPLOAD_COMPRESSION_VERSION === version) {
    if (window.__MBG_UPLOAD_COMPRESSION_UPDATE) {
      window.__MBG_UPLOAD_COMPRESSION_UPDATE();
    }
    return;
  }
  window.__MBG_UPLOAD_COMPRESSION_VERSION = version;

  var limitBytes = 5000000;
  // Leave headroom for multipart overhead and servers that count 5,000,000.
  var targetBytes = 4700000;
  var maxCompressionInputBytes = 128 * 1024 * 1024;
  var maxOfficeEntryBytes = 32 * 1024 * 1024;
  var maxOfficeExpandedBytes = 128 * 1024 * 1024;
  var maxCanvasPixels = 16000000;
  var libraryTimeoutMs = 30000;
  var compressionTimeoutMs = 120000;
  var replaying = typeof WeakSet === 'function' ? new WeakSet() : null;
  var libraryWaiters = {};

  var imageTypes = {
    jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp'
  };
  var officeTypes = {
    docx: 'word', docm: 'word', pptx: 'ppt', pptm: 'ppt', xlsx: 'xl', xlsm: 'xl'
  };

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

  // Inputs inside the Gakujo iframe belong to that frame's realm.
  function viewOf(input) {
    return input.ownerDocument && input.ownerDocument.defaultView || window;
  }

  function formatSize(bytes) {
    return (bytes / 1000000).toFixed(1) + 'MB';
  }

  function isFileInput(element) {
    return !!element && element.tagName === 'INPUT' &&
      String(element.type || '').toLowerCase() === 'file';
  }

  function extensionOf(file) {
    var match = /\.([^./\\]+)$/.exec(String(file.name || ''));
    return match ? match[1].toLowerCase() : '';
  }

  function kindOf(file) {
    var extension = extensionOf(file);
    var type = String(file.type || '').toLowerCase();
    if (imageTypes[extension] || /^image\/(jpeg|png|webp)$/.test(type)) {
      return 'image';
    }
    if (extension === 'pdf' || type === 'application/pdf') {
      return 'pdf';
    }
    if (officeTypes[extension]) {
      return 'office';
    }
    return null;
  }

  function imageTypeOf(file) {
    var type = String(file.type || '').toLowerCase();
    if (/^image\/(jpeg|png|webp)$/.test(type)) {
      return type;
    }
    return imageTypes[extensionOf(file)] || 'image/jpeg';
  }

  function makeFile(input, parts, file, type) {
    var FileCtor = viewOf(input).File || File;
    return new FileCtor(parts, file.name, {
      type: type || file.type || '',
      lastModified: file.lastModified || Date.now()
    });
  }

  function readBytes(blob) {
    if (blob.arrayBuffer) {
      return blob.arrayBuffer();
    }
    return new Promise(function(resolve, reject) {
      var reader = new FileReader();
      reader.onload = function() { resolve(reader.result); };
      reader.onerror = function() { reject(reader.error); };
      reader.readAsArrayBuffer(blob);
    });
  }

  // ---------------------------------------------------------------- libraries

  function libraryReady(kind) {
    if (kind === 'pdf') {
      return !!(window.__MBG_QPDF_WORKER_URL && window.__MBG_QPDF_MODULE_URL && window.__MBG_QPDF_WASM_URL);
    }
    return !!window.JSZip;
  }

  window.__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED = function(kind) {
    var waiters = libraryWaiters[kind] || [];
    delete libraryWaiters[kind];
    for (var i = 0; i < waiters.length; i += 1) {
      waiters[i]();
    }
  };

  function requestLibrary(kind) {
    if (libraryReady(kind)) {
      return Promise.resolve();
    }
    return new Promise(function(resolve, reject) {
      var channel = window[libraryChannelName];
      if (!channel || typeof channel.postMessage !== 'function') {
        reject(new Error('圧縮に必要な機能を読み込めませんでした'));
        return;
      }
      var timer = window.setTimeout(function() {
        var index = waiters.indexOf(waiter);
        if (index >= 0) {
          waiters.splice(index, 1);
        }
        if (!waiters.length && libraryWaiters[kind] === waiters) {
          delete libraryWaiters[kind];
        }
        reject(new Error('圧縮に必要な機能の読み込みがタイムアウトしました'));
      }, libraryTimeoutMs);
      var waiters = libraryWaiters[kind] = libraryWaiters[kind] || [];
      var waiter = function() {
        window.clearTimeout(timer);
        if (libraryReady(kind)) {
          resolve();
        } else {
          reject(new Error('圧縮に必要な機能を読み込めませんでした'));
        }
      };
      waiters.push(waiter);
      if (waiters.length === 1) {
        channel.postMessage(kind);
      }
    });
  }

  // ------------------------------------------------------------------ images

  function loadImage(blob, cancelled) {
    return mbgValidateImage(blob).then(function() {
      if (cancelled && cancelled()) throw new Error('圧縮を中止しました');
      if (typeof createImageBitmap === 'function') {
        return createImageBitmap(blob, { imageOrientation: 'from-image' })
          .catch(function() { return createImageBitmap(blob); })
          .catch(function() { return loadImageElement(blob); });
      }
      return loadImageElement(blob);
    });
  }

  function loadImageElement(blob) {
    return new Promise(function(resolve, reject) {
      var url = URL.createObjectURL(blob);
      var image = new Image();
      image.onload = function() {
        URL.revokeObjectURL(url);
        resolve(image);
      };
      image.onerror = function() {
        URL.revokeObjectURL(url);
        reject(new Error('画像を読み込めませんでした'));
      };
      image.src = url;
    });
  }

  function canvasToBlob(canvas, type, quality) {
    return new Promise(function(resolve, reject) {
      canvas.toBlob(function(blob) {
        if (blob) {
          resolve(blob);
        } else {
          reject(new Error('画像を書き出せませんでした'));
        }
      }, type, quality);
    });
  }

  function newCanvas(width, height) {
    var canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    return canvas;
  }

  function releaseCanvas(canvas) {
    canvas.width = 0;
    canvas.height = 0;
  }

  // Re-encodes an image in the same format, at most maxSide pixels on its
  // longer edge. Returns null when the browser cannot write that format.
  function encodeImage(image, type, scale, quality) {
    var width = image.width || image.naturalWidth;
    var height = image.height || image.naturalHeight;
    var w = Math.max(1, Math.round(width * scale));
    var h = Math.max(1, Math.round(height * scale));
    var canvas = newCanvas(w, h);
    var context = canvas.getContext('2d');
    if (!context) {
      return Promise.reject(new Error('画像を処理できませんでした'));
    }
    if (type === 'image/jpeg') {
      // JPEG has no alpha; transparent areas would otherwise turn black.
      context.fillStyle = '#ffffff';
      context.fillRect(0, 0, w, h);
    }
    context.drawImage(image, 0, 0, w, h);
    return canvasToBlob(canvas, type, quality).then(function(blob) {
      releaseCanvas(canvas);
      if (blob.type && blob.type !== type) {
        return null;
      }
      return blob;
    });
  }

  function qualitiesFor(type) {
    return type === 'image/png' ? [undefined] : [0.85, 0.72, 0.6];
  }

  function compressImage(input, file) {
    var type = imageTypeOf(file);
    var token = input.__mbgUploadCompressionPending;
    function cancelled() {
      return !window.__MBG_UPLOAD_COMPRESSION_ENABLED ||
        input.__mbgUploadCompressionPending !== token;
    }
    return loadImage(file, cancelled).then(function(image) {
      var width = image.width || image.naturalWidth;
      var height = image.height || image.naturalHeight;
      if (!width || !height) {
        throw new Error('画像サイズを取得できませんでした');
      }
      var scale = Math.min(1, Math.sqrt(maxCanvasPixels / (width * height)));
      var qualities = qualitiesFor(type);
      var attempt = 0;

      function tryNext() {
        if (cancelled()) throw new Error('圧縮を中止しました');
        var quality = qualities[attempt % qualities.length];
        return encodeImage(image, type, scale, quality).then(function(blob) {
          if (cancelled()) throw new Error('圧縮を中止しました');
          if (!blob) {
            throw new Error('この形式の画像は圧縮できません');
          }
          if (blob.size <= targetBytes) {
            return makeFile(input, [blob], file, type);
          }
          attempt += 1;
          if (attempt % qualities.length === 0) {
            scale *= Math.max(0.5, Math.min(0.85, Math.sqrt(targetBytes / blob.size)));
          }
          if (attempt >= 12) {
            throw new Error('5MB以下まで小さくできませんでした');
          }
          return tryNext();
        });
      }
      return Promise.resolve().then(tryNext).finally(function() {
        if (image.close) image.close();
      });
    });
  }

  // --------------------------------------------------------------------- PDF
  // qpdf rewrites the existing PDF instead of rasterizing pages. Each attempt
  // starts from the original bytes to avoid cumulative JPEG degradation.
  function compressPdf(input, file, progress) {
    if (file.size > 64 * 1024 * 1024) {
      return Promise.reject(new Error('PDFは64 MiB以下のファイルを選択してください'));
    }
    var lockHost = window;
    try {
      if (window.top && window.top.location.origin === window.location.origin) {
        lockHost = window.top;
      }
    } catch (_) {}
    if (lockHost.__MBG_ACTIVE_PDF_COMPRESSION) {
      return Promise.reject(new Error('別のPDFを圧縮中です。完了後に再試行してください'));
    }
    var lock = {};
    lockHost.__MBG_ACTIVE_PDF_COMPRESSION = lock;
    var worker = null;
    var cancelled = false;
    var rejectPending = null;
    function releaseLock() {
      if (lockHost.__MBG_ACTIVE_PDF_COMPRESSION === lock) {
        delete lockHost.__MBG_ACTIVE_PDF_COMPRESSION;
      }
    }
    function cancelWorker() {
      cancelled = true;
      if (worker) { worker.terminate(); worker = null; }
      if (rejectPending) { rejectPending(new Error('圧縮を中止しました')); rejectPending = null; }
    }
    input.__mbgPdfCompressionCancel = cancelWorker;
    return requestLibrary('pdf').then(function() {
      if (cancelled) throw new Error('圧縮を中止しました');
      return readBytes(file);
    }).then(function(buffer) {
      if (cancelled) throw new Error('圧縮を中止しました');
      if (typeof window.Worker !== 'function') {
        throw new Error('このWebViewではPDFを安全に圧縮できません');
      }
      return new Promise(function(resolve, reject) {
        rejectPending = reject;
        worker = new window.Worker(window.__MBG_QPDF_WORKER_URL, {type: 'module'});
        worker.onmessage = function(event) {
          var result = event.data || {};
          if (result.type === 'progress') {
            progress(result.quality === null ? 'PDFを圧縮しています…' :
              'PDF内の画像を圧縮しています…（画質 ' + result.quality + '）');
          } else if (result.type === 'result' && result.bytes) {
            rejectPending = null;
            resolve(makeFile(input, [result.bytes], file, 'application/pdf'));
          } else if (result.type === 'error') {
            rejectPending = null;
            reject(new Error(result.message || 'PDFを圧縮できませんでした'));
          }
        };
        worker.onerror = function() {
          rejectPending = null;
          reject(new Error('このWebViewではPDFを安全に圧縮できません'));
        };
        worker.postMessage({bytes: buffer, target: targetBytes,
          moduleUrl: window.__MBG_QPDF_MODULE_URL, wasmUrl: window.__MBG_QPDF_WASM_URL}, [buffer]);
      });
    }).finally(function() {
      if (worker) { worker.terminate(); worker = null; }
      rejectPending = null;
      releaseLock();
      if (input.__mbgPdfCompressionCancel === cancelWorker) {
        delete input.__mbgPdfCompressionCancel;
      }
    });
  }

  // ------------------------------------------------------------------ Office

  // Longest edge in pixels and JPEG quality for embedded pictures.
  var officeSteps = [
    { maxSide: 2400, quality: 0.8 },
    { maxSide: 1600, quality: 0.7 },
    { maxSide: 1200, quality: 0.6 },
    { maxSide: 900, quality: 0.5 },
    { maxSide: 640, quality: 0.45 }
  ];

  function compressOffice(input, file, progress) {
    var folder = officeTypes[extensionOf(file)];
    var mediaPattern = new RegExp('^' + folder + '/media/[^/]+\\.(jpe?g|png)$', 'i');
    var original;
    var cancelled = false;
    function cancelOffice() { cancelled = true; }
    input.__mbgOfficeCompressionCancel = cancelOffice;
    return requestLibrary('office').then(function() {
      if (cancelled) throw new Error('圧縮を中止しました');
      return readBytes(file);
    }).then(function(buffer) {
      original = buffer;
      var step = 0;
      function tryStep() {
        if (cancelled) throw new Error('圧縮を中止しました');
        if (step >= officeSteps.length) {
          throw new Error('5MB以下まで小さくできませんでした');
        }
        progress('文書内の画像を圧縮しています…');
        return rebuildOffice(original, mediaPattern, officeSteps[step], file.type, function() { return cancelled; })
          .then(function(bytes) {
            if (bytes.length <= targetBytes) {
              return makeFile(input, [bytes], file);
            }
            step += 1;
            return tryStep();
          });
      }
      return tryStep();
    }).finally(function() {
      if (input.__mbgOfficeCompressionCancel === cancelOffice) delete input.__mbgOfficeCompressionCancel;
    });
  }

  // Inspect the actual central directory before JSZip parses it synchronously.
  // Reject ZIP64: its extensible metadata has no bounded parser in the bundled
  // version and Office files accepted here are already limited to 128 MiB.
  function validateOfficeDirectory(buffer) {
    var bytes = new Uint8Array(buffer);
    var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    var end = -1;
    var min = Math.max(0, bytes.length - 65557);
    for (var p = bytes.length - 4; p >= min; p--) {
      if (view.getUint32(p, true) === 0x06054b50) { end = p; break; }
    }
    if (end < 0 || end + 22 > bytes.length ||
        end + 22 + view.getUint16(end + 20, true) !== bytes.length) {
      throw new Error('文書のZIP構造を確認できません');
    }
    var count = view.getUint16(end + 10, true);
    var size = view.getUint32(end + 12, true);
    var offset = view.getUint32(end + 16, true);
    if (view.getUint16(end + 4, true) !== 0 ||
        view.getUint16(end + 6, true) !== 0 ||
        view.getUint16(end + 8, true) !== count ||
        count === 0xffff || size === 0xffffffff || offset === 0xffffffff ||
        count > 5000 || offset + size > end) {
      throw new Error('文書のZIP構造が大きすぎるか未対応です');
    }
    var cursor = offset, limit = offset + size;
    for (var i = 0; i < count; i++) {
      if (cursor + 46 > limit || view.getUint32(cursor, true) !== 0x02014b50 ||
          view.getUint32(cursor + 20, true) === 0xffffffff ||
          view.getUint32(cursor + 24, true) === 0xffffffff ||
          view.getUint32(cursor + 42, true) === 0xffffffff) {
        throw new Error('文書のZIP構造が不正か未対応です');
      }
      cursor += 46 + view.getUint16(cursor + 28, true) +
        view.getUint16(cursor + 30, true) + view.getUint16(cursor + 32, true);
      if (cursor > limit) throw new Error('文書のZIP構造が不正です');
    }
    if (cursor !== limit) throw new Error('文書のZIP構造が不正です');
  }

  function rebuildOffice(buffer, mediaPattern, settings, mimeType, cancelled) {
    validateOfficeDirectory(buffer);
    return window.JSZip.loadAsync(buffer).then(function(zip) {
      if (cancelled()) throw new Error('圧縮を中止しました');
      var entries = Object.keys(zip.files);
      if (entries.length > 5000) throw new Error('文書内のファイルが多すぎます');
      var declaredTotal = 0;
      entries.forEach(function(name) {
        var entry = zip.files[name];
        if (entry.dir) return;
        var size = entry._data && entry._data.uncompressedSize;
        if (!Number.isSafeInteger(size) || size < 0 || size > maxOfficeEntryBytes) {
          throw new Error('文書内のファイルが大きすぎます');
        }
        declaredTotal += size;
        if (declaredTotal > maxOfficeExpandedBytes) {
          throw new Error('文書の展開サイズが大きすぎます');
        }
      });
      var names = Object.keys(zip.files).filter(function(name) {
        return mediaPattern.test(name) && !zip.files[name].dir;
      });
      var checkedIndex = 0, actualTotal = 0;
      function checkNextEntry() {
        if (cancelled()) throw new Error('圧縮を中止しました');
        if (checkedIndex >= entries.length) return nextImage();
        var name = entries[checkedIndex++];
        var entry = zip.files[name];
        if (entry.dir) return checkNextEntry();
        return readBoundedOfficeEntry(entry, cancelled).then(function(bytes) {
          actualTotal += bytes.length;
          if (actualTotal > maxOfficeExpandedBytes) {
            throw new Error('文書の展開サイズが大きすぎます');
          }
          // Preserve metadata while replacing all compressed input with bytes
          // already checked against the actual, not just declared, size.
          zip.file(name, bytes, {binary: true, createFolders: false,
            date: entry.date, comment: entry.comment,
            unixPermissions: entry.unixPermissions, dosPermissions: entry.dosPermissions});
          return checkNextEntry();
        });
      }
      var index = 0;
      function nextImage() {
        if (cancelled()) throw new Error('圧縮を中止しました');
        if (index >= names.length) {
          return readBoundedOfficeStream(zip.generateInternalStream({
            type: 'uint8array',
            compression: 'DEFLATE',
            compressionOptions: { level: 9 },
            mimeType: mimeType || undefined
          }), cancelled, maxOfficeExpandedBytes);
        }
        var name = names[index];
        index += 1;
        var type = /\.png$/i.test(name) ? 'image/png' : 'image/jpeg';
        return readBoundedOfficeEntry(zip.file(name), cancelled).then(function(bytes) {
          var blob = new Blob([bytes], { type: type });
          return loadImage(blob, cancelled).then(function(image) {
            var width = image.width || image.naturalWidth;
            var height = image.height || image.naturalHeight;
            var scale = Math.min(1, settings.maxSide / Math.max(width, height));
            // A PNG only shrinks by losing pixels; leave small ones untouched.
            if (type === 'image/png' && scale >= 1) {
              if (image.close) image.close();
              return null;
            }
            return encodeImage(image, type, scale,
              type === 'image/png' ? undefined : settings.quality)
              .finally(function() { if (image.close) image.close(); });
          }).then(function(encoded) {
            if (!encoded || encoded.size >= bytes.length) {
              return null;
            }
            return readBytes(encoded);
          }, function() {
            // Pictures the WebView cannot decode stay as they are.
            return null;
          }).then(function(replacement) {
            if (replacement) {
              // Real Office files have no folder entries; do not add any.
              zip.file(name, replacement, { createFolders: false });
            }
            return nextImage();
          });
        });
      }
      return checkNextEntry();
    });
  }

  function readBoundedOfficeEntry(entry, cancelled) {
    return readBoundedOfficeStream(entry.internalStream('uint8array'), cancelled, maxOfficeEntryBytes);
  }

  function readBoundedOfficeStream(stream, cancelled, limit) {
    return new Promise(function(resolve, reject) {
      var parts = [], length = 0, failed = false;
      stream.on('data', function(chunk) {
        if (failed) return;
        length += chunk.length;
        if (cancelled() || length > limit) {
          failed = true;
          stream.pause();
          reject(new Error(cancelled() ? '圧縮を中止しました' : '文書内のファイルが大きすぎます'));
          return;
        }
        parts.push(chunk);
      });
      stream.on('error', function(error) { if (!failed) reject(error); });
      stream.on('end', function() {
        if (failed) return;
        if (cancelled()) { reject(new Error('圧縮を中止しました')); return; }
        var bytes = new Uint8Array(length), offset = 0;
        parts.forEach(function(part) { bytes.set(part, offset); offset += part.length; });
        resolve(bytes);
      });
      stream.resume();
    });
  }

  // -------------------------------------------------------------- page glue

  function statusFor(input) {
    var doc = input.ownerDocument;
    var status = input.__mbgUploadCompressionStatus;
    if (status && status.isConnected) {
      return status;
    }
    status = doc.createElement('div');
    status.setAttribute('data-mbg-upload-compression-owned', 'true');
    status.setAttribute('role', 'status');
    status.style.cssText = 'margin:4px 0;font-size:12px;line-height:1.4;';
    if (input.parentNode) {
      input.parentNode.insertBefore(status, input.nextSibling);
    }
    input.__mbgUploadCompressionStatus = status;
    return status;
  }

  function showStatus(input, message, isError) {
    var status = statusFor(input);
    status.textContent = message;
    status.style.color = isError ? '#b00020' : '#1b5e20';
  }

  function replayChange(input) {
    if (replaying) {
      replaying.add(input);
    } else {
      input.__mbgUploadCompressionReplaying = true;
    }
    try {
      var EventCtor = viewOf(input).Event || Event;
      input.dispatchEvent(new EventCtor('input', { bubbles: true }));
      input.dispatchEvent(new EventCtor('change', { bubbles: true }));
    } finally {
      if (replaying) {
        replaying.delete(input);
      } else {
        input.__mbgUploadCompressionReplaying = false;
      }
    }
  }

  function isReplaying(input) {
    return replaying ? replaying.has(input) : !!input.__mbgUploadCompressionReplaying;
  }

  function hasPendingCompression(form) {
    if (!window.__MBG_UPLOAD_COMPRESSION_ENABLED) {
      return false;
    }
    var elements = form && form.elements || [];
    for (var i = 0; i < elements.length; i += 1) {
      if (elements[i].__mbgUploadCompressionPending) {
        showStatus(elements[i],
          'ファイルを圧縮しています。完了してから提出してください', false);
        return true;
      }
    }
    return false;
  }

  function blockPendingSubmit(event) {
    var target = event.target;
    if (event.type === 'click') {
      while (target && target.tagName !== 'BUTTON' && target.tagName !== 'INPUT') {
        target = target.parentNode;
      }
      if (!target || !/^(submit|image)$/.test(String(target.type ||
          (target.tagName === 'BUTTON' ? 'submit' : '')).toLowerCase())) {
        return;
      }
      target = target.form;
    }
    if (hasPendingCompression(target)) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }

  function wrapFormSubmits(doc) {
    if (!window.__MBG_UPLOAD_COMPRESSION_ENABLED) return;
    var view = doc.defaultView;
    var prototype = view && view.HTMLFormElement && view.HTMLFormElement.prototype;
    if (!prototype) return;
    var live = documents().map(function(liveDoc) {
      var liveView = liveDoc.defaultView;
      return liveView && liveView.HTMLFormElement && liveView.HTMLFormElement.prototype;
    });
    // Replaced iframe documents leave their prototypes behind; drop those.
    var hooks = window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES =
      (window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES || []).filter(function(entry) {
        return live.indexOf(entry.prototype) >= 0;
      });
    ['submit', 'requestSubmit'].forEach(function(method) {
      if (typeof prototype[method] !== 'function' || hooks.some(function(entry) {
        return entry.prototype === prototype && entry.method === method;
      })) {
        return;
      }
      var entry = { prototype: prototype, method: method, original: prototype[method] };
      var wrapper = function() {
        if (!hasPendingCompression(this)) return entry.original.apply(this, arguments);
      };
      // Both page scripts use this link to remove a hook beneath the other.
      wrapper.__mbgFormSubmitHook = entry;
      entry.wrapper = wrapper;
      prototype[method] = wrapper;
      hooks.push(entry);
    });
  }

  function compress(input, file, progress) {
    switch (kindOf(file)) {
      case 'image':
        progress('5MBを超える画像を圧縮しています…');
        return compressImage(input, file);
      case 'pdf':
        progress('5MBを超えるPDFを圧縮しています…');
        return compressPdf(input, file, progress);
      case 'office':
        return compressOffice(input, file, progress);
      default:
        return Promise.reject(new Error('この形式は自動で圧縮できません'));
    }
  }

  function handleChange(event) {
    var input = event.target;
    if (!isFileInput(input) || isReplaying(input)) {
      return;
    }
    if (input.__mbgPdfCompressionCancel) input.__mbgPdfCompressionCancel();
    if (input.__mbgOfficeCompressionCancel) input.__mbgOfficeCompressionCancel();
    var token = input.__mbgUploadCompressionSelection =
      (input.__mbgUploadCompressionSelection || 0) + 1;
    delete input.__mbgUploadCompressionPending;
    if (!window.__MBG_UPLOAD_COMPRESSION_ENABLED) {
      return;
    }
    var files = Array.prototype.slice.call(input.files || []);
    var generation = window.__MBG_UPLOAD_COMPRESSION_GENERATION || 0;
    var finished = false;
    function isCurrentSelection() {
      return !finished && window.__MBG_UPLOAD_COMPRESSION_ENABLED &&
        (window.__MBG_UPLOAD_COMPRESSION_GENERATION || 0) === generation &&
        input.__mbgUploadCompressionSelection === token &&
        input.files && input.files.length === files.length &&
        files.every(function(file, index) { return input.files[index] === file; });
    }
    if (input.__mbgUploadCompressionStatus) {
      input.__mbgUploadCompressionStatus.textContent = '';
    }
    var oversized = files.filter(function(file) {
      return file.size > limitBytes;
    });
    if (!oversized.length) {
      return;
    }
    if (oversized.some(function(file) { return file.size > maxCompressionInputBytes; })) {
      showStatus(input, '圧縮できるファイルのサイズを超えています。', true);
      return;
    }
    var unsupported = oversized.filter(function(file) {
      return !kindOf(file);
    });
    if (unsupported.length) {
      showStatus(input,
        '5MBを超えるファイルがあります（' + unsupported[0].name + '、' +
        formatSize(unsupported[0].size) + '）。この形式は自動で圧縮できません。',
        true);
      return;
    }
    var DataTransferCtor = viewOf(input).DataTransfer ||
      (typeof DataTransfer === 'function' ? DataTransfer : null);
    if (typeof DataTransferCtor !== 'function') {
      showStatus(input, 'このWebViewではファイルを自動で圧縮できません。', true);
      return;
    }

    // Hold the page's own handlers until the replacement files are ready.
    event.stopImmediatePropagation();
    input.__mbgUploadCompressionPending = token;
    var originalTotal = oversized.reduce(function(sum, file) {
      return sum + file.size;
    }, 0);
    function progress(message) {
      if (isCurrentSelection()) {
        showStatus(input, message, false);
      }
    }

    // One file at a time keeps memory use bounded on phones.
    var results = [];
    var chain = Promise.resolve();
    files.forEach(function(file) {
      chain = chain.then(function() {
        if (!isCurrentSelection()) throw new Error('圧縮を中止しました');
        if (file.size <= limitBytes) {
          return file;
        }
        return compress(input, file, progress);
      }).then(function(result) {
        if (!isCurrentSelection()) throw new Error('圧縮を中止しました');
        results.push(result);
      });
    });

    function releasePending() {
      if (input.__mbgUploadCompressionPending === token) {
        delete input.__mbgUploadCompressionPending;
      }
    }
    var timer;
    var timeout = new Promise(function(resolve, reject) {
      timer = window.setTimeout(function() {
        if (input.__mbgUploadCompressionPending === token && input.__mbgPdfCompressionCancel) {
          input.__mbgPdfCompressionCancel();
        }
        if (input.__mbgUploadCompressionPending === token && input.__mbgOfficeCompressionCancel) {
          input.__mbgOfficeCompressionCancel();
        }
        reject(new Error('ファイルの圧縮がタイムアウトしました'));
      }, compressionTimeoutMs);
    });
    Promise.race([chain, timeout]).then(function() {
      if (!isCurrentSelection()) {
        return;
      }
      var transfer = new DataTransferCtor();
      var compressedTotal = 0;
      for (var i = 0; i < results.length; i += 1) {
        transfer.items.add(results[i]);
        if (files[i].size > limitBytes) {
          compressedTotal += results[i].size;
        }
      }
      input.files = transfer.files;
      showStatus(input,
        '5MB以下に圧縮しました: ' + formatSize(originalTotal) + ' → ' +
        formatSize(compressedTotal), false);
      // Release the submit hold first: the page's change handler may submit.
      releasePending();
      replayChange(input);
    }).catch(function(error) {
      if (!isCurrentSelection()) {
        return;
      }
      showStatus(input, error && error.keepOriginal ? error.message :
        '圧縮できませんでした: ' + (error && error.message || error) +
        '。元のファイルのままです。', true);
      releasePending();
      replayChange(input);
    }).finally(function() {
      finished = true;
      window.clearTimeout(timer);
      releasePending();
    });
  }

  function attach() {
    var docs = documents();
    for (var i = 0; i < docs.length; i += 1) {
      var doc = docs[i];
      wrapFormSubmits(doc);
      if (doc.__mbgUploadCompressionAttached) {
        continue;
      }
      doc.__mbgUploadCompressionAttached = true;
      // Capture phase runs before handlers registered on the input itself.
      doc.addEventListener('change', handleChange, true);
      doc.addEventListener('submit', blockPendingSubmit, true);
      doc.addEventListener('click', blockPendingSubmit, true);
    }
  }

  window.__MBG_UPLOAD_COMPRESSION_UPDATE = attach;
  attach();
  // Gakujo swaps pages inside a same-origin iframe without a top-level load.
  window.__MBG_UPLOAD_COMPRESSION_INTERVAL = window.setInterval(attach, 1000);
})();
''';
  }

  static String buildTeardown() {
    return r'''
(function() {
  window.__MBG_UPLOAD_COMPRESSION_ENABLED = false;
  window.__MBG_UPLOAD_COMPRESSION_GENERATION =
    (window.__MBG_UPLOAD_COMPRESSION_GENERATION || 0) + 1;
  var hooks = window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES || [];
  hooks.forEach(function(entry) {
    var owner = entry.prototype;
    var key = entry.method;
    while (owner[key] && owner[key] !== entry.wrapper && owner[key].__mbgFormSubmitHook) {
      owner = owner[key].__mbgFormSubmitHook;
      key = 'original';
    }
    if (owner[key] === entry.wrapper) owner[key] = entry.original;
  });
  window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES = [];
  var docs = [document];
  var frames = document.querySelectorAll('iframe,frame');
  for (var i = 0; i < frames.length; i += 1) {
    try {
      if (frames[i].contentWindow && frames[i].contentWindow.document) {
        docs.push(frames[i].contentWindow.document);
      }
    } catch (e) {
      // Cross-origin frames cannot be inspected.
    }
  }
  for (var d = 0; d < docs.length; d += 1) {
    var inputs = docs[d].querySelectorAll('input[type="file"]');
    for (var k = 0; k < inputs.length; k += 1) {
      if (inputs[k].__mbgPdfCompressionCancel) inputs[k].__mbgPdfCompressionCancel();
      if (inputs[k].__mbgOfficeCompressionCancel) inputs[k].__mbgOfficeCompressionCancel();
      delete inputs[k].__mbgUploadCompressionPending;
    }
    var owned = docs[d].querySelectorAll('[data-mbg-upload-compression-owned="true"]');
    for (var j = 0; j < owned.length; j += 1) {
      owned[j].remove();
    }
  }
})();
''';
  }
}
