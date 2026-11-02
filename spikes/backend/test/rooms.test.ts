// Rooms for friends on the web: guest sign-in, a night in progress that takes newcomers, quick join, and the
// Activity instance that lands everyone in one night.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp, GUEST_ID_PREFIX, GUESTS_PER_ADDRESS_PER_HOUR, guestName } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { OffDiscord } from "../src/discord.ts";
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
  const call = async (method: "GET" | "POST", url: string, headers: object, payload?: object) =>
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
  assert.equal(guestName("  <b>Ann</b> & co  "), "bAnnb  co");
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
  const started = (await call("POST", `/lobbies/${lobby.id}/start`, host.headers)).json();
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

  await beat([first.matchId], { [first.matchId]: 4 });
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
