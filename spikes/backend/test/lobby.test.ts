// The pre-game lobby (#515): who is in it, the host's Start, a host that leaves, a full room, a member that went away,
// and a night in progress that a late joiner can read (its round) before pressing Join. Every time is a clock the test
// moves by hand.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { OffDiscord } from "../src/discord.ts";
import { DEFAULT_LOBBY_LIMITS, LobbyService, MAX_PLAYERS } from "../src/lobbies.ts";
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

async function platform(capacity = 3) {
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
  const guest = async (name: string) => {
    const response = await app.inject({ method: "POST", url: "/auth/guest", payload: { name }, remoteAddress: `10.0.0.${++guests}` });
    return { headers: { authorization: `Bearer ${response.json().token}` }, user: response.json().user as { id: string; name: string } };
  };
  const call = (method: "GET" | "POST", url: string, who: { headers: object }, payload?: object) =>
    app.inject({ method, url, headers: who.headers, payload });
  return { app, clock, beat, guest, call };
}

/** Polls every few seconds as a client on the lobby screen does. */
const POLL_MS = 2_000;

test("a lobby lists its members in seat order, marks the host, and waits for the host to start", async () => {
  const { app, guest, call } = await platform();
  const [ann, bo] = [await guest("Ann"), await guest("Bo")];
  const made = (await call("POST", "/lobbies", ann, { maxPlayers: 4 })).json();
  assert.equal(made.state, "open");
  assert.equal(made.round, null);
  assert.equal(made.matchId, null);
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });

  const seen = (await call("GET", `/lobbies/${made.id}`, bo)).json();
  assert.equal(seen.hostId, ann.user.id);
  assert.deepEqual(
    seen.members.map((m: { name: string; seat: number; host: boolean }) => [m.name, m.seat, m.host]),
    [
      ["Ann", 1, true],
      ["Bo", 2, false],
    ],
  );
  // Nobody gets a ticket before the host starts.
  assert.equal((await call("POST", `/lobbies/${made.id}/ticket`, bo)).statusCode, 409);
  await app.close();
});

test("only the host starts the night, and a guest then sees it started and takes a ticket", async () => {
  const { app, guest, call } = await platform();
  const [ann, bo, stranger] = [await guest("Ann"), await guest("Bo"), await guest("Cy")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });

  const refused = await call("POST", `/lobbies/${made.id}/start`, bo);
  assert.equal(refused.statusCode, 403);
  assert.equal(refused.json().error, "not_host");
  assert.equal((await call("POST", `/lobbies/${made.id}/start`, stranger)).statusCode, 403);
  assert.equal((await call("GET", `/lobbies/${made.id}`, bo)).json().state, "open");

  assert.equal((await call("POST", `/lobbies/${made.id}/start`, ann)).statusCode, 200);
  assert.equal((await call("POST", `/lobbies/${made.id}/start`, ann)).statusCode, 409); // not twice
  const polled = (await call("GET", `/lobbies/${made.id}`, bo)).json();
  assert.equal(polled.state, "started");
  assert.ok(polled.matchId);
  assert.equal((await call("POST", `/lobbies/${made.id}/ticket`, bo)).statusCode, 200);
  await app.close();
});

test("the host leaves before the start: the role passes to the next seat, and the seats close up", async () => {
  const { app, guest, call } = await platform();
  const [ann, bo, cy] = [await guest("Ann"), await guest("Bo"), await guest("Cy")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });
  await call("POST", "/lobbies/join-by-code", cy, { code: made.code });

  assert.equal((await call("POST", `/lobbies/${made.id}/leave`, ann)).statusCode, 204);
  const after = (await call("GET", `/lobbies/${made.id}`, cy)).json();
  assert.equal(after.hostId, bo.user.id);
  assert.deepEqual(
    after.members.map((m: { name: string; seat: number; host: boolean }) => [m.name, m.seat, m.host]),
    [
      ["Bo", 1, true],
      ["Cy", 2, false],
    ],
  );
  // The old host is no longer a member and cannot start it; the new one can.
  assert.equal((await call("POST", `/lobbies/${made.id}/start`, ann)).statusCode, 403);
  assert.equal((await call("POST", `/lobbies/${made.id}/start`, bo)).statusCode, 200);

  // The last one out closes an open lobby.
  const solo = (await call("POST", "/lobbies", ann, {})).json();
  await call("POST", `/lobbies/${solo.id}/leave`, ann);
  assert.equal((await call("GET", `/lobbies/${solo.id}`, ann)).statusCode, 404);
  await app.close();
});

