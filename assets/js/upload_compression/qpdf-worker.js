// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/qpdf_worker/main.ts
// Regenerate with: npm --prefix web_scripts run build

// web_scripts/src/shared/qpdf_worker_messages.ts
var MAX_PDF_BYTES = 64 * 1024 * 1024;

// web_scripts/src/qpdf_worker/main.ts
var MAX_INSPECTION_BYTES = 2 * 1024 * 1024;
var MAX_WASM_PAGES = 4096;
function limitWasmMemory(input, maxPages) {
  const bytes = new Uint8Array(input);
  if (bytes.length < 8 || bytes[0] !== 0 || bytes[1] !== 97 || bytes[2] !== 115 || bytes[3] !== 109 || bytes[4] !== 1 || bytes[5] !== 0 || bytes[6] !== 0 || bytes[7] !== 0) {
    throw new Error("PDF処理モジュールを確認できません");
  }
  function read(cursor, end) {
    let value = 0, shift = 0, byte;
    do {
      if (cursor.pos >= end || shift > 28) throw new Error("不正なWASM形式です");
      byte = bytes[cursor.pos++];
      value += (byte & 127) * 2 ** shift;
      shift += 7;
    } while (byte & 128);
    if (!Number.isSafeInteger(value) || value > 4294967295) throw new Error("不正なWASM形式です");
    return value;
  }
  function encode(value) {
    const result2 = [];
    do {
      let byte = value % 128;
      value = Math.floor(value / 128);
      if (value) byte |= 128;
      result2.push(byte);
    } while (value);
    return result2;
  }
  let position = 8, memorySeen = false;
  const parts = [bytes.slice(0, 8)];
  while (position < bytes.length) {
    const section = bytes[position++];
    const cursor = { pos: position };
    const size = read(cursor, bytes.length);
    const end = cursor.pos + size;
    if (end > bytes.length) throw new Error("不正なWASM形式です");
    let payload = bytes.slice(cursor.pos, end);
    if (section === 5) {
      if (memorySeen) throw new Error("PDF処理のメモリーを制限できません");
      memorySeen = true;
      const memory = { pos: cursor.pos };
      const count = read(memory, end);
      const flags = read(memory, end);
      const initial = read(memory, end);
      const maximum = flags === 1 ? read(memory, end) : 0;
      if (count !== 1 || flags !== 1 || initial > maxPages || maximum < initial || memory.pos !== end) {
        throw new Error("PDF処理のメモリーを制限できません");
      }
      payload = Uint8Array.from([1, 1, ...encode(initial), ...encode(Math.min(maximum, maxPages))]);
    }
    parts.push(Uint8Array.from([section, ...encode(payload.length)]), payload);
    position = end;
  }
  if (!memorySeen) throw new Error("PDF処理のメモリーを制限できません");
  const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}
