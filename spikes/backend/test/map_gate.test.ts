// The lobby host's level decides a hosted night's map (docs/design/maps.md#levels-open-maps, Deadnight #1098): the
// backend signs `hostLevel` into EVERY ticket of a match (a guest's carries the host's, not its own), refuses a map the
// host's level does not open as `bad_settings`, and holds its per-map levels equal to the game's own (`MapInfo`).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { OffDiscord } from "../src/discord.ts";
import { PROFILE_SLOT, freshProfile, levelOf } from "../src/progression.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { DEFAULT_MAP, MAP_UNLOCK_LEVELS, PLAYABLE_MAPS, checkSettings, mapOpenAt } from "../src/settings.ts";
import { MemoryStore } from "../src/store.ts";
import { verifyToken } from "../src/tokens.ts";

const config = loadConfig({
  SESSION_SECRET: "s".repeat(32),
  TICKET_SECRET: "t".repeat(32),
  GAME_SERVER_SECRET: "g".repeat(32),
  DISCORD_MODE: "off",
  GUEST_SIGN_IN: "1",
  NODE_ENV: "production",
});
const BACK_ROOMS = "small_indoor";
const RULES = { count_multiplier: 1, max_alive: 0, break_seconds: 0 };
/** Raw XP that reaches a level exactly (the curve is the game's: test/progression.test.ts holds the copy equal). */
const XP_FOR = { 1: 0, 3: 170, 9: 830, 10: 965, 12: 1_285 } as const;

async function platform() {
  const clock = { now: 5_000_000 };
  const registry = new GameServerRegistry(60 * 60_000, () => clock.now);
  const store = new MemoryStore();
  const app = buildApp({ config, store, discord: new OffDiscord(), registry, now: () => clock.now });
  const auth = { authorization: `Bearer ${config.gameServerSecret}` };
  await app.inject({
    method: "POST",
    url: "/internal/servers/heartbeat",
    headers: auth,
    payload: { id: "gs", url: "wss://gs.example", activityPath: "/gs", capacity: 4, matchIds: [], players: {} },
  });
  const call = (method: "GET" | "POST" | "PUT", url: string, headers: object, payload?: object) => app.inject({ method, url, headers, payload });
  /** A guest account whose stored profile holds the XP of `level`. */
  const player = async (name: string, level: keyof typeof XP_FOR = 1) => {
    const response = await app.inject({ method: "POST", url: "/auth/guest", payload: { name } });
    const user = response.json().user as { id: string };
    const who = { id: user.id, headers: { authorization: `Bearer ${response.json().token}` } };
    if (level !== 1) await giveXp(who.id, XP_FOR[level]);
    return who;
  };
  const giveXp = async (userId: string, xp: number) => {
    const saved = await store.getSave(userId, PROFILE_SLOT);
    await store.putSave(userId, PROFILE_SLOT, { schemaVersion: 1, data: { ...freshProfile(), xp } }, saved?.revision ?? 0);
  };
  type Who = Awaited<ReturnType<typeof player>>;
  const lobbyOf = async (host: Who, ...guests: Who[]) => {
    const lobby = (await call("POST", "/lobbies", host.headers, {})).json();
    for (const guest of guests) await call("POST", "/lobbies/join-by-code", guest.headers, { code: lobby.code });
    return lobby as { id: string; code: string };
  };
  const start = (lobbyId: string, host: Who, settings?: object) => call("POST", `/lobbies/${lobbyId}/start`, host.headers, settings ? { settings } : {});
  const claims = async (lobbyId: string, who: Who) => {
    const answer = await call("POST", `/lobbies/${lobbyId}/ticket`, who.headers, {});
    assert.equal(answer.statusCode, 200, answer.body);
    const verified = verifyToken(config.ticketSecret, "ticket", answer.json().ticket);
    assert.ok(verified);
    return verified as Record<string, unknown>;
  };
  const end = (matchId: string, present: string[]) => call("POST", `/internal/matches/${matchId}/end`, auth, { finished: true, present });
  return { app, call, player, giveXp, lobbyOf, start, claims, end, store };
}

