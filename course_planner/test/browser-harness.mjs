import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { createServer } from "vite";

const root = fileURLToPath(new URL("../", import.meta.url));

export async function withBrowserHarness(
  { name, pagePath, entryPath, html, entry, viewport, optimizeDeps },
  check,
) {
  const server = await createServer({
    root,
    server: { host: "127.0.0.1", port: 0, strictPort: false, hmr: false },
    optimizeDeps,
    logLevel: "error",
    plugins: [{
      name,
      configureServer(vite) {
        vite.middlewares.use((req, res, next) => {
          if (req.url !== pagePath) return next();
          vite.transformIndexHtml(pagePath, html).then((transformed) => {
            res.statusCode = 200;
            res.setHeader("Content-Type", "text/html; charset=utf-8");
            res.end(transformed);
          }).catch(next);
        });
      },
      resolveId(id) {
        return id === entryPath ? id : null;
      },
      load(id) {
        return id === entryPath ? entry : null;
      },
    }],
  });
  let browser;
  try {
    await server.listen();
    const { port } = server.httpServer.address();
    const url = `http://127.0.0.1:${port}${pagePath}`;
    browser = await chromium.launch({
      channel: process.env.CHROME_CHANNEL ?? "chrome",
      headless: true,
      chromiumSandbox: true,
    });
    const context = await browser.newContext({ viewport });
    const page = await context.newPage();
    page.setDefaultTimeout(10000);
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await check({ page, url, errors });
  } finally {
    try {
      await browser?.close();
    } finally {
      await server.close();
    }
  }
}
