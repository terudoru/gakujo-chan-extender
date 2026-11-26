import { once } from "node:events";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { build } from "vite";

export async function buildArchiveBundle({ entry, name, source, ...config }) {
  const virtualEntry = "\0" + entry;
  const bundle = await build({
    root: fileURLToPath(new URL("../", import.meta.url)),
    logLevel: "error",
    ...config,
    plugins: [{
      name,
      resolveId(id) { if (id === entry) return virtualEntry; },
      load(id) { if (id === virtualEntry) return source; },
    }],
    build: { write: false, rollupOptions: { input: entry, output: { entryFileNames: "entry.js" } } },
  });
  return new Map(bundle.output.map((file) => ["/" + file.fileName, file.code ?? file.source]));
}

export async function withArchiveBundle({ files, html, mount = "" }, check) {
  const accessed = [];
  const server = createServer((req, res) => {
    const pathname = new URL(req.url, "http://localhost").pathname;
    if (!pathname.startsWith(mount + "/")) return res.writeHead(404).end();
    const path = pathname.slice(mount.length);
    accessed.push(path);
    if (path === "/") return res.writeHead(200, { "Content-Type": "text/html" }).end(html);
    if (!files.has(path)) return res.writeHead(404).end();
    res.writeHead(200, { "Content-Type": path.endsWith(".json") ? "application/json" : "text/javascript" }).end(files.get(path));
  });
  let browser;
  try {
    await once(server.listen(0, "127.0.0.1"), "listening");
    const origin = "http://127.0.0.1:" + server.address().port;
    browser = await chromium.launch({ channel: process.env.CHROME_CHANNEL ?? "chrome", headless: true, chromiumSandbox: true });
    await check({ origin, browser, accessed });
  } finally {
    try {
      await browser?.close();
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  }
}
