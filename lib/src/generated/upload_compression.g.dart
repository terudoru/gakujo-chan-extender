// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/upload_compression/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoUploadCompressionJs(Map<String, Object?> config) =>
    _gakujoUploadCompressionJsPrefix +
    jsonEncode(config) +
    _gakujoUploadCompressionJsSuffix;

const String _gakujoUploadCompressionJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
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

  // web_scripts/src/upload_compression/main.ts
  function uploadCompression() {
    var version = 2;
    var libraryChannelName = __mbgConfig.libraryChannelName;
    window.__MBG_UPLOAD_COMPRESSION_ENABLED = true;
    if (window.__MBG_UPLOAD_COMPRESSION_VERSION === version) {
      if (window.__MBG_UPLOAD_COMPRESSION_UPDATE) {
        window.__MBG_UPLOAD_COMPRESSION_UPDATE();
      }
      return;
    }
    window.__MBG_UPLOAD_COMPRESSION_VERSION = version;
    var limitBytes = 5e6;
    var targetBytes = 47e5;
    var maxCompressionInputBytes = 128 * 1024 * 1024;
    var maxOfficeEntryBytes = 32 * 1024 * 1024;
    var maxOfficeExpandedBytes = 128 * 1024 * 1024;
    var maxCanvasPixels = 16e6;
    var libraryTimeoutMs = 3e4;
    var compressionTimeoutMs = 12e4;
    var replaying = typeof WeakSet === "function" ? /* @__PURE__ */ new WeakSet() : null;
    var libraryWaiters = {};
    var imageTypes = {
      jpg: "image/jpeg",
      jpeg: "image/jpeg",
      png: "image/png",
      webp: "image/webp"
    };
    var officeTypes = {
      docx: "word",
      docm: "word",
      pptx: "ppt",
      pptm: "ppt",
      xlsx: "xl",
      xlsm: "xl"
    };
    function documents() {
      var result = [document];
      var frames = document.querySelectorAll("iframe,frame");
      for (var i = 0; i < frames.length; i += 1) {
        try {
          if (frames[i].contentWindow && frames[i].contentWindow.document) {
            result.push(frames[i].contentWindow.document);
          }
        } catch (e) {
        }
      }
      return result;
    }
    function viewOf(input) {
      return input.ownerDocument && input.ownerDocument.defaultView || window;
    }
    function formatSize(bytes) {
      return (bytes / 1e6).toFixed(1) + "MB";
    }
    function isFileInput(element) {
      return !!element && element.tagName === "INPUT" && String(element.type || "").toLowerCase() === "file";
    }
    function extensionOf(file) {
      var match = /\.([^./\\]+)$/.exec(String(file.name || ""));
      return match ? match[1].toLowerCase() : "";
    }
    function kindOf(file) {
      var extension = extensionOf(file);
      var type = String(file.type || "").toLowerCase();
      if (imageTypes[extension] || /^image\/(jpeg|png|webp)$/.test(type)) {
        return "image";
      }
      if (extension === "pdf" || type === "application/pdf") {
        return "pdf";
      }
      if (officeTypes[extension]) {
        return "office";
      }
      return null;
    }
    function imageTypeOf(file) {
      var type = String(file.type || "").toLowerCase();
      if (/^image\/(jpeg|png|webp)$/.test(type)) {
        return type;
      }
      return imageTypes[extensionOf(file)] || "image/jpeg";
    }
    function makeFile(input, parts, file, type) {
      var FileCtor = viewOf(input).File || File;
      return new FileCtor(parts, file.name, {
        type: type || file.type || "",
        lastModified: file.lastModified || Date.now()
      });
    }
    function readBytes(blob) {
      if (blob.arrayBuffer) {
        return blob.arrayBuffer();
      }
      return new Promise(function(resolve, reject) {
        var reader = new FileReader();
        reader.onload = function() {
          resolve(reader.result);
        };
        reader.onerror = function() {
          reject(reader.error);
        };
        reader.readAsArrayBuffer(blob);
      });
    }
    function libraryReady(kind) {
      if (kind === "pdf") {
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
        if (!channel || typeof channel.postMessage !== "function") {
          reject(new Error("圧縮に必要な機能を読み込めませんでした"));
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
          reject(new Error("圧縮に必要な機能の読み込みがタイムアウトしました"));
        }, libraryTimeoutMs);
        var waiters = libraryWaiters[kind] = libraryWaiters[kind] || [];
        var waiter = function() {
          window.clearTimeout(timer);
          if (libraryReady(kind)) {
            resolve();
          } else {
            reject(new Error("圧縮に必要な機能を読み込めませんでした"));
          }
        };
        waiters.push(waiter);
        if (waiters.length === 1) {
          channel.postMessage(kind);
        }
      });
    }
    function loadImage(blob, cancelled) {
      return mbgValidateImage(blob).then(function() {
        if (cancelled && cancelled()) throw new Error("圧縮を中止しました");
        if (typeof createImageBitmap === "function") {
          return createImageBitmap(blob, { imageOrientation: "from-image" }).catch(function() {
            return createImageBitmap(blob);
          }).catch(function() {
            return loadImageElement(blob);
          });
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
          reject(new Error("画像を読み込めませんでした"));
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
            reject(new Error("画像を書き出せませんでした"));
          }
        }, type, quality);
      });
    }
    function newCanvas(width, height) {
      var canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;
      return canvas;
    }
    function releaseCanvas(canvas) {
      canvas.width = 0;
      canvas.height = 0;
    }
    function encodeImage(image, type, scale, quality) {
      var width = image.width || image.naturalWidth;
      var height = image.height || image.naturalHeight;
      var w = Math.max(1, Math.round(width * scale));
      var h = Math.max(1, Math.round(height * scale));
      var canvas = newCanvas(w, h);
      var context = canvas.getContext("2d");
      if (!context) {
        return Promise.reject(new Error("画像を処理できませんでした"));
      }
      if (type === "image/jpeg") {
        context.fillStyle = "#ffffff";
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
      return type === "image/png" ? [void 0] : [0.85, 0.72, 0.6];
    }
    function compressImage(input, file) {
      var type = imageTypeOf(file);
      var token = input.__mbgUploadCompressionPending;
      function cancelled() {
        return !window.__MBG_UPLOAD_COMPRESSION_ENABLED || input.__mbgUploadCompressionPending !== token;
      }
      return loadImage(file, cancelled).then(function(image) {
        var width = image.width || image.naturalWidth;
        var height = image.height || image.naturalHeight;
        if (!width || !height) {
          throw new Error("画像サイズを取得できませんでした");
        }
        var scale = Math.min(1, Math.sqrt(maxCanvasPixels / (width * height)));
        var qualities = qualitiesFor(type);
        var attempt = 0;
        function tryNext() {
          if (cancelled()) throw new Error("圧縮を中止しました");
          var quality = qualities[attempt % qualities.length];
          return encodeImage(image, type, scale, quality).then(function(blob) {
            if (cancelled()) throw new Error("圧縮を中止しました");
            if (!blob) {
              throw new Error("この形式の画像は圧縮できません");
            }
            if (blob.size <= targetBytes) {
              return makeFile(input, [blob], file, type);
            }
            attempt += 1;
            if (attempt % qualities.length === 0) {
              scale *= Math.max(0.5, Math.min(0.85, Math.sqrt(targetBytes / blob.size)));
            }
            if (attempt >= 12) {
              throw new Error("5MB以下まで小さくできませんでした");
            }
            return tryNext();
          });
        }
        return Promise.resolve().then(tryNext).finally(function() {
          if (image.close) image.close();
        });
      });
    }
    function compressPdf(input, file, progress) {
      if (file.size > 64 * 1024 * 1024) {
        return Promise.reject(new Error("PDFは64 MiB以下のファイルを選択してください"));
      }
      var lockHost = window;
      try {
        if (window.top && window.top.location.origin === window.location.origin) {
          lockHost = window.top;
        }
      } catch (_) {
      }
      if (lockHost.__MBG_ACTIVE_PDF_COMPRESSION) {
        return Promise.reject(new Error("別のPDFを圧縮中です。完了後に再試行してください"));
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
        if (worker) {
          worker.terminate();
          worker = null;
        }
        if (rejectPending) {
          rejectPending(new Error("圧縮を中止しました"));
          rejectPending = null;
        }
      }
      input.__mbgPdfCompressionCancel = cancelWorker;
      return requestLibrary("pdf").then(function() {
        if (cancelled) throw new Error("圧縮を中止しました");
        return readBytes(file);
      }).then(function(buffer) {
        if (cancelled) throw new Error("圧縮を中止しました");
        if (typeof window.Worker !== "function") {
          throw new Error("このWebViewではPDFを安全に圧縮できません");
        }
        return new Promise(function(resolve, reject) {
          rejectPending = reject;
          worker = new window.Worker(window.__MBG_QPDF_WORKER_URL, { type: "module" });
          worker.onmessage = function(event) {
            var result = event.data || {};
            if (result.type === "progress") {
              progress(result.quality === null ? "PDFを圧縮しています…" : "PDF内の画像を圧縮しています…（画質 " + result.quality + "）");
            } else if (result.type === "result" && result.bytes) {
              rejectPending = null;
              resolve(makeFile(input, [result.bytes], file, "application/pdf"));
            } else if (result.type === "error") {
              rejectPending = null;
              reject(new Error(result.message || "PDFを圧縮できませんでした"));
            }
          };
          worker.onerror = function() {
            rejectPending = null;
            reject(new Error("このWebViewではPDFを安全に圧縮できません"));
          };
          worker.postMessage({
            bytes: buffer,
            target: targetBytes,
            moduleUrl: window.__MBG_QPDF_MODULE_URL,
            wasmUrl: window.__MBG_QPDF_WASM_URL
          }, [buffer]);
        });
      }).finally(function() {
        if (worker) {
          worker.terminate();
          worker = null;
        }
        rejectPending = null;
        releaseLock();
        if (input.__mbgPdfCompressionCancel === cancelWorker) {
          delete input.__mbgPdfCompressionCancel;
        }
      });
    }
    var officeSteps = [
      { maxSide: 2400, quality: 0.8 },
      { maxSide: 1600, quality: 0.7 },
      { maxSide: 1200, quality: 0.6 },
      { maxSide: 900, quality: 0.5 },
      { maxSide: 640, quality: 0.45 }
    ];
    function compressOffice(input, file, progress) {
      var folder = officeTypes[extensionOf(file)];
      var mediaPattern = new RegExp("^" + folder + "/media/[^/]+\\.(jpe?g|png)$", "i");
      var original;
      var cancelled = false;
      function cancelOffice() {
        cancelled = true;
      }
      input.__mbgOfficeCompressionCancel = cancelOffice;
      return requestLibrary("office").then(function() {
        if (cancelled) throw new Error("圧縮を中止しました");
        return readBytes(file);
      }).then(function(buffer) {
        original = buffer;
        var step = 0;
        function tryStep() {
          if (cancelled) throw new Error("圧縮を中止しました");
          if (step >= officeSteps.length) {
            throw new Error("5MB以下まで小さくできませんでした");
          }
          progress("文書内の画像を圧縮しています…");
          return rebuildOffice(original, mediaPattern, officeSteps[step], file.type, function() {
            return cancelled;
          }).then(function(bytes) {
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
    function validateOfficeDirectory(buffer) {
      var bytes = new Uint8Array(buffer);
      var view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      var end = -1;
      var min = Math.max(0, bytes.length - 65557);
      for (var p = bytes.length - 4; p >= min; p--) {
        if (view.getUint32(p, true) === 101010256) {
          end = p;
          break;
        }
      }
      if (end < 0 || end + 22 > bytes.length || end + 22 + view.getUint16(end + 20, true) !== bytes.length) {
        throw new Error("文書のZIP構造を確認できません");
      }
      var count = view.getUint16(end + 10, true);
      var size = view.getUint32(end + 12, true);
      var offset = view.getUint32(end + 16, true);
      if (view.getUint16(end + 4, true) !== 0 || view.getUint16(end + 6, true) !== 0 || view.getUint16(end + 8, true) !== count || count === 65535 || size === 4294967295 || offset === 4294967295 || count > 5e3 || offset + size > end) {
        throw new Error("文書のZIP構造が大きすぎるか未対応です");
      }
      var cursor = offset, limit = offset + size;
      for (var i = 0; i < count; i++) {
        if (cursor + 46 > limit || view.getUint32(cursor, true) !== 33639248 || view.getUint32(cursor + 20, true) === 4294967295 || view.getUint32(cursor + 24, true) === 4294967295 || view.getUint32(cursor + 42, true) === 4294967295) {
          throw new Error("文書のZIP構造が不正か未対応です");
        }
        cursor += 46 + view.getUint16(cursor + 28, true) + view.getUint16(cursor + 30, true) + view.getUint16(cursor + 32, true);
        if (cursor > limit) throw new Error("文書のZIP構造が不正です");
      }
      if (cursor !== limit) throw new Error("文書のZIP構造が不正です");
    }
    function rebuildOffice(buffer, mediaPattern, settings, mimeType, cancelled) {
      validateOfficeDirectory(buffer);
      return window.JSZip.loadAsync(buffer).then(function(zip) {
        if (cancelled()) throw new Error("圧縮を中止しました");
        var entries = Object.keys(zip.files);
        if (entries.length > 5e3) throw new Error("文書内のファイルが多すぎます");
        var declaredTotal = 0;
        entries.forEach(function(name) {
          var entry = zip.files[name];
          if (entry.dir) return;
          var size = entry._data && entry._data.uncompressedSize;
          if (!Number.isSafeInteger(size) || size < 0 || size > maxOfficeEntryBytes) {
            throw new Error("文書内のファイルが大きすぎます");
          }
          declaredTotal += size;
          if (declaredTotal > maxOfficeExpandedBytes) {
            throw new Error("文書の展開サイズが大きすぎます");
          }
        });
        var names = Object.keys(zip.files).filter(function(name) {
          return mediaPattern.test(name) && !zip.files[name].dir;
        });
        var checkedIndex = 0, actualTotal = 0;
        function checkNextEntry() {
          if (cancelled()) throw new Error("圧縮を中止しました");
          if (checkedIndex >= entries.length) return nextImage();
          var name = entries[checkedIndex++];
          var entry = zip.files[name];
          if (entry.dir) return checkNextEntry();
          return readBoundedOfficeEntry(entry, cancelled).then(function(bytes) {
            actualTotal += bytes.length;
            if (actualTotal > maxOfficeExpandedBytes) {
              throw new Error("文書の展開サイズが大きすぎます");
            }
            zip.file(name, bytes, {
              binary: true,
              createFolders: false,
              date: entry.date,
              comment: entry.comment,
              unixPermissions: entry.unixPermissions,
              dosPermissions: entry.dosPermissions
            });
            return checkNextEntry();
          });
        }
        var index = 0;
        function nextImage() {
          if (cancelled()) throw new Error("圧縮を中止しました");
          if (index >= names.length) {
            return readBoundedOfficeStream(zip.generateInternalStream({
              type: "uint8array",
              compression: "DEFLATE",
              compressionOptions: { level: 9 },
              mimeType: mimeType || void 0
            }), cancelled, maxOfficeExpandedBytes);
          }
          var name = names[index];
          index += 1;
          var type = /\.png$/i.test(name) ? "image/png" : "image/jpeg";
          return readBoundedOfficeEntry(zip.file(name), cancelled).then(function(bytes) {
            var blob = new Blob([bytes], { type });
            return loadImage(blob, cancelled).then(function(image) {
              var width = image.width || image.naturalWidth;
              var height = image.height || image.naturalHeight;
              var scale = Math.min(1, settings.maxSide / Math.max(width, height));
              if (type === "image/png" && scale >= 1) {
                if (image.close) image.close();
                return null;
              }
              return encodeImage(
                image,
                type,
                scale,
                type === "image/png" ? void 0 : settings.quality
              ).finally(function() {
                if (image.close) image.close();
              });
            }).then(function(encoded) {
              if (!encoded || encoded.size >= bytes.length) {
                return null;
              }
              return readBytes(encoded);
            }, function() {
              return null;
            }).then(function(replacement) {
              if (replacement) {
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
      return readBoundedOfficeStream(entry.internalStream("uint8array"), cancelled, maxOfficeEntryBytes);
    }
    function readBoundedOfficeStream(stream, cancelled, limit) {
      return new Promise(function(resolve, reject) {
        var parts = [], length = 0, failed = false;
        stream.on("data", function(chunk) {
          if (failed) return;
          length += chunk.length;
          if (cancelled() || length > limit) {
            failed = true;
            stream.pause();
            reject(new Error(cancelled() ? "圧縮を中止しました" : "文書内のファイルが大きすぎます"));
            return;
          }
          parts.push(chunk);
        });
        stream.on("error", function(error) {
          if (!failed) reject(error);
        });
        stream.on("end", function() {
          if (failed) return;
          if (cancelled()) {
            reject(new Error("圧縮を中止しました"));
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
    function statusFor(input) {
      var doc = input.ownerDocument;
      var status = input.__mbgUploadCompressionStatus;
      if (status && status.isConnected) {
        return status;
      }
      status = doc.createElement("div");
      status.setAttribute("data-mbg-upload-compression-owned", "true");
      status.setAttribute("role", "status");
      status.style.cssText = "margin:4px 0;font-size:12px;line-height:1.4;";
      if (input.parentNode) {
        input.parentNode.insertBefore(status, input.nextSibling);
      }
      input.__mbgUploadCompressionStatus = status;
      return status;
    }
    function showStatus(input, message, isError) {
      var status = statusFor(input);
      status.textContent = message;
      status.style.color = isError ? "#b00020" : "#1b5e20";
    }
    function replayChange(input) {
      if (replaying) {
        replaying.add(input);
      } else {
        input.__mbgUploadCompressionReplaying = true;
      }
      try {
        var EventCtor = viewOf(input).Event || Event;
        input.dispatchEvent(new EventCtor("input", { bubbles: true }));
        input.dispatchEvent(new EventCtor("change", { bubbles: true }));
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
          showStatus(
            elements[i],
            "ファイルを圧縮しています。完了してから提出してください",
            false
          );
          return true;
        }
      }
      return false;
    }
    function blockPendingSubmit(event) {
      var target = event.target;
      if (event.type === "click") {
        while (target && target.tagName !== "BUTTON" && target.tagName !== "INPUT") {
          target = target.parentNode;
        }
        if (!target || !/^(submit|image)$/.test(String(target.type || (target.tagName === "BUTTON" ? "submit" : "")).toLowerCase())) {
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
      var hooks = window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES = (window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES || []).filter(function(entry) {
        return live.indexOf(entry.prototype) >= 0;
      });
      ["submit", "requestSubmit"].forEach(function(method) {
        if (typeof prototype[method] !== "function" || hooks.some(function(entry2) {
          return entry2.prototype === prototype && entry2.method === method;
        })) {
          return;
        }
        var entry = { prototype, method, original: prototype[method] };
        var wrapper = function() {
          if (!hasPendingCompression(this)) return entry.original.apply(this, arguments);
        };
        wrapper.__mbgFormSubmitHook = entry;
        entry.wrapper = wrapper;
        prototype[method] = wrapper;
        hooks.push(entry);
      });
    }
    function compress(input, file, progress) {
      switch (kindOf(file)) {
        case "image":
          progress("5MBを超える画像を圧縮しています…");
          return compressImage(input, file);
        case "pdf":
          progress("5MBを超えるPDFを圧縮しています…");
          return compressPdf(input, file, progress);
        case "office":
          return compressOffice(input, file, progress);
        default:
          return Promise.reject(new Error("この形式は自動で圧縮できません"));
      }
    }
    function handleChange(event) {
      var input = event.target;
      if (!isFileInput(input) || isReplaying(input)) {
        return;
      }
      if (input.__mbgPdfCompressionCancel) input.__mbgPdfCompressionCancel();
      if (input.__mbgOfficeCompressionCancel) input.__mbgOfficeCompressionCancel();
      var token = input.__mbgUploadCompressionSelection = (input.__mbgUploadCompressionSelection || 0) + 1;
      delete input.__mbgUploadCompressionPending;
      if (!window.__MBG_UPLOAD_COMPRESSION_ENABLED) {
        return;
      }
      var files = Array.prototype.slice.call(input.files || []);
      var generation = window.__MBG_UPLOAD_COMPRESSION_GENERATION || 0;
      var finished = false;
      function isCurrentSelection() {
        return !finished && window.__MBG_UPLOAD_COMPRESSION_ENABLED && (window.__MBG_UPLOAD_COMPRESSION_GENERATION || 0) === generation && input.__mbgUploadCompressionSelection === token && input.files && input.files.length === files.length && files.every(function(file, index) {
          return input.files[index] === file;
        });
      }
      if (input.__mbgUploadCompressionStatus) {
        input.__mbgUploadCompressionStatus.textContent = "";
      }
      var oversized = files.filter(function(file) {
        return file.size > limitBytes;
      });
      if (!oversized.length) {
        return;
      }
      if (oversized.some(function(file) {
        return file.size > maxCompressionInputBytes;
      })) {
        showStatus(input, "圧縮できるファイルのサイズを超えています。", true);
        return;
      }
      var unsupported = oversized.filter(function(file) {
        return !kindOf(file);
      });
      if (unsupported.length) {
        showStatus(
          input,
          "5MBを超えるファイルがあります（" + unsupported[0].name + "、" + formatSize(unsupported[0].size) + "）。この形式は自動で圧縮できません。",
          true
        );
        return;
      }
      var DataTransferCtor = viewOf(input).DataTransfer || (typeof DataTransfer === "function" ? DataTransfer : null);
      if (typeof DataTransferCtor !== "function") {
        showStatus(input, "このWebViewではファイルを自動で圧縮できません。", true);
        return;
      }
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
      var results = [];
      var chain = Promise.resolve();
      files.forEach(function(file) {
        chain = chain.then(function() {
          if (!isCurrentSelection()) throw new Error("圧縮を中止しました");
          if (file.size <= limitBytes) {
            return file;
          }
          return compress(input, file, progress);
        }).then(function(result) {
          if (!isCurrentSelection()) throw new Error("圧縮を中止しました");
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
          reject(new Error("ファイルの圧縮がタイムアウトしました"));
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
        showStatus(
          input,
          "5MB以下に圧縮しました: " + formatSize(originalTotal) + " → " + formatSize(compressedTotal),
          false
        );
        releasePending();
        replayChange(input);
      }).catch(function(error) {
        if (!isCurrentSelection()) {
          return;
        }
        showStatus(input, error && error.keepOriginal ? error.message : "圧縮できませんでした: " + (error && error.message || error) + "。元のファイルのままです。", true);
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
        doc.addEventListener("change", handleChange, true);
        doc.addEventListener("submit", blockPendingSubmit, true);
        doc.addEventListener("click", blockPendingSubmit, true);
      }
    }
    window.__MBG_UPLOAD_COMPRESSION_UPDATE = attach;
    attach();
    window.__MBG_UPLOAD_COMPRESSION_INTERVAL = window.setInterval(attach, 1e3);
  }
  uploadCompression();
})();
})(''';
const String _gakujoUploadCompressionJsSuffix = r''');
''';
