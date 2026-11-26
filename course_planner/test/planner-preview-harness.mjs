import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { build, preview } from "vite";

export const plannerRoot = fileURLToPath(new URL("../", import.meta.url));

export async function withPlannerPreview(
  prefix,
  { root = plannerRoot, headless, build: buildOptions, ...vite },
  check,
) {
  const tempRoot = resolve(tmpdir());
  const outDir = await mkdtemp(join(tempRoot, prefix));
  let server, browser;
  try {
    const config = {
      root,
      logLevel: "error",
      ...vite,
      build: { ...buildOptions, outDir, emptyOutDir: false },
    };
    await build(config);
    server = await preview({ ...config, preview: { host: "127.0.0.1", port: 0 } });
    const origin = "http://127.0.0.1:" + server.httpServer.address().port;
    browser = await chromium.launch({
      channel: process.env.CHROME_CHANNEL || "chrome", headless, chromiumSandbox: true,
    });
    await check({ origin, browser });
  } finally {
    try {
      await browser?.close();
    } finally {
      try {
        await server?.close();
      } finally {
        if (dirname(outDir) === tempRoot) await rm(outDir, { recursive: true, force: true });
      }
    }
  }
}
