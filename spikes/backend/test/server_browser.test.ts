// The Server Browser's data and the people cap (Deadnight #1179): the list of public nights, a night private by its host's
// word, a count of people with bots left out, and a night that ended or emptied gone from the next call. The screen is #1180.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { OffDiscord } from "../src/discord.ts";
import { MAX_PLAYERS } from "../src/lobbies.ts";
import { LIST_LIMIT, LIST_PER_WINDOW, LIST_WINDOW_MS } from "../src/lobby_list.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore } from "../src/store.ts";

const env = {
  SESSION_SECRET: "s".repeat(32),
  TICKET_SECRET: "t".repeat(32),
  GAME_SERVER_SECRET: "g".repeat(32),
  DISCORD_MODE: "off",
  GUEST_SIGN_IN: "1",
  NODE_ENV: "production",
};

type Who = { headers: object; user: { id: string; name: string } };
type Row = Record<string, unknown> & { code: string; players: number; full: boolean };

async function platform(capacity = 40) {
  const clock = { now: 5_000_000 };
  const registry = new GameServerRegistry(60 * 60_000, () => clock.now);
  const config = loadConfig(env);
  const app = buildApp({ config, store: new MemoryStore(), discord: new OffDiscord(), registry, now: () => clock.now });
  const auth = { authorization: `Bearer ${config.gameServerSecret}` };
  const beat = (matchIds: string[] = [], extra: { players?: Record<string, number>; rounds?: Record<string, number> } = {}) =>
    app.inject({
      method: "POST",
      url: "/internal/servers/heartbeat",
      headers: auth,
      payload: { id: "gs", url: "wss://gs.example", activityPath: "/gs", capacity, matchIds, ...extra },
    });
  await beat();
  let guests = 0;
  const guest = async (name: string): Promise<Who> => {
    const n = ++guests;
    const response = await app.inject({ method: "POST", url: "/auth/guest", payload: { name }, remoteAddress: `10.${n >> 8}.0.${n & 255}` });
    return { headers: { authorization: `Bearer ${response.json().token}` }, user: response.json().user };
  };
  const call = (method: "GET" | "POST" | "PUT", url: string, who: { headers: object }, payload?: object) =>
    app.inject({ method, url, headers: who.headers, payload });
  /** The list as `who` reads it. */
  const list = async (who: Who) => {
    const response = await call("GET", "/lobbies", who);
    assert.equal(response.statusCode, 200);
    return response.json() as { maxPlayers: number; total: number; nights: Row[] };
  };
  const endMatch = (matchId: string, body?: object) =>
    app.inject({ method: "POST", url: `/internal/matches/${matchId}/end`, headers: auth, payload: body });
  return { app, clock, beat, guest, call, list, endMatch };
}

const RULES = { count_multiplier: 1, max_alive: 0, break_seconds: 0 };

test("a new night is public and a row says its map, its people out of the cap, its bots, and waiting or the round", async () => {
  const { app, guest, call, list, beat } = await platform();
  const [ann, bo, looker] = [await guest("Ann"), await guest("Bo"), await guest("Looker")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  assert.equal(made.visibility, "public");
  await call("PUT", `/lobbies/${made.id}/settings`, ann, { ...RULES, bots: 3 });
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });

  const waiting = await list(looker);
  assert.equal(waiting.maxPlayers, MAX_PLAYERS);
  assert.equal(waiting.nights.length, 1);
  assert.deepEqual(waiting.nights[0], {
    id: made.id,
    code: made.code,
    map: "drive_in",
    hostName: "Ann",
    players: 2,
    maxPlayers: 8,
    bots: 3,
    kind: "lobby",
    state: "open",
    round: null,
    full: false,
  });

  // In progress it is listed too (players join mid-night), with the round and the game server's count of people.
  const started = (await call("POST", `/lobbies/${made.id}/start`, ann)).json();
  await beat([started.matchId], { players: { [started.matchId]: 2 }, rounds: { [started.matchId]: 4 } });
  const playing = (await list(looker)).nights[0]!;
  assert.deepEqual(
    { kind: playing.kind, state: playing.state, round: playing.round, players: playing.players, bots: playing.bots },
    { kind: "match", state: "started", round: 4, players: 2, bots: 3 },
  );
  await app.close();
});

