// Lobby and capacity lifecycle: lobbies expire, a user is in one open lobby, a match that ends frees its slot.
// Every time is a clock the test moves by hand.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { StubDiscord } from "../src/discord.ts";
import { type Lobby, LobbyFailure, LobbyService } from "../src/lobbies.ts";
import { GameServerRegistry, MATCH_JOIN_GRACE_MS } from "../src/servers.ts";
import { MemoryStore } from "../src/store.ts";

const MINUTE = 60_000;
const limits = { openIdleMs: 10 * MINUTE, startedMaxAgeMs: 120 * MINUTE };

const alice = { userId: "alice", name: "alice" };
const bob = { userId: "bob", name: "bob" };
const carol = { userId: "carol", name: "carol" };

function failure(fn: () => unknown): string {
  try {
    fn();
  } catch (error) {
    if (error instanceof LobbyFailure) return error.reason;
    throw error;
  }
  return "no failure";
}

/** A lobby service with a clock and a game-server pool of `slots` matches, counted by what was allocated. */
function service(slots: number) {
  const clock = { now: 0 };
  const running = new Set<string>();
  const lobbies = new LobbyService({
    allocate: (matchId) => {
      if (running.size >= slots) return null;
      running.add(matchId);
      return { id: "gs", url: "ws://gs", activityPath: "/gs", capacity: slots, matches: running.size };
    },
    release: (matchId) => void running.delete(matchId),
    now: () => clock.now,
    limits,
  });
  return { lobbies, clock, running };
}

test("an open lobby expires when nobody touches it, and a member's poll keeps it alive", () => {
  const { lobbies, clock } = service(1);
  const idle = lobbies.create(alice, 4, null);
  const polled = lobbies.create(bob, 4, null);
  assert.equal(lobbies.size, 2);

  clock.now = 6 * MINUTE;
  lobbies.view(polled.id, "bob"); // a poll is activity
  clock.now = 11 * MINUTE; // alice's is idle for 11 minutes, bob's for 5
  assert.equal(failure(() => lobbies.get(idle.id)), "not_found");
  assert.equal(lobbies.findByCode(idle.code), null);
  assert.equal(lobbies.get(polled.id).id, polled.id);

  clock.now = 25 * MINUTE;
  assert.equal(lobbies.sweep(), 1); // bob's went quiet too
  assert.equal(lobbies.size, 0);
  assert.equal(failure(() => lobbies.view(polled.id, "bob")), "not_found");
});

test("an expired lobby frees its members, its code and its Activity instance", () => {
  const { lobbies, clock } = service(1);
  const first = lobbies.create(alice, 4, "instance-1");
  clock.now = 11 * MINUTE;
  lobbies.sweep();
  assert.equal(lobbies.findByInstance("instance-1"), null);
  const again = lobbies.create(alice, 4, "instance-1"); // alice is free to open another
  assert.notEqual(again.id, first.id);
  assert.equal(lobbies.findByInstance("instance-1")?.id, again.id);
});

test("a started lobby lasts until its match ends or its maximum age, then frees the slot", () => {
  const { lobbies, clock, running } = service(1);
  const lobby = lobbies.create(alice, 4, null);
  lobbies.start(lobby.id, "alice", 1);
  assert.equal(running.size, 1);

  clock.now = 119 * MINUTE; // far past the open-lobby idle time: a started lobby does not idle out
  assert.equal(lobbies.get(lobby.id).state, "started");
  clock.now = 121 * MINUTE;
  assert.equal(failure(() => lobbies.get(lobby.id)), "not_found");
  assert.equal(running.size, 0);
  assert.equal(lobbies.size, 0);
});