test("a full room turns the next player away with 409 full, and a seat that frees up is taken", async () => {
  const { app, guest, call } = await platform();
  const players = [];
  for (const name of ["a", "b", "c", "d", "e"]) players.push(await guest(name));
  const made = (await call("POST", "/lobbies", players[0]!, { maxPlayers: 4 })).json();
  for (const player of players.slice(1, 4)) {
    assert.equal((await call("POST", "/lobbies/join-by-code", player, { code: made.code })).statusCode, 200);
  }
  const turned = await call("POST", "/lobbies/join-by-code", players[4]!, { code: made.code });
  assert.equal(turned.statusCode, 409);
  assert.equal(turned.json().error, "full");
  await call("POST", `/lobbies/${made.id}/leave`, players[3]!);
  assert.equal((await call("POST", "/lobbies/join-by-code", players[4]!, { code: made.code })).statusCode, 200);
  await app.close();
});

test("a room holds eight by default, people and bots together; a ninth player is turned away and a limit above eight is refused", async () => {
  const { app, guest, call } = await platform();
  const players = [];
  for (let i = 0; i < 9; i++) players.push(await guest(`p${i}`));
  const made = (await call("POST", "/lobbies", players[0]!, {})).json();
  assert.equal(made.maxPlayers, MAX_PLAYERS);
  assert.equal(made.maxPlayers, 8);
  for (const player of players.slice(1, 8)) {
    assert.equal((await call("POST", "/lobbies/join-by-code", player, { code: made.code })).statusCode, 200);
  }
  const turned = await call("POST", "/lobbies/join-by-code", players[8]!, { code: made.code });
  assert.equal(turned.statusCode, 409);
  assert.equal(turned.json().error, "full");
  const wide = await call("POST", "/lobbies", players[8]!, { maxPlayers: MAX_PLAYERS + 1 });
  assert.equal(wide.statusCode, 400);
  await app.close();
});

test("a member who stops polling is dropped after a minute, and the host role goes to someone who is still there", async () => {
  const { app, guest, call, clock } = await platform();
  const [ann, bo, cy] = [await guest("Ann"), await guest("Bo"), await guest("Cy")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });
  await call("POST", "/lobbies/join-by-code", cy, { code: made.code });

  // Bo and Cy keep polling; Ann (the host) closed her tab.
  for (let t = 0; t < DEFAULT_LOBBY_LIMITS.memberAwayMs + 10_000; t += POLL_MS) {
    clock.now += POLL_MS;
    await call("GET", `/lobbies/${made.id}`, bo);
    await call("GET", `/lobbies/${made.id}`, cy);
  }
  const seen = (await call("GET", `/lobbies/${made.id}`, cy)).json();
  assert.deepEqual(seen.members.map((m: { name: string }) => m.name), ["Bo", "Cy"]);
  assert.equal(seen.hostId, bo.user.id);
  // Her place is free: she is not stuck in "already in a lobby" and can open another.
  assert.equal((await call("POST", "/lobbies", ann, {})).statusCode, 201);
  // Coming back to the old lobby she is told she is not in it any more.
  assert.equal((await call("GET", `/lobbies/${made.id}`, ann)).statusCode, 403);
  await app.close();
});

test("a member seen a moment ago is shown as there, one quiet for a while as away", async () => {
  const { app, guest, call, clock } = await platform();
  const [ann, bo] = [await guest("Ann"), await guest("Bo")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });
  clock.now += 20_000;
  const seen = (await call("GET", `/lobbies/${made.id}`, bo)).json();
  assert.deepEqual(seen.members.map((m: { away: boolean }) => m.away), [true, false]);
  await app.close();
});

test("a host alone is never dropped for being quiet: the lobby just expires when nobody comes back", async () => {
  const { app, guest, call, clock } = await platform();
  const ann = await guest("Ann");
  const made = (await call("POST", "/lobbies", ann, {})).json();
  clock.now += 5 * 60_000; // away for five minutes, copying the link into a chat
  const back = await call("GET", `/lobbies/${made.id}`, ann);
  assert.equal(back.statusCode, 200);
  assert.equal(back.json().hostId, ann.user.id);
  clock.now += 11 * 60_000;
  assert.equal((await call("GET", `/lobbies/${made.id}`, ann)).statusCode, 404);
  await app.close();
});