test("a private night is not listed, its code still joins it, and public lists it again; only its host decides", async () => {
  const { app, guest, call, list } = await platform();
  const [ann, bo, looker] = [await guest("Ann"), await guest("Bo"), await guest("Looker")];
  const secret = (await call("POST", "/lobbies", ann, { visibility: "private" })).json();
  assert.equal(secret.visibility, "private");
  assert.deepEqual((await list(looker)).nights, []);
  // The code is all a friend needs.
  assert.equal((await call("POST", "/lobbies/join-by-code", bo, { code: secret.code })).statusCode, 200);

  // Only the host moves it, and only to a value the backend knows.
  assert.equal((await call("PUT", `/lobbies/${secret.id}/visibility`, bo, { visibility: "public" })).statusCode, 403);
  assert.equal((await call("PUT", `/lobbies/${secret.id}/visibility`, ann, { visibility: "hidden" })).statusCode, 400);
  assert.equal((await call("PUT", `/lobbies/${secret.id}/visibility`, ann, {})).statusCode, 400);
  assert.equal((await call("PUT", `/lobbies/${secret.id}/visibility`, { headers: {} }, { visibility: "public" })).statusCode, 401);
  const opened = await call("PUT", `/lobbies/${secret.id}/visibility`, ann, { visibility: "public" });
  assert.equal(opened.json().visibility, "public");
  assert.deepEqual((await list(looker)).nights.map((n) => n.code), [secret.code]);

  // Private again, even with the night in progress.
  await call("POST", `/lobbies/${secret.id}/start`, ann);
  assert.equal((await call("PUT", `/lobbies/${secret.id}/visibility`, ann, { visibility: "private" })).json().visibility, "private");
  assert.deepEqual((await list(looker)).nights, []);
  await app.close();
});

test("8 people join a night with 7 bots set: the count is people, the night is full on people alone", async () => {
  const { app, guest, call, list, beat } = await platform();
  const people = await Promise.all(Array.from({ length: MAX_PLAYERS + 1 }, (_, i) => guest(`P${i}`)));
  const [host, ...rest] = people as [Who, ...Who[]];
  const made = (await call("POST", "/lobbies", host, {})).json();
  assert.equal((await call("PUT", `/lobbies/${made.id}/settings`, host, { ...RULES, bots: 7 })).statusCode, 200);
  // Seven more people take the seven other seats; bots take none (they are not in the lobby at all).
  for (const person of rest.slice(0, MAX_PLAYERS - 1)) {
    assert.equal((await call("POST", "/lobbies/join-by-code", person, { code: made.code })).statusCode, 200);
  }
  const waiting = (await list(host)).nights[0]!;
  assert.deepEqual({ players: waiting.players, bots: waiting.bots, full: waiting.full }, { players: 8, bots: 7, full: true });
  // The ninth person is refused: the cap is 8 people.
  const ninth = rest[MAX_PLAYERS - 1]!;
  assert.equal((await call("POST", "/lobbies/join-by-code", ninth, { code: made.code })).statusCode, 409);

  // Started, the game server counts people (the bots it runs are not in the count it sends).
  const started = (await call("POST", `/lobbies/${made.id}/start`, host)).json();
  await beat([started.matchId], { players: { [started.matchId]: 7 }, rounds: { [started.matchId]: 2 } });
  const room = (await list(host)).nights[0]!;
  assert.deepEqual({ players: room.players, full: room.full, bots: room.bots }, { players: 7, full: false, bots: 7 });
  assert.equal((await call("POST", "/lobbies/join-by-code", ninth, { code: made.code })).statusCode, 200);
  await beat([started.matchId], { players: { [started.matchId]: 8 } });
  assert.equal((await list(host)).nights[0]!.full, true);
  await app.close();
});

