import 'gakujo_upload_compression_libraries.dart';

/// Shrinks files chosen in Gakujo file inputs that exceed the 5 MB upload
/// limit, before the page sees them. Every file keeps its name and format:
///
/// - JPEG, PNG and WebP images are re-encoded in the same format.
/// - PDFs are rebuilt with each page rendered as a JPEG image.
/// - Word, PowerPoint and Excel files keep their content and have their
///   embedded pictures re-encoded.
///
/// PDF and Office support uses bundled libraries that the app injects on
/// request through [GakujoUploadCompressionLibraries.channelName].
class GakujoUploadCompressionScript {
  const GakujoUploadCompressionScript._();

  static const limitBytes = 5 * 1024 * 1024;

  static String build() {
    return '''
(function() {
  var version = 2;
  var libraryChannelName = '${GakujoUploadCompressionLibraries.channelName}';
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

  var limitBytes = 5 * 1024 * 1024;
  // Leave headroom for multipart overhead and servers that count 5,000,000.
  var targetBytes = 4700000;
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
    return (bytes / 1024 / 1024).toFixed(1) + 'MB';
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
      return !!(window.pdfjsLib && window.PDFLib);
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

  function loadImage(blob) {
    if (typeof createImageBitmap === 'function') {
      return createImageBitmap(blob, { imageOrientation: 'from-image' })
        .catch(function() {
          return createImageBitmap(blob);
        })
        .catch(function() {
          return loadImageElement(blob);
        });
    }
    return loadImageElement(blob);
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
    return loadImage(file).then(function(image) {
      var width = image.width || image.naturalWidth;
      var height = image.height || image.naturalHeight;
      if (!width || !height) {
        throw new Error('画像サイズを取得できませんでした');
      }
      var scale = Math.min(1, Math.sqrt(maxCanvasPixels / (width * height)));
      var qualities = qualitiesFor(type);
      var attempt = 0;

      function tryNext() {
        var quality = qualities[attempt % qualities.length];
        return encodeImage(image, type, scale, quality).then(function(blob) {
          if (!blob) {
            throw new Error('この形式の画像は圧縮できません');
          }
          if (blob.size <= targetBytes) {
            if (image.close) {
              image.close();
            }
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
      return tryNext();
    });
  }

  // --------------------------------------------------------------------- PDF

  // Rendering resolution and JPEG quality, tried in order until it fits.
  var pdfSteps = [
    { dpi: 150, quality: 0.75 },
    { dpi: 120, quality: 0.65 },
    { dpi: 96, quality: 0.6 },
    { dpi: 72, quality: 0.5 },
    { dpi: 56, quality: 0.45 }
  ];

  var pdfTextMessage = 'PDFの文字が正しく変換できないため、元のファイルのままにしました（5MBを超える場合は提出前に容量を減らしてください）';
  var pdfContentMessage = 'PDFの添付ファイル・フォーム・リンク・注釈を保持できないため、元のファイルのままにしました（5MBを超える場合は提出前に容量を減らしてください）';
  var pdfRenderMessage = 'PDFの内容が正しく変換できないため、元のファイルのままにしました（5MBを超える場合は提出前に容量を減らしてください）';
  var pdfFontChecks = [];

  function keepOriginalPdf(message) {
    var error = new Error(message);
    error.keepOriginal = true;
    return error;
  }

  // The bundled pdf.js worker runs on the page thread. Its warn() uses
  // console.log, so listen there too, and restore the hooks after all jobs.
  function watchPdfFonts() {
    var check = { failed: false, message: pdfRenderMessage };
    var console = window.console;
    var hooks = [];
    if (!pdfFontChecks.length && console) {
      ['log', 'warn', 'error'].forEach(function(level) {
        var original = console[level];
        if (typeof original !== 'function') {
          return;
        }
        var hook = function() {
          var message = Array.prototype.join.call(arguments, ' ');
          var textWarning = /font|cmap|glyph|character/i.test(message);
          var renderWarning = /image|jpx|jbig|jpeg|decode|unable to|failed|corrupt|invalid|bad |unsupported|mask|colorspace|smask/i.test(message);
          if ((level !== 'log' || /warning:|error:/i.test(message)) &&
              !/setting up fake worker|deprecated|deprecation|^info:/i.test(message) &&
              (textWarning || renderWarning)) {
            pdfFontChecks.forEach(function(active) {
              active.failed = true;
              active.message = textWarning ?
                pdfTextMessage : pdfRenderMessage;
            });
          }
          return original.apply(console, arguments);
        };
        hooks.push(function() {
          if (console[level] === hook) {
            console[level] = original;
          }
        });
        console[level] = hook;
      });
      pdfFontChecks.restore = function() {
        hooks.forEach(function(restore) { restore(); });
      };
    }
    pdfFontChecks.push(check);
    check.stop = function() {
      pdfFontChecks.splice(pdfFontChecks.indexOf(check), 1);
      if (!pdfFontChecks.length && pdfFontChecks.restore) {
        pdfFontChecks.restore();
      }
    };
    check.verify = function() {
      if (check.failed) {
        throw keepOriginalPdf(check.message);
      }
    };
    return check;
  }

  function compressPdf(input, file, progress) {
    var fontCheck;
    var loadingTask;
    return requestLibrary('pdf').then(function() {
      return readBytes(file);
    }).then(function(buffer) {
      fontCheck = watchPdfFonts();
      // CMaps and standard font data are not bundled. Fail closed when the
      // source needs them instead of submitting a PDF with missing glyphs.
      loadingTask = window.pdfjsLib.getDocument({
        data: new Uint8Array(buffer),
        isEvalSupported: false,
        useSystemFonts: true,
        stopAtErrors: true,
        verbosity: window.pdfjsLib.VerbosityLevel.WARNINGS
      });
      return loadingTask.promise;
    }).then(function(pdf) {
      var step = 0;
      function tryStep() {
        fontCheck.verify();
        if (step >= pdfSteps.length) {
          throw new Error('5MB以下まで小さくできませんでした');
        }
        var settings = pdfSteps[step];
        return rasterizePdf(pdf, settings, progress, fontCheck).then(function(bytes) {
          fontCheck.verify();
          if (bytes && bytes.length <= targetBytes) {
            return makeFile(input, [bytes], file, 'application/pdf');
          }
          step += 1;
          return tryStep();
        });
      }
      return Promise.all([pdf.getAttachments(), pdf.getFieldObjects()])
        .then(function(content) {
          fontCheck.verify();
          if (content.some(function(items) {
            return items && Object.keys(items).length;
          })) {
            throw keepOriginalPdf(pdfContentMessage);
          }
          return tryStep();
        });
    }).catch(function(error) {
      if (fontCheck) { fontCheck.verify(); }
      if (/font|cmap|glyph/i.test(String(error && error.message || error))) {
        throw keepOriginalPdf(pdfTextMessage);
      }
      if (error && error.name === 'PasswordException') {
        throw new Error('パスワード付きのPDFは圧縮できません');
      }
      throw error;
    }).finally(function() {
      // Keep observing warnings until pdf.js has finished destroying the job.
      return Promise.resolve(loadingTask && loadingTask.destroy())
        .then(function() { if (fontCheck) { fontCheck.verify(); } })
        .finally(function() { if (fontCheck) { fontCheck.stop(); } });
    });
  }

  function checkPdfPage(page, fontCheck) {
    return Promise.all([
      page.getTextContent(), page.getOperatorList(), page.getAnnotations()
    ]).then(function(content) {
      fontCheck.verify();
      var hasText = content[0].items.some(function(item) {
        return /\S/.test(item.str || '');
      });
      var ops = window.pdfjsLib.OPS;
      var hasTextDrawing = content[1].fnArray.some(function(op) {
        return op === ops.showText || op === ops.showSpacedText ||
          op === ops.nextLineShowText || op === ops.nextLineSetSpacingShowText;
      });
      if (hasText && !hasTextDrawing) {
        throw keepOriginalPdf(pdfTextMessage);
      }
      if (content[2].length) {
        throw keepOriginalPdf(pdfContentMessage);
      }
      return page;
    });
  }

  // Returns the rebuilt PDF bytes, or null as soon as the pages alone already
  // exceed the target so the next, smaller step can start.
  function rasterizePdf(pdf, settings, progress, fontCheck) {
    var PDFDocument = window.PDFLib.PDFDocument;
    return PDFDocument.create().then(function(output) {
      var pageNumber = 0;
      var imageBytes = 0;
      function nextPage() {
        pageNumber += 1;
        if (pageNumber > pdf.numPages) {
          return output.save({ useObjectStreams: true });
        }
        progress('PDFを圧縮しています… ' + pageNumber + '/' + pdf.numPages + 'ページ');
        return pdf.getPage(pageNumber).then(function(page) {
          return checkPdfPage(page, fontCheck);
        }).then(function(page) {
          var size = page.getViewport({ scale: 1 });
          var scale = settings.dpi / 72;
          var pixels = size.width * scale * size.height * scale;
          if (pixels > maxCanvasPixels) {
            scale *= Math.sqrt(maxCanvasPixels / pixels);
          }
          var viewport = page.getViewport({ scale: scale });
          var canvas = newCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
          var context = canvas.getContext('2d');
          context.fillStyle = '#ffffff';
          context.fillRect(0, 0, canvas.width, canvas.height);
          return page.render({ canvasContext: context, viewport: viewport }).promise
            .then(function() {
              fontCheck.verify();
              return canvasToBlob(canvas, 'image/jpeg', settings.quality);
            })
            .then(function(blob) {
              if (!blob.size) {
                throw keepOriginalPdf(pdfRenderMessage);
              }
              return readBytes(blob);
            })
            .finally(function() {
              releaseCanvas(canvas);
              page.cleanup();
            })
            .then(function(jpeg) {
              if (!jpeg || !jpeg.byteLength) {
                throw keepOriginalPdf(pdfRenderMessage);
              }
              imageBytes += jpeg.byteLength;
              if (imageBytes > targetBytes) {
                return null;
              }
              return output.embedJpg(jpeg).then(function(image) {
                var outputPage = output.addPage([size.width, size.height]);
                outputPage.drawImage(image, {
                  x: 0, y: 0, width: size.width, height: size.height
                });
                return nextPage();
              });
            });
        });
      }
      return nextPage();
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
    return requestLibrary('office').then(function() {
      return readBytes(file);
    }).then(function(buffer) {
      original = buffer;
      var step = 0;
      function tryStep() {
        if (step >= officeSteps.length) {
          throw new Error('5MB以下まで小さくできませんでした');
        }
        progress('文書内の画像を圧縮しています…');
        return rebuildOffice(original, mediaPattern, officeSteps[step], file.type)
          .then(function(bytes) {
            if (bytes.length <= targetBytes) {
              return makeFile(input, [bytes], file);
            }
            step += 1;
            return tryStep();
          });
      }
      return tryStep();
    });
  }

  function rebuildOffice(buffer, mediaPattern, settings, mimeType) {
    return window.JSZip.loadAsync(buffer).then(function(zip) {
      var names = Object.keys(zip.files).filter(function(name) {
        return mediaPattern.test(name) && !zip.files[name].dir;
      });
      var index = 0;
      function nextImage() {
        if (index >= names.length) {
          return zip.generateAsync({
            type: 'uint8array',
            compression: 'DEFLATE',
            compressionOptions: { level: 9 },
            mimeType: mimeType || undefined
          });
        }
        var name = names[index];
        index += 1;
        var type = /\.png$/i.test(name) ? 'image/png' : 'image/jpeg';
        return zip.file(name).async('uint8array').then(function(bytes) {
          var blob = new Blob([bytes], { type: type });
          return loadImage(blob).then(function(image) {
            var width = image.width || image.naturalWidth;
            var height = image.height || image.naturalHeight;
            var scale = Math.min(1, settings.maxSide / Math.max(width, height));
            // A PNG only shrinks by losing pixels; leave small ones untouched.
            if (type === 'image/png' && scale >= 1) {
              return null;
            }
            return encodeImage(image, type, scale,
              type === 'image/png' ? undefined : settings.quality);
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
      return nextImage();
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
        if (file.size <= limitBytes) {
          return file;
        }
        return compress(input, file, progress);
      }).then(function(result) {
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