test("a user is in at most one open lobby; leaving hands over the host and drops an empty lobby", () => {
  const { lobbies } = service(1);
  const first = lobbies.create(alice, 4, null);
  assert.equal(failure(() => lobbies.create(alice, 4, null)), "already_in_lobby");
  lobbies.join(first.id, bob);
  const second = lobbies.create(carol, 4, null);
  assert.equal(failure(() => lobbies.join(first.id, carol)), "already_in_lobby");
  assert.equal(lobbies.join(first.id, bob).id, first.id); // joining your own lobby again is harmless

  lobbies.leave(first.id, "alice"); // the host leaves
  assert.equal(lobbies.get(first.id).hostId, "bob");
  assert.deepEqual(lobbies.get(first.id).members.map((m) => m.userId), ["bob"]);
  assert.equal(failure(() => lobbies.start(first.id, "alice", 1)), "not_host");
  assert.equal(failure(() => lobbies.leave(first.id, "alice")), "not_member");
  lobbies.create(alice, 4, null); // alice is free again

  lobbies.leave(first.id, "bob"); // the last one out closes the lobby
  assert.equal(failure(() => lobbies.get(first.id)), "not_found");
  assert.equal(lobbies.findByCode(first.code), null);
  assert.equal(lobbies.get(second.id).id, second.id);
});

test("starting a lobby frees its members to open another; leaving a started lobby keeps the match", () => {
  const { lobbies, running } = service(2);
  const lobby = lobbies.create(alice, 4, null);
  lobbies.join(lobby.id, bob);
  lobbies.start(lobby.id, "alice", 1);
  const next = lobbies.create(alice, 4, null);
  assert.equal(next.state, "open");

  lobbies.leave(lobby.id, "alice");
  assert.equal(running.size, 1); // bob is still in the match
  lobbies.leave(lobby.id, "bob");
  assert.equal(running.size, 0); // nobody is left: the match is over
});

test("lobbies do not pile up: create-and-abandon cycles leave nothing behind", () => {
  const { lobbies, clock } = service(1);
  for (let i = 0; i < 2000; i++) {
    const lobby = lobbies.create({ userId: `u${i}`, name: "u" }, 4, `i${i}`);
    if (i % 2 === 0) lobbies.leave(lobby.id, `u${i}`);
    clock.now += 1000;
  }
  clock.now += limits.openIdleMs + 1;
  lobbies.sweep();
  assert.equal(lobbies.size, 0);
});

// ---- over HTTP, with the registry

const env = {
  SESSION_SECRET: "s".repeat(32),
  TICKET_SECRET: "t".repeat(32),
  GAME_SERVER_SECRET: "g".repeat(32),
  DISCORD_MODE: "stub",
  ALLOW_STUB_SIGN_IN: "1",
};

async function platform(slots: number) {
  const clock = { now: 1_000_000 };
  const registry = new GameServerRegistry(60 * MINUTE, () => clock.now);
  const config = loadConfig(env);
  const app = buildApp({ config, store: new MemoryStore(), discord: new StubDiscord(), registry, now: () => clock.now, lobbyLimits: limits });
  const auth = { authorization: `Bearer ${config.gameServerSecret}` };
  const beat = (matchIds: string[] = []) =>
    app.inject({ method: "POST", url: "/internal/servers/heartbeat", headers: auth, payload: { id: "gs", url: "ws://gs", activityPath: "/gs", capacity: slots, matchIds } });
  await beat();

  const tokens = new Map<string, string>();
  const user = async (name: string) => {
    const response = await app.inject({ method: "POST", url: "/auth/discord", payload: { code: `stub:${tokens.size + 1}:${name}` } });
    tokens.set(name, response.json().token);
    return { authorization: `Bearer ${response.json().token}` };
  };
  /** Signs `name` in, opens a lobby and starts it: the status of the start, and the lobby. */
  const startMatch = async (name: string) => {
    const headers = await user(name);
    const lobby = (await app.inject({ method: "POST", url: "/lobbies", headers, payload: {} })).json() as Lobby;
    const start = await app.inject({ method: "POST", url: `/lobbies/${lobby.id}/start`, headers });
    return { status: start.statusCode, lobby, headers, matchId: start.json().matchId as string | null };
  };
  return { app, clock, auth, beat, user, startMatch, registry };
}

