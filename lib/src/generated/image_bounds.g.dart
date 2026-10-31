// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/image_bounds/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoImageBoundsJs = r'''
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

  // web_scripts/src/image_bounds/main.ts
  globalThis.mbgValidateImage = mbgValidateImage;
})();
''';
