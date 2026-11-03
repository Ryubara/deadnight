// Rooms for friends on the web: guest sign-in, a night in progress that takes newcomers, quick join, and the
// Activity instance that lands everyone in one night.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp, GUEST_ID_PREFIX, GUESTS_PER_ADDRESS_PER_HOUR, guestName } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { OffDiscord } from "../src/discord.ts";
import { MAX_PLAYERS } from "../src/lobbies.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore } from "../src/store.ts";
import { verifyToken } from "../src/tokens.ts";

const env = {
  SESSION_SECRET: "s".repeat(32),
  TICKET_SECRET: "t".repeat(32),
  GAME_SERVER_SECRET: "g".repeat(32),
  DISCORD_MODE: "off",
  GUEST_SIGN_IN: "1",
  NODE_ENV: "production",
};

async function platform(extra: Record<string, string> = {}, capacity = 3) {
  const clock = { now: 5_000_000 };
  const registry = new GameServerRegistry(60 * 60_000, () => clock.now);
  const config = loadConfig({ ...env, ...extra });
  const store = new MemoryStore();
  const app = buildApp({ config, store, discord: new OffDiscord(), registry, now: () => clock.now });
  const auth = { authorization: `Bearer ${config.gameServerSecret}` };
  const beat = (matchIds: string[] = [], players: Record<string, number> = {}) =>
    app.inject({
      method: "POST",
      url: "/internal/servers/heartbeat",
      headers: auth,
      payload: { id: "gs", url: "wss://gs.example", activityPath: "/gs", capacity, matchIds, players },
    });
  await beat();
  const guest = async (name = "", ip = "10.0.0.1") => {
    const response = await app.inject({ method: "POST", url: "/auth/guest", payload: { name }, remoteAddress: ip });
    return { response, headers: { authorization: `Bearer ${response.json().token}` }, user: response.json().user };
  };
  const call = async (method: "GET" | "POST" | "PUT", url: string, headers: object, payload?: object) =>
    app.inject({ method, url, headers, payload });
  return { app, clock, registry, config, store, beat, guest, call, auth };
}

test("a guest signs in with no Discord and gets a user in its own namespace", async () => {
  const { app, guest, store } = await platform();
  const { response, user } = await guest("Ann");
  assert.equal(response.statusCode, 201);
  assert.equal(user.name, "Ann");
  assert.equal(user.guest, true);
  assert.equal((await store.getUser(user.id))?.discordId.startsWith(GUEST_ID_PREFIX), true);
  // Two guests are two users, even with the same name.
  const other = await guest("Ann");
  assert.notEqual(other.user.id, user.id);
  // A backend with Discord off does not take a Discord code, and a guest cannot be made by one.
  const discord = await app.inject({ method: "POST", url: "/auth/discord", payload: { code: "stub:1:x" } });
  assert.equal(discord.statusCode, 502);
  await app.close();
});

test("guest sign-in is off unless it is switched on, and names are cleaned", async () => {
  const { app, guest } = await platform({ DISCORD_MODE: "stub", ALLOW_STUB_SIGN_IN: "1", NODE_ENV: "test", GUEST_SIGN_IN: "0" });
  assert.equal((await guest("x")).response.statusCode, 404);
  await app.close();
  assert.equal(guestName("  <b>Ann</b> & co  "), "bAnnb co");
  assert.match(guestName(""), /^Guest [0-9]{4}$/);
  assert.equal(guestName("x".repeat(80)).length, 24);
  assert.equal(guestName("Zoë-3"), "Zoë-3");
  assert.throws(() => loadConfig({ ...env, GUEST_SIGN_IN: "0" }), /GUEST_SIGN_IN/);
});

test("one address cannot make guests without end, and the limit comes back with the hour", async () => {
  const { app, guest, clock } = await platform();
  for (let i = 0; i < GUESTS_PER_ADDRESS_PER_HOUR; i++) assert.equal((await guest("a", "10.1.1.1")).response.statusCode, 201);
  assert.equal((await guest("a", "10.1.1.1")).response.statusCode, 429);
  assert.equal((await guest("a", "10.2.2.2")).response.statusCode, 201); // another address is not held up
  clock.now += 61 * 60_000;
  assert.equal((await guest("a", "10.1.1.1")).response.statusCode, 201);
  await app.close();
});