test("every ticket of a match carries the host's level, a guest's own level changes nothing", async () => {
  const { app, player, lobbyOf, start, claims } = await platform();
  for (const [hostLevel, guestLevel] of [[3, 12], [12, 3]] as const) {
    const host = await player(`host${hostLevel}`, hostLevel);
    const guest = await player(`guest${guestLevel}`, guestLevel);
    const lobby = await lobbyOf(host, guest);
    assert.equal((await start(lobby.id, host)).statusCode, 200);
    // The guest asks first: the order the players arrive in decides nothing.
    const guestClaims = await claims(lobby.id, guest);
    const hostClaims = await claims(lobby.id, host);
    assert.equal(guestClaims.hostLevel, hostLevel, "the guest's ticket says the host's level");
    assert.equal(hostClaims.hostLevel, hostLevel);
    // The seat's own level stays its own (the ticket's `level` claim, for the badge in the night).
    assert.equal(guestClaims.level, guestLevel);
    assert.equal(hostClaims.level, hostLevel);
  }
  await app.close();
});

test("a host with no profile is level 1, and a night joined from the list signs the host's level too", async () => {
  const { app, player, lobbyOf, start, claims, call } = await platform();
  const fresh = await player("fresh");
  const lobby = await lobbyOf(fresh);
  await start(lobby.id, fresh);
  assert.equal((await claims(lobby.id, fresh)).hostLevel, 1);
  const veteran = await player("veteran", 12);
  const listed = (await call("GET", "/lobbies", veteran.headers)).json();
  assert.equal(listed.nights[0].code, lobby.code);
  const joined = (await call("POST", "/lobbies/join-by-code", veteran.headers, { code: listed.nights[0].code })).json();
  assert.equal(joined.id, lobby.id);
  assert.equal((await claims(lobby.id, veteran)).hostLevel, 1);
  await app.close();
});

test("the level is the host's when the match started: XP earned while it runs does not move it", async () => {
  const { app, player, lobbyOf, start, claims, giveXp } = await platform();
  const host = await player("host", 9);
  const lobby = await lobbyOf(host);
  await start(lobby.id, host);
  await giveXp(host.id, XP_FOR[10]); // the host reaches level 10 in the night itself
  assert.equal((await claims(lobby.id, host)).hostLevel, 9);
  assert.equal((await claims(lobby.id, host)).level, 10, "the seat's own badge follows the profile");
  await app.close();
});

test("the host passing on changes it for the next match", async () => {
  const { app, player, lobbyOf, start, claims, end, call } = await platform();
  const alice = await player("alice", 12);
  const bob = await player("bob", 3);
  const lobby = await lobbyOf(alice, bob);
  const first = (await start(lobby.id, alice)).json() as { matchId: string };
  assert.equal((await claims(lobby.id, bob)).hostLevel, 12);
  // The night ends and the lobby opens again; alice leaves, the host role passes to bob, who starts the next night.
  assert.equal((await end(first.matchId, [alice.id, bob.id])).statusCode, 204);
  assert.equal((await call("POST", `/lobbies/${lobby.id}/leave`, alice.headers, {})).statusCode, 204);
  const members = (await call("GET", `/lobbies/${lobby.id}`, bob.headers)).json().members as { userId: string; host: boolean }[];
  assert.deepEqual(members.filter((m) => m.host).map((m) => m.userId), [bob.id]);
  assert.equal((await start(lobby.id, bob)).statusCode, 200);
  assert.equal((await claims(lobby.id, bob)).hostLevel, 3);
  await app.close();
});

test("a host below level 10 setting the back rooms is refused as bad_settings, at the settings and at the start", async () => {
  const { app, player, lobbyOf, start, call } = await platform();
  const host = await player("host", 9);
  const lobby = await lobbyOf(host);
  const set = await call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, { ...RULES, map: BACK_ROOMS });
  assert.equal(set.statusCode, 400);
  assert.equal(set.json().error, "bad_settings");
  assert.match(JSON.stringify(set.json()), /level 10/);
  const started = await start(lobby.id, host, { ...RULES, map: BACK_ROOMS });
  assert.equal(started.statusCode, 400);
  assert.equal(started.json().error, "bad_settings");
  // Nothing was kept or started: the lobby is open on the usual rules, and the lot is allowed.
  const view = (await call("GET", `/lobbies/${lobby.id}`, host.headers)).json();
  assert.equal(view.state, "open");
  assert.equal(view.settings, null);
  assert.equal((await call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, { ...RULES, map: DEFAULT_MAP })).statusCode, 200);
  // The same host at level 10 is taken.
  const veteran = await player("veteran", 10);
  const second = await lobbyOf(veteran);
  const ok = await call("PUT", `/lobbies/${second.id}/settings`, veteran.headers, { ...RULES, map: BACK_ROOMS });
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.json().map, BACK_ROOMS);
  await app.close();
});

