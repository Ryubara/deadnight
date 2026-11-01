// Fastify prints a deprecation when a removed-in-Fastify-6 option is used. This file builds its app first in its own
// process (node --test runs each file separately), so the once-per-process warning would show up here if it came back.
import assert from "node:assert/strict";
import { Writable } from "node:stream";
import { test } from "node:test";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { StubDiscord } from "../src/discord.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore } from "../src/store.ts";

test("the app builds without a deprecation warning, and health checks and heartbeats stay out of the request log", async () => {
  const warnings: string[] = [];
  process.on("warning", (warning) => warnings.push(`${warning.name} ${(warning as { code?: string }).code ?? ""}: ${warning.message}`));

  const lines: string[] = [];
  const stream = new Writable({
    write(chunk: Buffer, _encoding, done) {
      lines.push(...chunk.toString().split("\n").filter(Boolean));
      done();
    },
  });
  const config = loadConfig({
    SESSION_SECRET: "s".repeat(32),
    TICKET_SECRET: "t".repeat(32),
    GAME_SERVER_SECRET: "g".repeat(32),
    DISCORD_MODE: "stub",
    ALLOW_STUB_SIGN_IN: "1",
  });
  const app = buildApp({
    config,
    store: new MemoryStore(),
    discord: new StubDiscord(),
    registry: new GameServerRegistry(),
    logger: { level: "info", stream },
  });
  await app.ready();

  await app.inject({ method: "GET", url: "/health" });
  await app.inject({ method: "GET", url: "/ready" });
  await app.inject({
    method: "POST",
    url: "/internal/servers/heartbeat",
    headers: { authorization: `Bearer ${config.gameServerSecret}` },
    payload: { id: "gs", url: "ws://gs", activityPath: "/gs", capacity: 1, matchIds: [] },
  });
  await app.inject({ method: "POST", url: "/auth/discord", payload: { code: "stub:1:ann" } });
  await app.close();
  await new Promise((resolve) => setTimeout(resolve, 50)); // process warnings are emitted on a later tick

  assert.deepEqual(warnings, []);
  const incoming = lines
    .map((line) => JSON.parse(line) as { msg?: string; req?: { url?: string } })
    .filter((entry) => entry.msg === "incoming request")
    .map((entry) => entry.req?.url);
  assert.deepEqual(incoming, ["/ready", "/auth/discord"]);
});
