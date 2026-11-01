import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { buildApp } from "../src/app.ts";
import { api, connect, signIn } from "../src/client.ts";
import { loadConfig } from "../src/config.ts";
import { StubDiscord } from "../src/discord.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { startStubGameServer } from "../src/stub-gameserver.ts";
import { MemoryStore } from "../src/store.ts";
import { signToken } from "../src/tokens.ts";

const secrets = {
  SESSION_SECRET: "s".repeat(32),
  TICKET_SECRET: "t".repeat(32),
  GAME_SERVER_SECRET: "g".repeat(32),
};
const config = loadConfig({ ...secrets, DISCORD_MODE: "stub", ALLOW_STUB_SIGN_IN: "1" });

describe("platform backend, end to end", () => {
  const app = buildApp({ config, store: new MemoryStore(), discord: new StubDiscord(), registry: new GameServerRegistry() });
  let base = "";
  let gameServer: Awaited<ReturnType<typeof startStubGameServer>>;

  before(async () => {
    base = await app.listen({ host: "127.0.0.1", port: 0 });
    gameServer = await startStubGameServer({
      id: "gs-test",
      port: 0,
      ticketSecret: config.ticketSecret,
      publicUrl: "ws://127.0.0.1:0",
      activityPath: "/gs/test",
      backendUrl: base,
      gameServerSecret: config.gameServerSecret,
    });
    // The server announced port 0 as its URL; announce the real one.
    await fetch(`${base}/internal/servers/heartbeat`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${config.gameServerSecret}` },
      body: JSON.stringify({ id: "gs-test", url: `ws://127.0.0.1:${gameServer.port}`, activityPath: "/gs/test", capacity: 2, matches: 0 }),
    });
  });
  after(async () => {
    await gameServer.close();
    await app.close();
  });

  test("two players sign in, share a lobby and are handed a running game server", async () => {
    const alice = await signIn(base, "stub:1001:alice");
    const bob = await signIn(base, "stub:1002:bob");
    const lobby = await api.createLobby(base, alice, { maxPlayers: 2 });
    await api.joinByCode(base, bob, lobby.code.toLowerCase());
    await api.start(base, alice, lobby.id);

    for (const player of [alice, bob]) {
      const { address, ticket, matchId } = await api.ticket(base, player, lobby.id);
      assert.equal(address.activityPath, "/gs/test");
      const welcome = await connect(address.url, ticket);
      assert.deepEqual(
        { type: welcome.type, matchId: welcome.matchId, userId: welcome.userId, name: welcome.name },
        { type: "welcome", matchId, userId: player.userId, name: player.name },
      );
    }
  });

  test("an Activity instance maps to one open lobby", async () => {
    const carol = await signIn(base, "stub:2001:carol");
    const dave = await signIn(base, "stub:2002:dave");
    const first = await api.createLobby(base, carol, { instanceId: "i-123" });
    const second = await api.createLobby(base, dave, { instanceId: "i-123" });
    assert.equal(second.id, first.id);
  });

  test("rejects bad codes, missing sessions, full lobbies and non-hosts", async () => {
    const bad = await fetch(`${base}/auth/discord`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code: "nope" }) });
    assert.equal(bad.status, 401);
    assert.equal((await fetch(`${base}/lobbies`, { method: "POST" })).status, 401);

    const host = await signIn(base, "stub:3001:erin");
    const guest = await signIn(base, "stub:3002:frank");
    const late = await signIn(base, "stub:3003:gina");
    const lobby = await api.createLobby(base, host, { maxPlayers: 2 });
    await api.joinByCode(base, guest, lobby.code);
    await assert.rejects(api.joinByCode(base, late, lobby.code), /409/);
    await assert.rejects(api.start(base, guest, lobby.id), /403/);
    await assert.rejects(api.ticket(base, host, lobby.id), /409/); // not started yet
  });

  test("the game server refuses a forged or expired ticket", async () => {
    const forged = signToken("x".repeat(32), "ticket", "u1", 60, { matchId: "m1" });
    await assert.rejects(connect(`ws://127.0.0.1:${gameServer.port}`, forged), /4401/);
    const expired = signToken(config.ticketSecret, "ticket", "u1", 60, { matchId: "m1" }, 1_000);
    await assert.rejects(connect(`ws://127.0.0.1:${gameServer.port}`, expired), /4401/);
    const wrongKind = signToken(config.sessionSecret, "session", "u1", 60, { matchId: "m1" });
    await assert.rejects(connect(`ws://127.0.0.1:${gameServer.port}`, wrongKind), /4401/);
  });

  test("a start fails with 503 when no game server has capacity", async () => {
    // gs-test has capacity 2 and the first test used one slot; use up the rest, then ask for one more.
    const host = await signIn(base, "stub:4001:hana");
    const results: number[] = [];
    for (let i = 0; i < 3; i++) {
      const lobby = await api.createLobby(base, host, {});
      await api.start(base, host, lobby.id).then(
        () => results.push(200),
        (error: Error) => results.push(Number(/-> (\d+)/.exec(error.message)?.[1])),
      );
    }
    assert.ok(results.includes(503), `expected a 503 in ${results.join(",")}`);
  });

  test("saves are per user, versioned and reject stale writes", async () => {
    const ivy = await signIn(base, "stub:5001:ivy");
    const put = (revision: number, data: object) =>
      fetch(`${base}/saves/main`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${ivy.token}` },
        body: JSON.stringify({ revision, data }),
      });
    assert.equal((await put(0, { night: 1 })).status, 200);
    assert.equal((await put(0, { night: 99 })).status, 409); // stale
    assert.equal((await put(1, { night: 2 })).status, 200);

    const read = await fetch(`${base}/saves/main`, { headers: { Authorization: `Bearer ${ivy.token}` } });
    assert.deepEqual(await read.json(), { revision: 2, data: { night: 2 } });

    const other = await signIn(base, "stub:5002:jon");
    const otherRead = await fetch(`${base}/saves/main`, { headers: { Authorization: `Bearer ${other.token}` } });
    assert.equal(otherRead.status, 404);
  });

  test("heartbeats need the game-server secret and health endpoints answer", async () => {
    const heartbeat = await fetch(`${base}/internal/servers/heartbeat`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer wrong" },
      body: JSON.stringify({ id: "x", url: "ws://x", activityPath: "/x", capacity: 1, matches: 0 }),
    });
    assert.equal(heartbeat.status, 401);
    assert.equal((await fetch(`${base}/health`)).status, 200);
    assert.equal((await fetch(`${base}/ready`)).status, 200);
  });
});