test("a friend with the code joins a night that has started, and a full night turns the next one away", async () => {
  const { app, guest, call, beat } = await platform();
  const host = await guest("host");
  const lobby = (await call("POST", "/lobbies", host.headers, { maxPlayers: 2 })).json();
  const started = (await call("POST", `/lobbies/${lobby.id}/start`, host.headers, {})).json();
  assert.equal(started.state, "started");

  const friend = await guest("friend");
  const joined = await call("POST", "/lobbies/join-by-code", friend.headers, { code: lobby.code.toLowerCase() });
  assert.equal(joined.statusCode, 200);
  const ticket = await call("POST", `/lobbies/${lobby.id}/ticket`, friend.headers);
  assert.equal(ticket.statusCode, 200);
  assert.equal(ticket.json().address.url, "wss://gs.example");

  // The game server says two are in: the third is told it is full, not given a ticket for nothing.
  await beat([started.matchId], { [started.matchId]: 2 });
  const third = await guest("third");
  assert.equal((await call("POST", "/lobbies/join-by-code", third.headers, { code: lobby.code })).statusCode, 409);
  // One leaves: the server's count drops and there is room again.
  await beat([started.matchId], { [started.matchId]: 1 });
  assert.equal((await call("POST", "/lobbies/join-by-code", third.headers, { code: lobby.code })).statusCode, 200);
  await app.close();
});

test("quick join puts strangers in one public night, then starts another when it is full", async () => {
  const { app, guest, call, beat } = await platform({}, 3);
  const [a, b, c, d, e] = [await guest("a"), await guest("b"), await guest("c"), await guest("d"), await guest("e")];
  const first = (await call("POST", "/lobbies/quick", a.headers)).json();
  assert.equal(first.state, "started");
  assert.equal(first.visibility, "public");
  const second = (await call("POST", "/lobbies/quick", b.headers)).json();
  assert.equal(second.id, first.id);
  assert.equal((await call("POST", `/lobbies/${first.id}/ticket`, b.headers)).statusCode, 200);
  // The same player asking again gets the same night.
  assert.equal((await call("POST", "/lobbies/quick", a.headers)).json().id, first.id);

  await beat([first.matchId], { [first.matchId]: MAX_PLAYERS });
  const next = (await call("POST", "/lobbies/quick", c.headers)).json();
  assert.notEqual(next.id, first.id); // the first is full: a new night
  assert.equal((await call("POST", "/lobbies/quick", d.headers)).json().id, next.id);

  // A private night is never handed to a stranger.
  const mine = (await call("POST", "/lobbies", e.headers, {})).json();
  await call("POST", `/lobbies/${mine.id}/start`, e.headers);
  const stranger = await guest("stranger");
  const picked = (await call("POST", "/lobbies/quick", stranger.headers)).json();
  assert.notEqual(picked.id, mine.id);
  await app.close();
});

test("quick join with no game server up is a 503, not a lobby left behind", async () => {
  const { app, guest, call, registry } = await platform({}, 0);
  const a = await guest("a");
  assert.equal((await call("POST", "/lobbies/quick", a.headers)).statusCode, 503);
  // And the player is free to try again once a server has room.
  assert.equal(registry.alive().length, 1);
  await app.close();
});

test("everyone who opens the Activity in one voice channel lands in the same night, started or not", async () => {
  const { app, guest, call } = await platform();
  const [a, b, c] = [await guest("a"), await guest("b"), await guest("c")];
  const first = (await call("POST", "/lobbies", a.headers, { instanceId: "voice-42" })).json();
  assert.equal((await call("POST", `/lobbies/${first.id}/start`, a.headers)).statusCode, 200);
  // The Activity of the second opens after the night began.
  const second = await call("POST", "/lobbies", b.headers, { instanceId: "voice-42" });
  assert.equal(second.statusCode, 200);
  assert.equal(second.json().id, first.id);
  assert.equal((await call("POST", `/lobbies/${first.id}/ticket`, b.headers)).statusCode, 200);
  assert.equal((await call("POST", "/lobbies", c.headers, { instanceId: "voice-42" })).json().id, first.id);
  // Another channel is another night.
  const other = (await call("POST", "/lobbies", c.headers, { instanceId: "voice-43" })).json();
  assert.notEqual(other.id, first.id);
  await app.close();
});

