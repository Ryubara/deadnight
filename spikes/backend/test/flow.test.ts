import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { buildApp } from "../src/app.ts";
import { api, connect, signIn } from "../src/client.ts";
import { loadConfig } from "../src/config.ts";
import { StubDiscord } from "../src/discord.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { startStubGameServer } from "../src/stub-gameserver.ts";
import { MemoryStore } from "../src/store.ts";
import { WebSocket } from "ws";
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
      body: JSON.stringify({ id: "gs-test", url: `ws://127.0.0.1:${gameServer.port}`, activityPath: "/gs/test", capacity: 3, matchIds: [] }),
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

  test("an Activity instance names no lobby: two players of one instance each make their own, a third joins one by code", async () => {
    const carol = await signIn(base, "stub:2001:carol");
    const dave = await signIn(base, "stub:2002:dave");
    const erin = await signIn(base, "stub:2004:erin");
    // A client from before #1178 still sends the instance id; it is ignored.
    const first = await api.createLobby(base, carol, { instanceId: "i-123" });
    const second = await api.createLobby(base, dave, { instanceId: "i-123" });
    assert.notEqual(second.id, first.id);
    assert.notEqual(second.code, first.code);
    assert.equal((await api.joinByCode(base, erin, first.code)).id, first.id);
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

  /** Opens a socket without sending anything, so a test decides what the first message is. */
  const open = (url: string): Promise<WebSocket> =>
    new Promise((resolve, reject) => {
      const socket = new WebSocket(url);
      socket.once("open", () => resolve(socket));
      socket.once("error", reject);
    });
  const nextMessage = (socket: WebSocket): Promise<Record<string, unknown>> =>
    new Promise((resolve, reject) => {
      socket.once("message", (data) => resolve(JSON.parse(data.toString()) as Record<string, unknown>));
      socket.once("close", (code, reason) => reject(new Error(`closed ${code} ${reason.toString()}`)));
    });
  const closed = (socket: WebSocket): Promise<{ code: number; reason: string }> =>
    new Promise((resolve) => socket.once("close", (code, reason) => resolve({ code, reason: reason.toString() })));

  describe("game-server tickets", () => {
    let players: Awaited<ReturnType<typeof signIn>>[];
    let lobbyId: string;

    before(async () => {
      players = [await signIn(base, "stub:6001:kim"), await signIn(base, "stub:6002:lou")];
      const lobby = await api.createLobby(base, players[0]!, { maxPlayers: 2 });
      await api.joinByCode(base, players[1]!, lobby.code);
      await api.start(base, players[0]!, lobby.id);
      lobbyId = lobby.id;
    });

    const claimsOf = (ticket: string) => JSON.parse(Buffer.from(ticket.split(".")[1]!, "base64url").toString("utf8"));
    const serverUrl = () => `ws://127.0.0.1:${gameServer.port}`;
    const newTicket = async (who: number) => (await api.ticket(base, players[who]!, lobbyId)).ticket;

    test("a ticket names its server and carries a unique id", async () => {
      const first = claimsOf(await newTicket(0));
      const second = claimsOf(await newTicket(0));
      assert.equal(first.serverId, "gs-test");
      assert.match(first.jti, /^[0-9a-f-]{36}$/);
      assert.notEqual(first.jti, second.jti);
    });

    test("a ticket works once: a second use of it is refused", async () => {
      const ticket = await newTicket(0);
      assert.equal((await connect(serverUrl(), ticket)).type, "welcome");
      await assert.rejects(connect(serverUrl(), ticket), /4401 ticket already used/);
    });

    test("another server refuses a ticket issued for this one, though it holds the same secret", async () => {
      const other = await startStubGameServer({
        id: "gs-other",
        port: 0,
        ticketSecret: config.ticketSecret,
        publicUrl: "ws://127.0.0.1:0",
        activityPath: "/gs/other",
      });
      try {
        const ticket = await newTicket(1);
        await assert.rejects(connect(`ws://127.0.0.1:${other.port}`, ticket), /4401 ticket is for another server/);
        // The refusal did not use the ticket up: the server it is for still takes it.
        assert.equal((await connect(serverUrl(), ticket)).serverId, "gs-test");
      } finally {
        await other.close();
      }
    });

    test("the ticket is read from the first message, not from the URL", async () => {
      const quiet = await startStubGameServer({
        id: "gs-quiet",
        port: 0,
        ticketSecret: config.ticketSecret,
        publicUrl: "ws://127.0.0.1:0",
        activityPath: "/gs/quiet",
        joinTimeoutMs: 150,
      });
      try {
        const url = `ws://127.0.0.1:${quiet.port}`;
        const extra = { matchId: "m1", serverId: "gs-quiet", jti: "j1", name: "x" };
        const ticket = signToken(config.ticketSecret, "ticket", "u1", 60, extra);
        const viaUrl = await open(`${url}/?ticket=${encodeURIComponent(ticket)}`);
        assert.deepEqual(await closed(viaUrl), { code: 4408, reason: "no ticket" });
        assert.equal((await connect(url, ticket)).type, "welcome"); // the URL never spent it
      } finally {
        await quiet.close();
      }
    });

    test("a first message that is not a join is refused", async () => {
      for (const first of ["not json", JSON.stringify({ type: "chat" }), JSON.stringify({ type: "join" }), "null"]) {
        const socket = await open(serverUrl());
        socket.send(first);
        assert.equal((await closed(socket)).code, 4401, first);
      }
    });

    test("a ticket with no server or no id is refused even when correctly signed", async () => {
      for (const extra of [{ jti: "j" }, { serverId: "gs-test" }, { serverId: 7, jti: "j" }]) {
        const ticket = signToken(config.ticketSecret, "ticket", "u1", 60, { matchId: "m1", ...extra });
        await assert.rejects(connect(serverUrl(), ticket), /4401/, JSON.stringify(extra));
      }
    });

    test("a newer connection for a seat replaces the older one", async () => {
      const older = await open(serverUrl());
      older.send(JSON.stringify({ type: "join", ticket: await newTicket(0) }));
      assert.equal((await nextMessage(older)).type, "welcome");
      const olderClosed = closed(older);

      const newer = await open(serverUrl());
      newer.send(JSON.stringify({ type: "join", ticket: await newTicket(0) }));
      assert.equal((await nextMessage(newer)).type, "welcome");
      assert.deepEqual(await olderClosed, { code: 4409, reason: "replaced by a newer connection" });
      assert.equal(newer.readyState, WebSocket.OPEN);
      newer.close();
    });
  });

  test("a start fails with 503 when no game server has capacity", async () => {
    // gs-test has capacity 3 and the earlier tests used two slots; use up the rest, then ask for one more.
    const results: number[] = [];
    for (let i = 0; i < 3; i++) {
      const host = await signIn(base, `stub:${4001 + i}:hana${i}`);
      const lobby = await api.createLobby(base, host, {});
      await api.start(base, host, lobby.id).then(
        () => results.push(200),
        (error: Error) => results.push(Number(/-> (\d+)/.exec(error.message)?.[1])),
      );
    }
    assert.deepEqual(results, [200, 503, 503]);
  });

  test("saves are per user, versioned and reject stale writes", async () => {
    const ivy = await signIn(base, "stub:5001:ivy");
    const put = (revision: number, data: object) =>
      fetch(`${base}/saves/main`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${ivy.token}` },
        body: JSON.stringify({ revision, schemaVersion: 1, data }),
      });
    assert.equal((await put(0, { night: 1 })).status, 200);
    assert.equal((await put(0, { night: 99 })).status, 409); // stale
    assert.equal((await put(1, { night: 2 })).status, 200);

    const read = await fetch(`${base}/saves/main`, { headers: { Authorization: `Bearer ${ivy.token}` } });
    assert.deepEqual(await read.json(), { revision: 2, schemaVersion: 1, data: { night: 2 } });

    const other = await signIn(base, "stub:5002:jon");
    const otherRead = await fetch(`${base}/saves/main`, { headers: { Authorization: `Bearer ${other.token}` } });
    assert.equal(otherRead.status, 404);
  });

  test("a heartbeat must announce a websocket url and an absolute path", async () => {
    const beat = (url: string, activityPath: string) =>
      fetch(`${base}/internal/servers/heartbeat`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${config.gameServerSecret}` },
        body: JSON.stringify({ id: "gs-evil", url, activityPath, capacity: 1, matchIds: [] }),
      });
    assert.equal((await beat("javascript:alert(1)", "/x")).status, 400);
    assert.equal((await beat("https://evil.example", "/x")).status, 400);
    assert.equal((await beat("ws://evil.example", "x")).status, 400);
    assert.equal((await beat("wss://good.example/gs", "/gs/1")).status, 204);
  });

  test("heartbeats need the game-server secret and health endpoints answer", async () => {
    const heartbeat = await fetch(`${base}/internal/servers/heartbeat`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer wrong" },
      body: JSON.stringify({ id: "x", url: "ws://x", activityPath: "/x", capacity: 1, matchIds: [] }),
    });
    assert.equal(heartbeat.status, 401);
    assert.equal((await fetch(`${base}/health`)).status, 200);
    assert.equal((await fetch(`${base}/ready`)).status, 200);
  });
});