test("two quick starts do not both take the last slot, and a finished match frees it", async () => {
  const { app, auth, startMatch } = await platform(1);
  const first = await startMatch("ann");
  const second = await startMatch("ben"); // the game server has not seen a player of the first match yet
  assert.equal(first.status, 200);
  assert.equal(second.status, 503);

  const wrongSecret = await app.inject({ method: "POST", url: `/internal/matches/${first.matchId}/end`, headers: { authorization: "Bearer nope" } });
  assert.equal(wrongSecret.statusCode, 401);
  const ended = await app.inject({ method: "POST", url: `/internal/matches/${first.matchId}/end`, headers: auth });
  assert.equal(ended.statusCode, 204);
  assert.equal((await app.inject({ method: "POST", url: `/internal/matches/${first.matchId}/end`, headers: auth })).statusCode, 204); // idempotent

  const gone = await app.inject({ method: "GET", url: `/lobbies/${first.lobby.id}`, headers: first.headers });
  assert.equal(gone.statusCode, 404);
  const third = await startMatch("cat");
  assert.equal(third.status, 200); // the slot is free again
  await app.close();
});

test("a heartbeat that does not list a fresh match does not free it, a later one does", async () => {
  const { app, clock, beat, startMatch } = await platform(1);
  const first = await startMatch("ann");
  assert.equal(first.status, 200);

  await beat([]); // the server has no player in it yet: that must not free the slot
  assert.equal((await startMatch("ben")).status, 503);

  clock.now += MATCH_JOIN_GRACE_MS + 1;
  await beat([]); // nobody ever joined and the grace is over: the match is dropped, and its lobby with it
  assert.equal((await app.inject({ method: "GET", url: `/lobbies/${first.lobby.id}`, headers: first.headers })).statusCode, 404);
  assert.equal((await startMatch("cat")).status, 200);
  await app.close();
});

test("a running match stays counted while the server lists it, and one the backend never assigned is adopted", async () => {
  const { app, clock, beat, startMatch } = await platform(2);
  const first = await startMatch("ann");
  clock.now += 3 * MATCH_JOIN_GRACE_MS;
  await beat([first.matchId!]); // listed: still running, long after the grace
  assert.equal((await app.inject({ method: "GET", url: `/lobbies/${first.lobby.id}`, headers: first.headers })).statusCode, 200);

  // The backend restarted and forgot a match the server is still running: it takes a slot all the same.
  await beat([first.matchId!, "match-from-before-the-restart"]);
  assert.equal((await startMatch("ben")).status, 503);
  await beat([first.matchId!]); // ...and when the server stops listing it, after its grace, the slot is back
  clock.now += MATCH_JOIN_GRACE_MS + 1;
  await beat([first.matchId!]);
  assert.equal((await startMatch("cat")).status, 200);
  await app.close();
});

test("leave over HTTP, and a lobby gone after a restart answers 404 not_found", async () => {
  const { app, user } = await platform(1);
  const headers = await user("ann");
  const lobby = (await app.inject({ method: "POST", url: "/lobbies", headers, payload: {} })).json() as Lobby;
  assert.equal((await app.inject({ method: "POST", url: "/lobbies", headers, payload: {} })).statusCode, 409); // already in one
  assert.equal((await app.inject({ method: "POST", url: `/lobbies/${lobby.id}/leave`, headers })).statusCode, 204);
  const gone = await app.inject({ method: "GET", url: `/lobbies/${lobby.id}`, headers });
  assert.deepEqual([gone.statusCode, gone.json()], [404, { error: "not_found" }]);
  assert.equal((await app.inject({ method: "POST", url: `/lobbies/${lobby.id}/ticket`, headers })).statusCode, 404);
  assert.equal((await app.inject({ method: "POST", url: `/lobbies/${lobby.id}/leave`, headers })).statusCode, 404);
  await app.close();
});

// --- The end of a night: the lobby opens again for the people who were there (Deadnight #973) ---