test("only the pages named in CORS_ORIGINS may call the API from a browser", async () => {
  const { app } = await platform({ CORS_ORIGINS: "https://play.example, http://127.0.0.1:8080" });
  const ask = (origin: string, method: "OPTIONS" | "POST" = "OPTIONS") =>
    app.inject({ method, url: "/auth/guest", headers: { origin, "access-control-request-method": "POST" }, payload: method === "POST" ? {} : undefined });
  const allowed = await ask("https://play.example");
  assert.equal(allowed.statusCode, 204);
  assert.equal(allowed.headers["access-control-allow-origin"], "https://play.example");
  assert.match(String(allowed.headers["access-control-allow-headers"]), /Authorization/);
  const answer = await ask("http://127.0.0.1:8080", "POST");
  assert.equal(answer.statusCode, 201);
  assert.equal(answer.headers["access-control-allow-origin"], "http://127.0.0.1:8080");
  const stranger = await ask("https://evil.example");
  assert.equal(stranger.headers["access-control-allow-origin"], undefined);
  await app.close();
});

test("the host's match settings are checked, kept on the lobby and signed into every ticket of the match", async () => {
  const { app, guest, call, config } = await platform();
  const host = await guest("host");
  const lobby = (await call("POST", "/lobbies", host.headers, { maxPlayers: 3 })).json();
  assert.equal(lobby.settings, null);

  // A value outside the game's bounds, a missing key, an extra key or a wrong type is refused and the lobby stays open.
  const good = { count_multiplier: 2, max_alive: 12, break_seconds: 20 };
  for (const bad of [
    { ...good, count_multiplier: 9 },
    { ...good, count_multiplier: 0.1 },
    { ...good, max_alive: 121 },
    { ...good, max_alive: 3.5 },
    { ...good, break_seconds: 0.5 },
    { ...good, break_seconds: 500 },
    { count_multiplier: 2, max_alive: 12 },
    { ...good, extra: 1 },
    { ...good, max_alive: "12" },
    "hard",
    [],
  ]) {
    const refused = await call("POST", `/lobbies/${lobby.id}/start`, host.headers, { settings: bad });
    assert.equal(refused.statusCode, 400, JSON.stringify(bad));
    assert.equal(refused.json().error, "bad_settings");
  }
  assert.equal((await call("GET", `/lobbies/${lobby.id}`, host.headers)).json().state, "open");

  const started = await call("POST", `/lobbies/${lobby.id}/start`, host.headers, { settings: good });
  assert.equal(started.statusCode, 200);
  assert.deepEqual(started.json().settings, good);

  // A friend who joins later is handed the same rules in their ticket (the claims are signed, the game server reads them).
  const friend = await guest("friend");
  await call("POST", "/lobbies/join-by-code", friend.headers, { code: lobby.code });
  for (const who of [host, friend]) {
    const answer = (await call("POST", `/lobbies/${lobby.id}/ticket`, who.headers)).json();
    assert.deepEqual(verifyToken(config.ticketSecret, "ticket", answer.ticket)?.settings, good);
  }
  await app.close();
});

