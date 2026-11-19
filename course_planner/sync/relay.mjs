import { createServer } from "node:http";
import { randomUUID, timingSafeEqual } from "node:crypto";
import { mkdir, writeFile, readFile, readdir, link, rmdir, unlink } from "node:fs/promises";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";
import { bearerAccount, maxEnvelope, newPairingCode, pairingKey, relayIdentity, validEnvelope } from "../src/sync/crypto.mjs";
import { uuid } from "../src/sync/model.mjs";

export async function provision(directory, saveRecovery) {
  // Exclusive creation prevents re-keying a running account by mistake.
  await mkdir(directory, { mode: 0o700 });
  const code = newPairingCode();
  const { account } = await relayIdentity(await pairingKey(code));
  try { if (saveRecovery) await saveRecovery(code); }
  catch (e) { await rmdir(directory); throw e; }
  for (const stream of ["plan", "history"]) await mkdir(join(directory, stream), { mode: 0o700 });
  await writeFile(join(directory, "account.json"), JSON.stringify({ account }), { flag: "wx", mode: 0o600 });
  return code;
}
async function body(req) {
  const chunks = [];
  let size = 0;
  for await (const part of req) {
    size += part.length;
    if (size > maxEnvelope) throw Object.assign(Error(), { status: 413 });
    chunks.push(part);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (validEnvelope(value)) return JSON.stringify(value);
  } catch {}
  throw Object.assign(Error(), { status: 400 });
}
async function append(directory, id, data) {
  const temp = join(directory, "." + randomUUID());
  await writeFile(temp, data, { flag: "wx", mode: 0o600 });
  try {
    // Publish only complete files. A retry of the same immutable batch is safe.
    await link(temp, join(directory, id));
  } catch (e) { if (e.code !== "EEXIST") throw e; }
  finally { await unlink(temp); }
}
export async function createRelay(directory, origins) {
  const { account } = JSON.parse(await readFile(join(directory, "account.json"), "utf8"));
  if (!/^[A-Za-z0-9_-]{43}$/.test(account)) throw Error("Invalid account verifier.");
  if (!origins.length || origins.some((s) => new URL(s).origin !== s ||
      !["https:", "http:"].includes(new URL(s).protocol))) throw Error("Specify exact planner origin(s).");
  return createServer(async (req, res) => {
    const reply = (status, data) => res.writeHead(status).end(data);
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Content-Type", "application/json");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Vary", "Origin");
    const origin = req.headers.origin;
    if (origin && !origins.includes(origin)) return reply(403);
    if (origin) res.setHeader("Access-Control-Allow-Origin", origin);
    if (req.method === "OPTIONS") {
      res.setHeader("Access-Control-Allow-Methods", "GET, PUT");
      res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
      return reply(204);
    }
    try {
      const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.authorization ?? "");
      if (!match || !timingSafeEqual(Buffer.from(await bearerAccount(match[1])), Buffer.from(account))) return reply(401);
      if (req.method === "GET" && req.url === "/v1/account") return reply(200, JSON.stringify({ v: 1, account }));
      const path = /^\/v1\/(plan|history)(?:\/([a-f0-9-]+))?$/.exec(req.url);
      if (!path || (path[2] && !uuid(path[2]))) return reply(404);
      const dir = join(directory, path[1]), id = path[2];
      if (req.method === "GET") {
        if (!id) return reply(200, JSON.stringify((await readdir(dir)).filter(uuid).sort()));
        return reply(200, await readFile(join(dir, id)));
      }
      if (req.method === "PUT" && id) {
        if (req.headers["content-type"] !== "application/json") return reply(415);
        await append(dir, id, await body(req));
        return reply(204);
      }
      return reply(405);
    } catch (e) { return reply(e.code === "ENOENT" ? 404 : (e.status ?? 500)); }
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [command, path, ...origins] = process.argv.slice(2);
  if (command === "init" && path && origins.length === 1) {
    const recoveryPath = origins[0];
    const rel = relative(resolve(path), resolve(recoveryPath));
    if (!isAbsolute(rel) && !rel.startsWith(".." + sep)) throw Error("Keep the recovery file outside the relay data directory.");
    await provision(path, (code) => writeFile(recoveryPath, code + "\n", { flag: "wx", mode: 0o600 }));
    console.log("Pairing code saved to the separate recovery file. Only the verifier belongs on the relay.");
  } else if (command === "serve" && path && origins.length) {
    const server = await createRelay(path, origins);
    const port = Number(process.env.PLANNER_RELAY_PORT || "8788");
    server.listen(port, "127.0.0.1", () => console.log("Planner relay listening on loopback port " + server.address().port));
  } else {
    console.error("Usage: node relay.mjs init NEW_PRIVATE_DIRECTORY NEW_RECOVERY_FILE | serve PRIVATE_DIRECTORY PLANNER_ORIGIN [PLANNER_ORIGIN...]");
    process.exitCode = 2;
  }
}