test("a finished night reopens its lobby for the people who were there, with its settings and its host", () => {
  const { lobbies, running } = service(2);
  const lobby = lobbies.create(alice, 8, "instance-1");
  lobbies.join(lobby.id, bob);
  lobbies.join(lobby.id, carol);
  lobbies.setSettings(lobby.id, "alice", 10, { count_multiplier: 2, max_alive: 0, break_seconds: 0, map: "small_indoor", bots: 3 });
  const started = lobbies.start(lobby.id, "alice", 10);
  const matchId = started.match!.id;
  lobbies.setPlayers(matchId, 3);
  lobbies.setRound(matchId, 7);

  lobbies.matchEnded(matchId, { present: ["alice", "carol"] }); // bob left during the intermission
  const again = lobbies.get(lobby.id);
  assert.equal(again.state, "open");
  assert.equal(again.code, lobby.code);
  assert.equal(again.hostId, "alice");
  assert.deepEqual(again.members.map((m) => m.userId), ["alice", "carol"]);
  assert.deepEqual(again.settings, started.settings);
  assert.equal(again.match, null);
  assert.equal(again.round, null);
  assert.equal(again.players, null);
  assert.equal(running.size, 0); // the match's slot is free
  assert.equal(lobbies.findByInstance("instance-1")?.id, lobby.id);
  // They can start the next night at once, and the host's rules are still the ones chosen.
  const next = lobbies.start(lobby.id, "alice", 10);
  assert.equal(next.state, "started");
  assert.equal(next.settings?.map, "small_indoor");
  assert.equal(running.size, 1);
});

test("a finished night whose host left hands the lobby to the next seat, and an empty one drops it", () => {
  const { lobbies } = service(2);
  const lobby = lobbies.create(alice, 8, null);
  lobbies.join(lobby.id, bob);
  const first = lobbies.start(lobby.id, "alice", 1).match!.id;
  lobbies.matchEnded(first, { present: ["bob"] });
  assert.equal(lobbies.get(lobby.id).hostId, "bob");
  assert.deepEqual(lobbies.get(lobby.id).members.map((m) => m.userId), ["bob"]);

  const second = lobbies.start(lobby.id, "bob", 1).match!.id;
  lobbies.matchEnded(second, { present: [] }); // nobody was left: the lobby goes, as any other end does
  assert.equal(failure(() => lobbies.get(lobby.id)), "not_found");
});

test("a night that ended any other way still drops its lobby, and a user already in another lobby is not put back", () => {
  const { lobbies } = service(3);
  const one = lobbies.create(alice, 8, null);
  lobbies.join(one.id, bob);
  const matchOne = lobbies.start(one.id, "alice", 1).match!.id;
  lobbies.matchEnded(matchOne);
  assert.equal(failure(() => lobbies.get(one.id)), "not_found");

  const two = lobbies.create(alice, 8, null);
  lobbies.join(two.id, bob);
  const matchTwo = lobbies.start(two.id, "alice", 1).match!.id;
  const other = lobbies.create(bob, 8, null); // bob opened a lobby of his own while the night was on
  lobbies.matchEnded(matchTwo, { present: ["alice", "bob"] });
  assert.deepEqual(lobbies.get(two.id).members.map((m) => m.userId), ["alice"]);
  assert.equal(lobbies.get(other.id).hostId, "bob");
});

test("the game server's end call with finished and the users present reopens the lobby over HTTP", async () => {
  const { app, auth, startMatch, user } = await platform(1);
  const first = await startMatch("ann");
  const guest = await user("ben");
  await app.inject({ method: "POST", url: "/lobbies/join-by-code", headers: guest, payload: { code: first.lobby.code } });
  const ended = await app.inject({
    method: "POST",
    url: `/internal/matches/${first.matchId}/end`,
    headers: auth,
    payload: { finished: true, present: [first.lobby.hostId, (await app.inject({ method: "GET", url: `/lobbies/${first.lobby.id}`, headers: guest })).json().members[1].userId] },
  });
  assert.equal(ended.statusCode, 204);
  const back = await app.inject({ method: "GET", url: `/lobbies/${first.lobby.id}`, headers: first.headers });
  assert.equal(back.statusCode, 200);
  assert.equal(back.json().state, "open");
  assert.equal(back.json().members.length, 2);
  const again = await app.inject({ method: "POST", url: `/lobbies/${first.lobby.id}/start`, headers: first.headers });
  assert.equal(again.statusCode, 200); // the slot was given back, so the host can start the next night
  await app.close();
});