function limitFilesystem(fs, inputLimit, inspectionLimit, outputLimit) {
  fs.writeFile("/budget-probe", new Uint8Array(0));
  const node = fs.lookupPath("/budget-probe").node;
  const streamOps = node.stream_ops, nodeOps = node.node_ops;
  if (!streamOps || !nodeOps || typeof streamOps.write !== "function" || typeof nodeOps.setattr !== "function" || typeof fs.getPath !== "function") {
    throw new Error("PDF処理の保存領域を制限できません");
  }
  fs.unlink("/budget-probe");
  const originalWrite = streamOps.write, originalSetattr = nodeOps.setattr;
  function check(node2, size) {
    const path = fs.getPath(node2);
    const limit = path === "/input.pdf" ? inputLimit : path === "/inspect.json" ? inspectionLimit : path === "/output.pdf" ? outputLimit : 0;
    if (!Number.isSafeInteger(size) || size < 0 || size > limit || !limit) {
      throw new Error("PDFの処理量が安全な上限を超えました");
    }
  }
  streamOps.write = function(stream, buffer, offset, length, position, canOwn) {
    check(stream.node, position + length);
    return originalWrite.call(this, stream, buffer, offset, length, position, canOwn);
  };
  nodeOps.setattr = function(node2, attributes) {
    if (attributes.size !== void 0) check(node2, attributes.size);
    return originalSetattr.call(this, node2, attributes);
  };
}
var worker = self;
worker.onmessage = async function(event) {
  const message = event.data;
  try {
    if (!(message.bytes instanceof ArrayBuffer) || message.bytes.byteLength > MAX_PDF_BYTES) {
      throw new Error("PDFは64 MiB以下のファイルを選択してください");
    }
    const createModule = (await import(message.moduleUrl)).default;
    const response = await fetch(message.wasmUrl);
    if (!response.ok) throw new Error("qpdf を読み込めませんでした");
    const compiled = await WebAssembly.compile(limitWasmMemory(await response.arrayBuffer(), MAX_WASM_PAGES));
    if (WebAssembly.Module.imports(compiled).some(function(item) {
      return item.kind === "memory";
    })) {
      throw new Error("PDF処理のメモリーを制限できません");
    }
    const original = new Uint8Array(message.bytes);
    const errors = [];
    const module = await createModule({
      print: function() {
      },
      printErr: function(s) {
        if (errors.length < 20) errors.push(String(s).slice(0, 300));
      },
      instantiateWasm: function(imports, done) {
        const instance = new WebAssembly.Instance(compiled, imports);
        done(instance, compiled);
        return instance.exports;
      }
    });
    limitFilesystem(module.FS, MAX_PDF_BYTES, MAX_INSPECTION_BYTES, MAX_PDF_BYTES);
    module.FS.writeFile("/input.pdf", original);
    async function run(args, outputName, shouldRead) {
      errors.length = 0;
      let code;
      try {
        code = module.callMain([
          "--global",
          "--parser-max-nesting=100",
          "--parser-max-container-size=100000",
          "--"
        ].concat(args));
      } catch (error) {
        if (error && typeof error === "object" && "status" in error && typeof error.status === "number") code = error.status;
        else throw error;
      }
      if (code !== 0) throw new Error(errors.join(" ").slice(0, 300) || "PDFを安全に処理できません");
      const limit = outputName === "/inspect.json" ? MAX_INSPECTION_BYTES : MAX_PDF_BYTES;
      const size = module.FS.stat(outputName).size;
      if (!Number.isSafeInteger(size) || size < 0 || size > limit) {
        throw new Error("PDFの処理量が安全な上限を超えました");
      }
      const result = !shouldRead || shouldRead(size) ? module.FS.readFile(outputName) : null;
      module.FS.unlink(outputName);
      return result;
    }
    const json = await run([
      "/input.pdf",
      "--json",
      "--json-key=qpdf",
      "--json-key=encrypt",
      "/inspect.json"
    ], "/inspect.json");
    const info = JSON.parse(new TextDecoder().decode(json));
    if (info.encrypt && info.encrypt.encrypted) throw new Error("暗号化されたPDFは圧縮できません");
    const stack = [info.qpdf];
    while (stack.length) {
      const value = stack.pop();
      if (!value || typeof value !== "object") continue;
      const object = value;
      if (object["/FT"] === "/Sig" || object["/Type"] === "/Sig" || object["/ByteRange"] || object["/DocMDP"]) {
        throw new Error("署名付きPDFは圧縮できません");
      }
      for (const key of Object.keys(object)) {
        if (object[key] && typeof object[key] === "object") stack.push(object[key]);
      }
    }
    const levels = [null, 85, 75, 65, 55, 45];
    for (const quality of levels) {
      worker.postMessage({ type: "progress", quality });
      const args = ["/input.pdf", "--object-streams=generate"];
      if (quality !== null) args.push("--optimize-images", "--jpeg-quality=" + quality);
      args.push("/output.pdf");
      const output = await run(args, "/output.pdf", function(size) {
        return size <= message.target && size < original.length;
      });
      if (output) {
        worker.postMessage({ type: "result", bytes: output.buffer, quality }, [output.buffer]);
        return;
      }
    }
    throw new Error("文字の読みやすさを保つ設定では5MB以下にできませんでした");
  } catch (error) {
    const detail = error && (typeof error === "object" || typeof error === "function") && "message" in error ? error.message : void 0;
    worker.postMessage({ type: "error", message: String(detail || error).slice(0, 300) });
  }
};