test("a started night carries its round from the game server, and a late joiner reads it before joining", async () => {
  const { app, guest, call, beat } = await platform();
  const [ann, bo, late] = [await guest("Ann"), await guest("Bo"), await guest("Late")];
  const made = (await call("POST", "/lobbies", ann, { maxPlayers: 4 })).json();
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });

  // Before the start the code says: waiting room, host Ann, two of four.
  const waiting = (await call("POST", "/lobbies/preview", late, { code: made.code.toLowerCase() })).json();
  assert.deepEqual(
    { state: waiting.state, round: waiting.round, players: waiting.players, maxPlayers: waiting.maxPlayers, full: waiting.full, host: waiting.hostName },
    { state: "open", round: null, players: 2, maxPlayers: 4, full: false, host: "Ann" },
  );

  const started = (await call("POST", `/lobbies/${made.id}/start`, ann)).json();
  // The round arrives with the game server's heartbeat; until it says one, the night is round 1 (null: not known yet).
  assert.equal((await call("POST", "/lobbies/preview", late, { code: made.code })).json().round, null);
  await beat([started.matchId], { players: { [started.matchId]: 2 }, rounds: { [started.matchId]: 4 } });
  const inProgress = (await call("POST", "/lobbies/preview", late, { code: made.code })).json();
  assert.deepEqual(
    { state: inProgress.state, round: inProgress.round, players: inProgress.players, full: inProgress.full },
    { state: "started", round: 4, players: 2, full: false },
  );
  assert.equal((await call("GET", `/lobbies/${made.id}`, bo)).json().round, 4);

  // Pressing Join takes the late joiner straight to a ticket.
  assert.equal((await call("POST", "/lobbies/join-by-code", late, { code: made.code })).statusCode, 200);
  assert.equal((await call("POST", `/lobbies/${made.id}/ticket`, late)).statusCode, 200);
  // The round moves on with the night.
  await beat([started.matchId], { players: { [started.matchId]: 3 }, rounds: { [started.matchId]: 5 } });
  assert.equal((await call("GET", `/lobbies/${made.id}`, late)).json().round, 5);
  await app.close();
});

test("the preview says full for a night with no room, and 404 for a code nobody has; it joins nobody", async () => {
  const { app, guest, call, beat } = await platform();
  const [ann, stranger] = [await guest("Ann"), await guest("Cy")];
  const made = (await call("POST", "/lobbies", ann, { maxPlayers: 2 })).json();
  const started = (await call("POST", `/lobbies/${made.id}/start`, ann)).json();
  await beat([started.matchId], { players: { [started.matchId]: 2 }, rounds: { [started.matchId]: 2 } });

  const full = (await call("POST", "/lobbies/preview", stranger, { code: made.code })).json();
  assert.equal(full.full, true);
  assert.equal((await call("POST", "/lobbies/preview", stranger, { code: "NOSUCHCD" })).statusCode, 404);
  // Looking is not joining.
  assert.equal((await call("GET", `/lobbies/${made.id}`, stranger)).statusCode, 403);
  assert.equal((await call("POST", "/lobbies/preview", { headers: {} }, { code: made.code })).statusCode, 401);
  await app.close();
});

test("a lobby service drops an absent member and counts the round, with no HTTP in between", () => {
  const clock = { now: 0 };
  const lobbies = new LobbyService({
    allocate: () => ({ id: "gs", url: "ws://gs", activityPath: "/gs", capacity: 1, matches: 1 }),
    release: () => {},
    now: () => clock.now,
  });
  const ann = { userId: "ann", name: "Ann" };
  const bo = { userId: "bo", name: "Bo" };
  const made = lobbies.create(ann, 4, null);
  lobbies.join(made.id, bo);
  clock.now = DEFAULT_LOBBY_LIMITS.memberAwayMs + 1;
  lobbies.view(made.id, "ann"); // Ann is there, Bo has not been heard from
  assert.deepEqual(lobbies.get(made.id).members.map((m) => m.userId), ["ann"]);
  const started = lobbies.start(made.id, "ann", 1);
  lobbies.setRound(started.match!.id, 3);
  assert.equal(lobbies.get(made.id).round, 3);
  lobbies.setRound("unknown-match", 9); // ignored, as setPlayers does
});

test("the Activity's voice channel is looked at by its instance: nothing yet, then a waiting room, then a night in round N", async () => {
  const { app, guest, call, beat } = await platform();
  const [ann, bo] = [await guest("Ann"), await guest("Bo")];
  // Nobody has opened the lobby of this channel: nothing to read, and looking made none.
  assert.equal((await call("POST", "/lobbies/preview", bo, { instanceId: "voice-9" })).statusCode, 404);
  assert.equal((await call("POST", "/lobbies/preview", bo, {})).statusCode, 400);

  const made = (await call("POST", "/lobbies", ann, { instanceId: "voice-9" })).json();
  const waiting = (await call("POST", "/lobbies/preview", bo, { instanceId: "voice-9" })).json();
  assert.deepEqual(
    { code: waiting.code, state: waiting.state, players: waiting.players, host: waiting.hostName },
    { code: made.code, state: "open", players: 1, host: "Ann" },
  );
  assert.equal((await call("GET", `/lobbies/${made.id}`, bo)).statusCode, 403); // looking joined nobody

  const started = (await call("POST", `/lobbies/${made.id}/start`, ann)).json();
  await beat([started.matchId], { players: { [started.matchId]: 1 }, rounds: { [started.matchId]: 6 } });
  const inProgress = (await call("POST", "/lobbies/preview", bo, { instanceId: "voice-9" })).json();
  assert.deepEqual({ state: inProgress.state, round: inProgress.round, full: inProgress.full }, { state: "started", round: 6, full: false });
  await app.close();
});
