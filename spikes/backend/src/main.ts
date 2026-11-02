// Process entry: configuration from the environment, structured logs, health, graceful shutdown.
import { buildApp } from "./app.ts";
import { loadConfig } from "./config.ts";
import { LiveDiscord, OffDiscord, StubDiscord } from "./discord.ts";
import { PgStore } from "./pg-store.ts";
import { GameServerRegistry } from "./servers.ts";
import { MemoryStore } from "./store.ts";

const config = loadConfig();
const store = config.databaseUrl ? await PgStore.connect(config.databaseUrl) : new MemoryStore();
const discord =
  config.discordMode === "live"
    ? new LiveDiscord(config.discordClientId, config.discordClientSecret)
    : config.discordMode === "off"
      ? new OffDiscord()
      : new StubDiscord();

const app = buildApp({
  config,
  store,
  discord,
  registry: new GameServerRegistry(),
  logger: {
    level: config.logLevel,
    redact: ["req.headers.authorization", "req.body.code", "res.body.token", "res.body.access_token"],
  },
});

let stopping = false;
async function shutdown(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  app.log.info({ signal }, "shutting down");
  await app.close(); // stops accepting, lets in-flight requests finish
  await store.close();
  process.exit(0);
}
process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));

await app.listen({ host: config.host, port: config.port });