test("rules kept from a host who left start on the lot when the new host's level does not open their map", async () => {
  const { app, player, lobbyOf, start, claims, call } = await platform();
  const alice = await player("alice", 12);
  const bob = await player("bob", 3);
  const lobby = await lobbyOf(alice, bob);
  await call("PUT", `/lobbies/${lobby.id}/settings`, alice.headers, { ...RULES, count_multiplier: 2, map: BACK_ROOMS });
  assert.equal((await call("POST", `/lobbies/${lobby.id}/leave`, alice.headers, {})).statusCode, 204);
  const started = await start(lobby.id, bob);
  assert.equal(started.statusCode, 200, started.body);
  assert.equal(started.json().map, DEFAULT_MAP, "the lobby view shows the map the night is on");
  const ticket = await claims(lobby.id, bob);
  assert.equal(ticket.hostLevel, 3);
  assert.deepEqual(ticket.settings, { ...RULES, count_multiplier: 2, map: DEFAULT_MAP }, "the other rules stand");
  await app.close();
});

test("checkSettings opens a map by the level it is given, and not at all without one", () => {
  assert.equal(PLAYABLE_MAPS.length, Object.keys(MAP_UNLOCK_LEVELS).length);
  assert.deepEqual(checkSettings({ ...RULES, map: BACK_ROOMS }, 9), { problem: "map needs level 10" });
  assert.deepEqual(checkSettings({ ...RULES, map: BACK_ROOMS }, 10), { settings: { ...RULES, map: BACK_ROOMS } });
  assert.ok("settings" in checkSettings({ ...RULES, map: DEFAULT_MAP }, 1));
  assert.ok("settings" in checkSettings(RULES, 1)); // no map: the default one
  assert.deepEqual(checkSettings({ ...RULES, map: "nope" }, 55), { problem: "bad map" }); // an unknown id is still bad_map
  assert.ok("settings" in checkSettings({ ...RULES, map: BACK_ROOMS })); // the level is the caller's to give
  assert.equal(mapOpenAt("nope", 55), false);
  assert.equal(levelOf(XP_FOR[3]), 3);
  assert.equal(levelOf(XP_FOR[9]), 9);
  assert.equal(levelOf(XP_FOR[10]), 10);
  assert.equal(levelOf(XP_FOR[12]), 12);
  assert.equal(levelOf(XP_FOR[10] - 1), 9);
});

// ---- the game's own numbers

test("the per-map levels and the map ids are the game's own (read from MapInfo and the registry)", () => {
  const read = (path: string) => readFileSync(new URL(`../../../game/world/maps/${path}`, import.meta.url), "utf8");
  const registry = read("map_registry.gd");
  const paths = [...registry.matchAll(/"res:\/\/world\/maps\/([a-z_]+\.tres)"/g)].map((m) => m[1]!);
  assert.ok(paths.length >= 2, "the registry lists its maps");
  const defaultLevel = Number(/@export var unlock_level := (\d+)/.exec(read("map_info.gd"))![1]);
  const levels: Record<string, number> = {};
  for (const path of paths) {
    const text = read(path);
    const shipped = !/^shipped = false$/m.test(text); // MapInfo.shipped defaults to true
    if (!shipped) continue;
    const id = /^id = "([a-z_]+)"$/m.exec(text)![1]!;
    levels[id] = Number(/^unlock_level = (\d+)$/m.exec(text)?.[1] ?? defaultLevel);
  }
  assert.deepEqual(levels, { ...MAP_UNLOCK_LEVELS });
  assert.deepEqual(Object.keys(levels), [...PLAYABLE_MAPS], "the order is the picker's too");
  assert.equal(/const DEFAULT := "([a-z_]+)"/.exec(registry)![1], DEFAULT_MAP);
});