test("a night started with no settings keeps the game's defaults: no settings in the lobby or the ticket", async () => {
  const { app, guest, call, config } = await platform();
  const host = await guest("host");
  const lobby = (await call("POST", "/lobbies", host.headers, {})).json();
  const started = (await call("POST", `/lobbies/${lobby.id}/start`, host.headers, {})).json();
  assert.equal(started.settings, null, JSON.stringify(started));
  const answer = (await call("POST", `/lobbies/${lobby.id}/ticket`, host.headers)).json();
  assert.equal(verifyToken(config.ticketSecret, "ticket", answer.ticket)?.settings, undefined);
  // Only the host chooses, and only before the start.
  const other = await guest("other");
  const second = (await call("POST", "/lobbies", other.headers, {})).json();
  assert.equal((await call("POST", `/lobbies/${second.id}/start`, host.headers, { settings: { count_multiplier: 1, max_alive: 0, break_seconds: 0 } })).statusCode, 403);
  assert.equal((await call("POST", `/lobbies/${lobby.id}/start`, host.headers, { settings: { count_multiplier: 1, max_alive: 0, break_seconds: 0 } })).statusCode, 409);
  await app.close();
});

test("the host sets the rules while the lobby waits, the others read them, and the start keeps them", async () => {
  const { app, guest, call, config } = await platform();
  const host = await guest("host");
  const friend = await guest("friend");
  const lobby = (await call("POST", "/lobbies", host.headers, {})).json();
  await call("POST", "/lobbies/join-by-code", friend.headers, { code: lobby.code });
  const put = (who: { headers: object }, body: object) => call("PUT", `/lobbies/${lobby.id}/settings`, who.headers, body);

  const good = { count_multiplier: 3, max_alive: 14, break_seconds: 9 };
  const set = await put(host, good);
  assert.equal(set.statusCode, 200);
  assert.deepEqual(set.json().settings, good);
  // A member reads them on a poll.
  assert.deepEqual((await call("GET", `/lobbies/${lobby.id}`, friend.headers)).json().settings, good);

  // A guest cannot change them; a value the game does not take is refused and the rules stay as they were.
  assert.equal((await put(friend, { ...good, count_multiplier: 1 })).statusCode, 403);
  for (const bad of [{ ...good, count_multiplier: 9 }, { ...good, extra: 1 }, { count_multiplier: 2 }, []]) {
    const refused = await put(host, bad);
    assert.equal(refused.statusCode, 400, JSON.stringify(bad));
    assert.equal(refused.json().error, "bad_settings");
  }
  assert.deepEqual((await call("GET", `/lobbies/${lobby.id}`, host.headers)).json().settings, good);
  // Unknown lobby, then no sign-in.
  assert.equal((await call("PUT", "/lobbies/nope/settings", host.headers, good)).statusCode, 404);
  assert.equal((await call("PUT", `/lobbies/${lobby.id}/settings`, {}, good)).statusCode, 401);

  // Start with no settings of its own keeps what the host set; every ticket carries them.
  const started = await call("POST", `/lobbies/${lobby.id}/start`, host.headers, {});
  assert.equal(started.statusCode, 200);
  assert.deepEqual(started.json().settings, good);
  for (const who of [host, friend]) {
    const answer = (await call("POST", `/lobbies/${lobby.id}/ticket`, who.headers)).json();
    assert.deepEqual(verifyToken(config.ticketSecret, "ticket", answer.ticket)?.settings, good);
  }
  // Fixed from the start on.
  assert.equal((await put(host, { ...good, count_multiplier: 1 })).statusCode, 409);
  await app.close();
});

test("settings sent with the start win over the ones set while waiting", async () => {
  const { app, guest, call } = await platform();
  const host = await guest("host");
  const lobby = (await call("POST", "/lobbies", host.headers, {})).json();
  await call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, { count_multiplier: 3, max_alive: 14, break_seconds: 9 });
  const mine = { count_multiplier: 2, max_alive: 0, break_seconds: 0 };
  const started = (await call("POST", `/lobbies/${lobby.id}/start`, host.headers, { settings: mine })).json();
  assert.deepEqual(started.settings, mine);
  await app.close();
});

