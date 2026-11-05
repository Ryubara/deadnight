// Moving between nights (Deadnight #1177): a player is in one lobby at a time, and creating or joining another takes
// them out of the one they were in, whatever state it is in. Nothing a player left holds them: a lobby with no people in
// it is gone at once, and the game server's word that a seat is empty takes the member out of a started night.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { OffDiscord } from "../src/discord.ts";
import { LobbyFailure, LobbyService } from "../src/lobbies.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore } from "../src/store.ts";

const MINUTE = 60_000;
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

function service(slots = 8) {
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
    limits: { openIdleMs: 10 * MINUTE, startedMaxAgeMs: 120 * MINUTE },
  });
  return { lobbies, clock, running };
}

test("create takes a player out of the open lobby they were in, and an empty lobby is gone at once", () => {
  const { lobbies } = service();
  const first = lobbies.create(alice, 8);
  const second = lobbies.create(alice, 8); // no refusal: she moves
  assert.notEqual(second.id, first.id);
  assert.equal(failure(() => lobbies.get(first.id)), "not_found");
  assert.equal(lobbies.findByCode(first.code), null);
  assert.equal(lobbies.size, 1);
});

test("join takes a player out of the lobby they were in; the host role of the one they left passes on", () => {
  const { lobbies } = service();
  const first = lobbies.create(alice, 8);
  lobbies.join(first.id, bob);
  const second = lobbies.create(carol, 8);
  lobbies.join(second.id, alice); // alice moves from the one she hosts to carol's
  assert.deepEqual(lobbies.get(first.id).members.map((m) => m.userId), ["bob"]);
  assert.equal(lobbies.get(first.id).hostId, "bob");
  assert.deepEqual(lobbies.get(second.id).members.map((m) => m.userId), ["carol", "alice"]);
  // A join that is refused (full) leaves the player where they were.
  const small = lobbies.create({ userId: "dan", name: "dan" }, 1);
  assert.equal(failure(() => lobbies.join(small.id, alice)), "full");
  assert.deepEqual(lobbies.get(second.id).members.map((m) => m.userId), ["carol", "alice"]);
});

test("a player in a started night who creates or joins another leaves it, and a night with nobody left is over", () => {
  const { lobbies, running } = service();
  const night = lobbies.create(alice, 8);
  lobbies.join(night.id, bob);
  lobbies.start(night.id, "alice", 1);
  assert.equal(running.size, 1);

  const mine = lobbies.create(alice, 8); // from a started night, to a lobby of her own
  assert.deepEqual(lobbies.get(night.id).members.map((m) => m.userId), ["bob"]);
  assert.equal(lobbies.get(night.id).hostId, "bob");
  lobbies.join(mine.id, bob); // the last one out of the night: it is over and its slot is free
  assert.equal(failure(() => lobbies.get(night.id)), "not_found");
  assert.equal(running.size, 0);
});

test("a started night reopened for the people who were there does not hold the one who went to the menu", () => {
  const { lobbies } = service();
  const night = lobbies.create(alice, 8);
  lobbies.join(night.id, bob);
  const matchId = lobbies.start(night.id, "alice", 1).match!.id;
  // The game server says the night finished and who was still connected; bob had closed his tab (not listed).
  lobbies.matchEnded(matchId, { present: ["alice"] });
  assert.deepEqual(lobbies.get(night.id).members.map((m) => m.userId), ["alice"]);
  const next = lobbies.create(bob, 8); // bob is free: nothing holds him
  assert.equal(next.hostId, "bob");
  // alice is in the reopened lobby but can still move at once.
  const moved = lobbies.join(next.id, alice);
  assert.equal(moved.members.length, 2);
  assert.equal(failure(() => lobbies.get(night.id)), "not_found");
});

test("a lobby reopened by a finished night that nobody reads is gone within a minute, one that is read stays", () => {
  const { lobbies, clock } = service();
  const quiet = lobbies.create(alice, 8); // alice's screen gave up waiting for it and went to the menu
  const read = lobbies.create(bob, 8); // bob's night screen is asking for it
  const matchQuiet = lobbies.start(quiet.id, "alice", 1).match!.id;
  const matchRead = lobbies.start(read.id, "bob", 1).match!.id;
  lobbies.matchEnded(matchQuiet, { present: ["alice"] });
  lobbies.matchEnded(matchRead, { present: ["bob"] });
  clock.now += 30_000;
  lobbies.view(read.id, "bob"); // the night screen's ask
  clock.now += 31_000; // a minute after it opened
  assert.equal(lobbies.sweep(), 1);
  assert.equal(failure(() => lobbies.get(quiet.id)), "not_found");
  assert.equal(lobbies.get(read.id).state, "open"); // read once: it lives by the usual idle time again
  clock.now += 5 * MINUTE;
  assert.equal(lobbies.get(read.id).id, read.id);
});

