/// Shrinks images chosen in Gakujo file inputs that exceed the 5 MB upload
/// limit, before the page sees them.
///
/// Only raster images can be recompressed in the WebView. Other oversized
/// files are left untouched and the user is told why.
class GakujoUploadCompressionScript {
  const GakujoUploadCompressionScript._();

  static const limitBytes = 5 * 1024 * 1024;

  static String build() {
    return r'''
(function() {
  var version = 1;
  window.__MBG_UPLOAD_COMPRESSION_ENABLED = true;
  if (window.__MBG_UPLOAD_COMPRESSION_VERSION === version) {
    if (window.__MBG_UPLOAD_COMPRESSION_UPDATE) {
      window.__MBG_UPLOAD_COMPRESSION_UPDATE();
    }
    return;
  }
  window.__MBG_UPLOAD_COMPRESSION_VERSION = version;

  var limitBytes = 5 * 1024 * 1024;
  // Leave headroom for multipart overhead and servers that count 5,000,000.
  var targetBytes = 4700000;
  var maxCanvasPixels = 16000000;
  var compressibleTypes = [
    'image/jpeg', 'image/png', 'image/webp', 'image/bmp',
    'image/heic', 'image/heif'
  ];
  var replaying = typeof WeakSet === 'function' ? new WeakSet() : null;

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
    return (bytes / 1024 / 1024).toFixed(1) + 'MB';
  }

  function isFileInput(element) {
    return !!element && element.tagName === 'INPUT' &&
      String(element.type || '').toLowerCase() === 'file';
  }

  function fileType(file) {
    var type = String(file.type || '').toLowerCase();
    if (type) {
      return type;
    }
    var name = String(file.name || '').toLowerCase();
    if (/\.jpe?g$/.test(name)) return 'image/jpeg';
    if (/\.png$/.test(name)) return 'image/png';
    if (/\.webp$/.test(name)) return 'image/webp';
    if (/\.bmp$/.test(name)) return 'image/bmp';
    if (/\.hei[cf]$/.test(name)) return 'image/heic';
    return '';
  }

  function acceptAllows(input, type, extension) {
    var accept = String(input.getAttribute('accept') || '').trim();
    if (!accept) {
      return true;
    }
    var entries = accept.toLowerCase().split(',');
    for (var i = 0; i < entries.length; i += 1) {
      var entry = entries[i].trim();
      if (entry === type || entry === '*/*' || entry === 'image/*' ||
          entry === '.' + extension ||
          (extension === 'jpg' && entry === '.jpeg')) {
        return true;
      }
    }
    return false;
  }

  // JPEG compresses photos and scans far better. Keep PNG only when the
  // input's accept list rules JPEG out.
  function outputFormat(input, file) {
    if (acceptAllows(input, 'image/jpeg', 'jpg')) {
      return { type: 'image/jpeg', extension: 'jpg' };
    }
    if (fileType(file) === 'image/png' && acceptAllows(input, 'image/png', 'png')) {
      return { type: 'image/png', extension: 'png' };
    }
    return null;
  }

  function renamed(name, extension) {
    var base = String(name || 'image').replace(/\.[^./\\]*$/, '');
    return (base || 'image') + '.' + extension;
  }

  function loadImage(file) {
    if (typeof createImageBitmap === 'function') {
      return createImageBitmap(file, { imageOrientation: 'from-image' })
        .catch(function() {
          return createImageBitmap(file);
        })
        .catch(function() {
          return loadImageElement(file);
        });
    }
    return loadImageElement(file);
  }

  function loadImageElement(file) {
    return new Promise(function(resolve, reject) {
      var url = URL.createObjectURL(file);
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

  function encode(image, width, height, format, quality) {
    return new Promise(function(resolve, reject) {
      var canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      var context = canvas.getContext('2d');
      if (!context) {
        reject(new Error('画像を処理できませんでした'));
        return;
      }
      if (format.type === 'image/jpeg') {
        // JPEG has no alpha; transparent areas would otherwise turn black.
        context.fillStyle = '#ffffff';
        context.fillRect(0, 0, width, height);
      }
      context.drawImage(image, 0, 0, width, height);
      canvas.toBlob(function(blob) {
        canvas.width = 0;
        canvas.height = 0;
        if (blob) {
          resolve(blob);
        } else {
          reject(new Error('画像を書き出せませんでした'));
        }
      }, format.type, quality);
    });
  }

  function compressImage(input, file) {
    var format = outputFormat(input, file);
    if (!format) {
      return Promise.reject(new Error('この欄で受け付ける形式に圧縮できません'));
    }
    return loadImage(file).then(function(image) {
      var width = image.width || image.naturalWidth;
      var height = image.height || image.naturalHeight;
      if (!width || !height) {
        throw new Error('画像サイズを取得できませんでした');
      }
      var scale = Math.min(1, Math.sqrt(maxCanvasPixels / (width * height)));
      var qualities = format.type === 'image/jpeg' ? [0.85, 0.72, 0.6] : [undefined];
      var attempt = 0;

      function tryNext() {
        var quality = qualities[attempt % qualities.length];
        var w = Math.max(1, Math.round(width * scale));
        var h = Math.max(1, Math.round(height * scale));
        return encode(image, w, h, format, quality).then(function(blob) {
          if (blob.size <= targetBytes) {
            if (image.close) {
              image.close();
            }
            var FileCtor = viewOf(input).File || File;
            return new FileCtor([blob], renamed(file.name, format.extension), {
              type: format.type,
              lastModified: file.lastModified || Date.now()
            });
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
      return tryNext();
    });
  }

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

  function handleChange(event) {
    var input = event.target;
    if (!window.__MBG_UPLOAD_COMPRESSION_ENABLED || !isFileInput(input) ||
        isReplaying(input)) {
      return;
    }
    var files = Array.prototype.slice.call(input.files || []);
    var oversized = files.filter(function(file) {
      return file.size > limitBytes;
    });
    if (!oversized.length) {
      return;
    }
    var unsupported = oversized.filter(function(file) {
      return compressibleTypes.indexOf(fileType(file)) < 0;
    });
    if (unsupported.length) {
      showStatus(input,
        '5MBを超えるファイルがあります（' + unsupported[0].name + '、' +
        formatSize(unsupported[0].size) + '）。画像以外は自動で圧縮できません。',
        true);
      return;
    }
    var DataTransferCtor = viewOf(input).DataTransfer ||
      (typeof DataTransfer === 'function' ? DataTransfer : null);
    if (typeof DataTransferCtor !== 'function') {
      showStatus(input, 'このWebViewでは画像を自動で圧縮できません。', true);
      return;
    }

    // Hold the page's own handlers until the replacement files are ready.
    event.stopImmediatePropagation();
    var originalTotal = oversized.reduce(function(sum, file) {
      return sum + file.size;
    }, 0);
    showStatus(input, '5MBを超える画像を圧縮しています…', false);

    Promise.all(files.map(function(file) {
      return file.size > limitBytes ? compressImage(input, file) : file;
    })).then(function(results) {
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
        '画像を圧縮しました: ' + formatSize(originalTotal) + ' → ' +
        formatSize(compressedTotal), false);
      replayChange(input);
    }, function(error) {
      showStatus(input,
        '画像を圧縮できませんでした: ' + (error && error.message || error) +
        '。元のファイルのままです。', true);
      replayChange(input);
    });
  }

  function attach() {
    var docs = documents();
    for (var i = 0; i < docs.length; i += 1) {
      var doc = docs[i];
      if (doc.__mbgUploadCompressionAttached) {
        continue;
      }
      doc.__mbgUploadCompressionAttached = true;
      // Capture phase runs before handlers registered on the input itself.
      doc.addEventListener('change', handleChange, true);
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
    var owned = docs[d].querySelectorAll('[data-mbg-upload-compression-owned="true"]');
    for (var j = 0; j < owned.length; j += 1) {
      owned[j].remove();
    }
  }
})();
''';
  }
}