test("a night that ended, emptied or ran out is gone from the very next call", async () => {
  const { app, guest, call, list, beat, endMatch, clock } = await platform();
  const [a, b, c, d, looker] = [await guest("A"), await guest("B"), await guest("C"), await guest("D"), await guest("Looker")];
  const ended = (await call("POST", "/lobbies", a, {})).json();
  const emptied = (await call("POST", "/lobbies", b, {})).json();
  const idle = (await call("POST", "/lobbies", c, {})).json();
  const playing = (await call("POST", "/lobbies", d, {})).json();
  const startedEnded = (await call("POST", `/lobbies/${ended.id}/start`, a)).json();
  await call("POST", `/lobbies/${playing.id}/start`, d);
  await beat([startedEnded.matchId]);
  assert.equal((await list(looker)).total, 4);

  // The game server says the match is over.
  await endMatch(startedEnded.matchId);
  assert.deepEqual((await list(looker)).nights.map((n) => n.code).sort(), [emptied.code, idle.code, playing.code].sort());
  // The last person leaves a waiting night.
  await call("POST", `/lobbies/${emptied.id}/leave`, b);
  assert.deepEqual((await list(looker)).nights.map((n) => n.code).sort(), [idle.code, playing.code].sort());
  // A waiting night nobody touched for ten minutes is dropped by the list itself, with no sweep in between.
  clock.now += 10 * 60_000 + 1;
  await call("GET", `/lobbies/${playing.id}`, d); // its host is still there
  assert.deepEqual((await list(looker)).nights.map((n) => n.code), [playing.code]);
  await app.close();
});

test("a member who stopped polling is not counted in the people of a waiting night", async () => {
  const { app, guest, call, list, clock } = await platform();
  const [ann, bo, looker] = [await guest("Ann"), await guest("Bo"), await guest("Looker")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });
  assert.equal((await list(looker)).nights[0]!.players, 2);
  clock.now += 61_000;
  await call("GET", `/lobbies/${made.id}`, ann); // Ann is still on her screen, Bo closed his tab
  assert.equal((await list(looker)).nights[0]!.players, 1);
  await app.close();
});

test("rows are ordered with room first, then the most people, and a page is capped", async () => {
  const { app, guest, call, list } = await platform();
  const [h1, h2, h3, extra, looker] = [await guest("H1"), await guest("H2"), await guest("H3"), await guest("X"), await guest("Looker")];
  const small = (await call("POST", "/lobbies", h1, {})).json();
  const busy = (await call("POST", "/lobbies", h2, {})).json();
  const full = (await call("POST", "/lobbies", h3, { maxPlayers: 1 })).json();
  await call("POST", "/lobbies/join-by-code", extra, { code: busy.code });
  const ordered = await list(looker);
  assert.deepEqual(ordered.nights.map((n) => n.code), [busy.code, small.code, full.code]);
  assert.deepEqual(ordered.nights.map((n) => n.full), [false, false, true]);

  // 80 more nights: the answer carries the first LIST_LIMIT and says how many there are.
  for (let i = 0; i < 80; i++) await call("POST", "/lobbies", await guest(`M${i}`), {});
  const page = await list(looker);
  assert.equal(page.nights.length, LIST_LIMIT);
  assert.equal(page.total, 83);
  assert.equal(page.nights[0]!.code, busy.code);
  assert.equal(page.nights.some((n) => n.code === full.code), false);
  await app.close();
});

test("the list is for signed-in players and is limited per account, and the limit passes with the window", async () => {
  const { app, guest, call, clock } = await platform();
  const [ann, bo] = [await guest("Ann"), await guest("Bo")];
  assert.equal((await call("GET", "/lobbies", { headers: {} })).statusCode, 401);
  for (let i = 0; i < LIST_PER_WINDOW; i++) assert.equal((await call("GET", "/lobbies", ann)).statusCode, 200);
  const refused = await call("GET", "/lobbies", ann);
  assert.equal(refused.statusCode, 429);
  assert.equal(refused.json().error, "too_many_requests");
  assert.equal(refused.headers["retry-after"], String(LIST_WINDOW_MS / 1000));
  assert.equal((await call("GET", "/lobbies", bo)).statusCode, 200); // another account is not held up
  clock.now += LIST_WINDOW_MS + 1;
  assert.equal((await call("GET", "/lobbies", ann)).statusCode, 200);
  await app.close();
});