test("a sole member who closed the tab of a waiting lobby is not refused for it", () => {
  const { lobbies } = service();
  const abandoned = lobbies.create(alice, 8); // her tab closed: nobody polls it
  const other = lobbies.create(bob, 8);
  assert.equal(lobbies.join(other.id, alice).members.length, 2); // the join works at once
  assert.equal(failure(() => lobbies.get(abandoned.id)), "not_found");
});

test("quick join moves a player to a night, and never hands back the one the game server says they left", () => {
  const { lobbies, running } = service();
  const night = lobbies.quick(alice, 1); // public, started
  lobbies.quick(bob, 1);
  const matchId = night.match!.id;
  assert.equal(lobbies.quick(alice, 1).id, night.id); // asking again while in it is the same night
  // alice's seat on the game server is empty (she went to the menu): she is no longer a member.
  lobbies.memberLeft(matchId, "alice");
  assert.deepEqual(lobbies.get(night.id).members.map((m) => m.userId), ["bob"]);
  // She creates a lobby of her own: not refused. Quick join from there leaves it.
  const mine = lobbies.create(alice, 8);
  const again = lobbies.quick(alice, 1);
  assert.equal(failure(() => lobbies.get(mine.id)), "not_found");
  assert.ok(again.members.some((m) => m.userId === "alice"));
  assert.ok(running.size >= 1);
});

test("the game server saying a seat is empty takes the member out, and the last one out ends the night", () => {
  const { lobbies, running } = service();
  const night = lobbies.create(alice, 8);
  lobbies.join(night.id, bob);
  const matchId = lobbies.start(night.id, "alice", 1).match!.id;
  lobbies.memberLeft(matchId, "alice");
  assert.equal(lobbies.get(night.id).hostId, "bob"); // the host role passes on
  assert.equal(lobbies.memberLeft("no-such-match", "bob"), false); // unknown matches are ignored
  lobbies.memberLeft(matchId, "bob");
  assert.equal(failure(() => lobbies.get(night.id)), "not_found");
  assert.equal(running.size, 0);
  lobbies.memberLeft(matchId, "bob"); // idempotent
});

test("over HTTP: create, join and quick never answer 409, and the game server's left call frees the member", async () => {
  const env = {
    SESSION_SECRET: "s".repeat(32),
    TICKET_SECRET: "t".repeat(32),
    GAME_SERVER_SECRET: "g".repeat(32),
    DISCORD_MODE: "off",
    GUEST_SIGN_IN: "1",
    NODE_ENV: "production",
  };
  const clock = { now: 5_000_000 };
  const registry = new GameServerRegistry(60 * MINUTE, () => clock.now);
  const config = loadConfig(env);
  const app = buildApp({ config, store: new MemoryStore(), discord: new OffDiscord(), registry, now: () => clock.now });
  const auth = { authorization: `Bearer ${config.gameServerSecret}` };
  await app.inject({
    method: "POST",
    url: "/internal/servers/heartbeat",
    headers: auth,
    payload: { id: "gs", url: "wss://gs.example", activityPath: "/gs", capacity: 3, matchIds: [] },
  });
  const guest = async (name: string) => {
    const response = await app.inject({ method: "POST", url: "/auth/guest", payload: { name } });
    return { authorization: `Bearer ${response.json().token}` };
  };
  const call = (method: "GET" | "POST", url: string, headers: object, payload?: object) => app.inject({ method, url, headers, payload });
  const [ann, bo] = [await guest("Ann"), await guest("Bo")];

  const first = (await call("POST", "/lobbies", ann, {})).json();
  assert.equal((await call("POST", "/lobbies", ann, {})).statusCode, 201); // her old lobby is gone, not a 409
  assert.equal((await call("GET", `/lobbies/${first.id}`, ann)).statusCode, 404);
  const night = (await call("POST", "/lobbies/quick", bo)).json();
  const joined = await call("POST", "/lobbies/join-by-code", ann, { code: night.code });
  assert.equal(joined.statusCode, 200); // a public night joined from her waiting lobby
  assert.equal((await call("POST", "/lobbies/quick", ann)).json().id, night.id);

  // The game server says Bo's seat is empty: he is out of the night and free to make another.
  const bound = await call("POST", `/internal/matches/${night.matchId}/left`, auth, { userId: night.members[0].userId });
  assert.equal(bound.statusCode, 204);
  assert.equal((await call("GET", `/lobbies/${night.id}`, bo)).statusCode, 403);
  assert.equal((await call("POST", "/lobbies", bo, {})).statusCode, 201);
  assert.equal((await call("POST", `/internal/matches/${night.matchId}/left`, { authorization: "Bearer nope" }, { userId: "x" })).statusCode, 401);
  await app.close();
});