test("the host's map is checked, kept on the lobby, shown in its view and preview, and signed into the ticket", async () => {
  const { app, guest, call, config } = await platform();
  const host = await guest("host");
  const lobby = (await call("POST", "/lobbies", host.headers, {})).json();
  // A night nobody set a map for is on the default one, in the lobby's view and in what a code says before joining.
  assert.equal(lobby.settings, null);
  assert.equal(lobby.map, "drive_in");
  const code = { code: lobby.code };
  assert.equal((await call("POST", "/lobbies/preview", host.headers, code)).json().map, "drive_in");

  // Only a map the game can play is taken: a map that is listed but not built, a made-up one and a wrong type are refused.
  const rules = { count_multiplier: 1, max_alive: 0, break_seconds: 0 };
  const put = (body: object) => call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, body);
  for (const map of ["small_indoor", "nope", "", 7, null]) {
    const refused = await put({ ...rules, map });
    assert.equal(refused.statusCode, 400, JSON.stringify(map));
    assert.equal(refused.json().error, "bad_settings");
  }
  const set = await put({ ...rules, map: "drive_in" });
  assert.equal(set.statusCode, 200);
  assert.deepEqual(set.json().settings, { ...rules, map: "drive_in" });
  assert.equal(set.json().map, "drive_in");

  // The map rides the ticket with the other rules, so the game server builds the room on it.
  const started = await call("POST", `/lobbies/${lobby.id}/start`, host.headers, {});
  assert.equal(started.statusCode, 200);
  const answer = (await call("POST", `/lobbies/${lobby.id}/ticket`, host.headers)).json();
  assert.deepEqual(verifyToken(config.ticketSecret, "ticket", answer.ticket)?.settings, { ...rules, map: "drive_in" });

  // Quick join shows the map of the night it finds.
  const friend = await guest("friend", "10.0.0.2");
  const quick = (await call("POST", "/lobbies/quick", friend.headers)).json();
  assert.equal(quick.map, "drive_in");
  await app.close();
});

test("the bot count rides the settings: 0 to 7 whole bots are kept and signed, others are refused, a client without it is still taken", async () => {
  const { app, guest, call, config } = await platform();
  const host = await guest("host");
  const lobby = (await call("POST", "/lobbies", host.headers, { maxPlayers: 4 })).json();
  const good = { count_multiplier: 1, max_alive: 0, break_seconds: 0 };
  for (const bots of [8, -1, 1.5, "2"]) {
    const refused = await call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, { ...good, bots });
    assert.equal(refused.statusCode, 400, String(bots));
    assert.equal(refused.json().error, "bad_settings");
  }
  const chosen = { ...good, bots: 7 };
  const set = await call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, chosen);
  assert.equal(set.statusCode, 200);
  assert.deepEqual(set.json().settings, chosen);
  // Without `bots` the settings are kept as sent: the game server reads a missing count as none.
  const bare = await call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, good);
  assert.deepEqual(bare.json().settings, good);
  await call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, chosen);
  await call("POST", `/lobbies/${lobby.id}/start`, host.headers);
  const answer = (await call("POST", `/lobbies/${lobby.id}/ticket`, host.headers)).json();
  assert.deepEqual(verifyToken(config.ticketSecret, "ticket", answer.ticket)?.settings, chosen);
  await app.close();
});

test("the bot skill rides the settings: 0 to 2 whole numbers are kept and signed, others are refused", async () => {
  const { app, guest, call, config } = await platform();
  const host = await guest("host");
  const lobby = (await call("POST", "/lobbies", host.headers, { maxPlayers: 4 })).json();
  const good = { count_multiplier: 1, max_alive: 0, break_seconds: 0, bots: 2 };
  for (const bot_skill of [3, -1, 0.5, "1"]) {
    const refused = await call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, { ...good, bot_skill });
    assert.equal(refused.statusCode, 400, String(bot_skill));
    assert.equal(refused.json().error, "bad_settings");
  }
  const chosen = { ...good, bot_skill: 2 };
  const set = await call("PUT", `/lobbies/${lobby.id}/settings`, host.headers, chosen);
  assert.equal(set.statusCode, 200);
  assert.deepEqual(set.json().settings, chosen);
  await call("POST", `/lobbies/${lobby.id}/start`, host.headers);
  const answer = (await call("POST", `/lobbies/${lobby.id}/ticket`, host.headers)).json();
  assert.deepEqual(verifyToken(config.ticketSecret, "ticket", answer.ticket)?.settings, chosen);
  await app.close();
});
