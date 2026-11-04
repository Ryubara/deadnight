// Permanent progression on the backend: the profile slot, the game server's round reports, the XP clamp and the
// ticket's claims (docs/design/progression.md#storage-and-trust). Every clock is one the test moves by hand.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { buildApp, GUEST_TTL_SECONDS, sweepIdleGuests } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { StubDiscord } from "../src/discord.ts";
import { PgStore } from "../src/pg-store.ts";
import {
  FIRST_GAME_OF_THE_DAY_XP,
  MAX_LEVEL,
  NIGHT_CAP,
  OPENING_NIGHT_XP,
  SOLO_WINDOW_MS,
  SOLO_XP_PER_MINUTE,
  TIER_COSTS,
  dayNumber,
  iconOf,
  levelOf,
} from "../src/progression.ts";
import { api, connect, signIn } from "../src/client.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { startStubGameServer } from "../src/stub-gameserver.ts";
import { DuplicateLedger, MemoryStore, RevisionConflict, type Store } from "../src/store.ts";

const MINUTE = 60_000;
const DAY = 86_400_000;
const GAME_SECRET = "g".repeat(32);
const env = {
  SESSION_SECRET: "s".repeat(32),
  TICKET_SECRET: "t".repeat(32),
  GAME_SERVER_SECRET: GAME_SECRET,
  DISCORD_MODE: "stub",
  ALLOW_STUB_SIGN_IN: "1",
  GUEST_SIGN_IN: "1",
};
/**
 * Where the tests' clock starts: an hour and a bit after now, so a session signed in (its token is stamped by the real
 * clock) began more than the clamp's window ago. A test that counts from the session's start sets the clock by `at`.
 */
const T0 = Date.now() + 61 * MINUTE;

const profile = (over: Record<string, unknown> = {}) => ({ xp: 0, equipped: {}, done: [], opening_night: false, bonus_day: -1, ...over });
const envelope = (revision: number, data: unknown, schemaVersion = 1) => ({ revision, schemaVersion, data });

interface Player {
  token: string;
  id: string;
  headers: Record<string, string>;
}

/** The backend with a clock the test moves (`clock.now`), a store (memory unless given) and helpers for who signs in. */
async function backend(store: Store = new MemoryStore()) {
  const clock = { now: T0 };
  const app = buildApp({
    config: loadConfig(env),
    store,
    discord: new StubDiscord(),
    registry: new GameServerRegistry(),
    now: () => clock.now,
  });
  const header = (token: string) => ({ authorization: `Bearer ${token}`, "content-type": "application/json" });
  const signIn = (r: { json(): { token: string; user: { id: string } } }): Player => ({ token: r.json().token, id: r.json().user.id, headers: header(r.json().token) });
  const discord = async (id: number, name: string): Promise<Player> =>
    signIn(await app.inject({ method: "POST", url: "/auth/discord", payload: { code: `stub:${id}:${name}` } }));
  const guest = async (name = "visitor"): Promise<Player> => signIn(await app.inject({ method: "POST", url: "/auth/guest", payload: { name } }));
  const put = (who: Player, body: unknown, slot = "profile") => app.inject({ method: "PUT", url: `/saves/${slot}`, headers: who.headers, payload: body as object });
  const get = (who: Player, slot = "profile") => app.inject({ method: "GET", url: `/saves/${slot}`, headers: who.headers });
  const report = (matchId: string, body: unknown, secret: string | null = GAME_SECRET) =>
    app.inject({
      method: "POST",
      url: `/internal/matches/${matchId}/report`,
      headers: secret === null ? {} : { authorization: `Bearer ${secret}` },
      payload: body as object,
    });
  /** A started lobby of these players, and the claims of each one's ticket. */
  const ticketClaims = async (host: Player, ...others: Player[]) => {
    await app.inject({ method: "POST", url: "/internal/servers/heartbeat", headers: { authorization: `Bearer ${GAME_SECRET}` }, payload: { id: "gs", url: "ws://gs", activityPath: "/gs", capacity: 4 } });
    const lobby = (await app.inject({ method: "POST", url: "/lobbies", headers: host.headers, payload: {} })).json();
    for (const other of others) await app.inject({ method: "POST", url: "/lobbies/join-by-code", headers: other.headers, payload: { code: lobby.code } });
    const started = await app.inject({ method: "POST", url: `/lobbies/${lobby.id}/start`, headers: host.headers, payload: {} });
    assert.equal(started.statusCode, 200, started.body);
    return async (who: Player) => {
      const t = (await app.inject({ method: "POST", url: `/lobbies/${lobby.id}/ticket`, headers: who.headers, payload: {} })).json().ticket as string;
      return JSON.parse(Buffer.from(t.split(".")[1]!, "base64url").toString("utf8")) as Record<string, unknown>;
    };
  };
  /** Puts the clock `minutes` after the moment this player's session began (the token's `iat`). */
  const at = (who: Player, minutes: number) => {
    const iat = JSON.parse(Buffer.from(who.token.split(".")[1]!, "base64url").toString("utf8")).iat as number;
    clock.now = iat * 1000 + minutes * MINUTE;
  };
  const today = () => dayNumber(clock.now);
  return { app, store, clock, discord, guest, put, get, report, ticketClaims, at, today };
}

const seat = (userId: string, xp: number, extra: Record<string, unknown> = {}) => ({ userId, xp, ...extra });
const roundReport = (n: number, seats: unknown[], kind = "round") => ({ kind, round: n, seats });
const profileOf = async (api: Awaited<ReturnType<typeof backend>>, who: Player) => (await api.get(who)).json();

// ---- the curve and the ticket's claims

test("the level curve and the night's numbers are the game's own (read from the GDScript)", () => {
  const curve = readFileSync(new URL("../../../game/gameplay/progression/level_curve.gd", import.meta.url), "utf8");
  const rules = readFileSync(new URL("../../../game/gameplay/progression/xp_rules.gd", import.meta.url), "utf8");
  const costs = /const TIER_COSTS: Array\[int\] = \[([^\]]+)\]/.exec(curve)![1]!.split(",").map((n) => Number(n.trim()));
  assert.deepEqual(costs, [...TIER_COSTS]);
  assert.equal(Number(/const MAX_LEVEL := (\d+)/.exec(curve)![1]), MAX_LEVEL);
  assert.equal(Number(/const NIGHT_CAP := (\d+)/.exec(rules)![1]), NIGHT_CAP);
  assert.equal(Number(/const OPENING_NIGHT_XP := (\d+)/.exec(rules)![1]), OPENING_NIGHT_XP);
  assert.equal(Number(/const FIRST_GAME_OF_THE_DAY_XP := (\d+)/.exec(rules)![1]), FIRST_GAME_OF_THE_DAY_XP);
  const profileGd = readFileSync(new URL("../../../game/gameplay/progression/profile.gd", import.meta.url), "utf8");
  assert.equal(Number(/const SCHEMA_VERSION := (\d+)/.exec(profileGd)![1]), 1); // the version the backend accepts for the slot
});

test("a level is derived from raw XP, with the edges of the curve", () => {
  assert.equal(levelOf(0), 1);
  assert.equal(levelOf(84), 1);
  assert.equal(levelOf(85), 2);
  assert.equal(levelOf(425), 6); // five levels of 85
  assert.equal(levelOf(18_009), 54);
  assert.equal(levelOf(18_010), 55); // the whole curve is 18,010 XP
  assert.equal(levelOf(10_000_000), 55); // XP past the top stays on the top
  assert.equal(iconOf(1), "level_01");
  assert.equal(iconOf(55), "level_55");
});

test("a ticket carries the seat's level, icon and XP from the stored profile; a new account is level 1", async () => {
  const api = await backend();
  const host = await api.discord(1, "ana");
  const friend = await api.discord(2, "ben");
  assert.equal((await api.put(host, envelope(0, profile({ xp: 300 })))).statusCode, 200);
  const claims = await api.ticketClaims(host, friend);
  const a = await claims(host);
  assert.deepEqual([a.level, a.icon, a.xp], [4, "level_04", 300]); // 85 + 170 = 255 begins level 4
  const b = await claims(friend);
  assert.deepEqual([b.level, b.icon, b.xp], [1, "level_01", 0]);
  await api.app.close();
});

test("a profile that does not read gives level 1 in the ticket, it never breaks a seat", async () => {
  const store = new MemoryStore();
  const api = await backend(store);
  const host = await api.discord(1, "ana");
  await store.putSave(host.id, "profile", { schemaVersion: 1, data: { xp: "lots" } }, 0);
  const a = await (await api.ticketClaims(host))(host);
  assert.deepEqual([a.level, a.icon, a.xp], [1, "level_01", 0]);
  await api.app.close();
});

test("the lobby's member list carries each member's level and icon, a Guest's too, and follows a report", async () => {
  const api = await backend();
  const host = await api.discord(1, "ana");
  const visitor = await api.guest("visitor");
  assert.equal((await api.put(host, envelope(0, profile({ xp: 300 })))).statusCode, 200);
  const lobby = (await api.app.inject({ method: "POST", url: "/lobbies", headers: host.headers, payload: {} })).json();
  const joined = await api.app.inject({ method: "POST", url: "/lobbies/join-by-code", headers: visitor.headers, payload: { code: lobby.code } });
  assert.equal(joined.statusCode, 200, joined.body);
  const levels = (view: { members: { userId: string; level?: number; icon?: string }[] }) => view.members.map((m) => [m.level, m.icon]);
  assert.deepEqual(levels(joined.json()), [[4, "level_04"], [1, "level_01"]]);
  // The tag in the lobby is the tag in the ticket: a report that pays the guest 85 XP moves it up the next time the list is read.
  assert.equal((await api.report("m1", roundReport(1, [seat(visitor.id, 85)]))).statusCode, 200);
  const again = (await api.app.inject({ method: "GET", url: `/lobbies/${lobby.id}`, headers: host.headers })).json();
  assert.deepEqual(levels(again), [[4, "level_04"], [2, "level_02"]]);
  await api.app.close();
});

// ---- the game server's round report

test("a round report pays once, and posting it again changes nothing", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  const first = await api.report("m1", roundReport(1, [seat(ana.id, 40)]));
  assert.equal(first.statusCode, 200);
  assert.deepEqual(first.json().seats, [{ userId: ana.id, status: "paid", credited: 40, openingNight: false, firstGameOfTheDay: false, xp: 40, level: 1 }]);
  const stored = await profileOf(api, ana);
  assert.deepEqual([stored.revision, stored.data.xp], [1, 40]);

  const retry = await api.report("m1", roundReport(1, [seat(ana.id, 40)]));
  assert.deepEqual(retry.json().seats[0], { userId: ana.id, status: "duplicate", credited: 40, openingNight: false, firstGameOfTheDay: false, xp: 40, level: 1 });
  const same = await profileOf(api, ana);
  assert.deepEqual([same.revision, same.data.xp], [1, 40]); // not a byte moved

  // The same round with a different amount is still the same report: the key decides, not the number.
  assert.equal((await api.report("m1", roundReport(1, [seat(ana.id, 900)]))).json().seats[0].status, "duplicate");
  assert.equal((await profileOf(api, ana)).data.xp, 40);

  // The next round, the night's end and another match each pay their own.
  assert.equal((await api.report("m1", roundReport(2, [seat(ana.id, 60)]))).json().seats[0].credited, 60);
  assert.equal((await api.report("m1", roundReport(2, [seat(ana.id, 5)], "night"))).json().seats[0].credited, 5);
  assert.equal((await api.report("m2", roundReport(1, [seat(ana.id, 10)]))).json().seats[0].credited, 10);
  const end = await profileOf(api, ana);
  assert.deepEqual([end.data.xp, end.revision], [115, 4]); // one write a report, never one a kill
  await api.app.close();
});

test("a report with several seats pays each seat, and a retry finishes only what was not paid", async () => {
  const store = new MemoryStore();
  const api = await backend(store);
  const [ana, ben, cy] = [await api.discord(1, "ana"), await api.discord(2, "ben"), await api.discord(3, "cy")];
  // Ana was paid by an earlier post that died halfway; the whole report comes again.
  await api.report("m1", roundReport(1, [seat(ana.id, 30)]));
  const all = await api.report("m1", roundReport(1, [seat(ana.id, 30), seat(ben.id, 20), seat(cy.id, 0)]));
  assert.deepEqual(all.json().seats.map((s: { status: string; credited: number }) => [s.status, s.credited]), [["duplicate", 30], ["paid", 20], ["paid", 0]]);
  assert.equal((await profileOf(api, ana)).data.xp, 30);
  assert.equal((await profileOf(api, ben)).data.xp, 20);
  await api.app.close();
});

test("two identical reports at once pay once", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  const both = await Promise.all([api.report("m1", roundReport(1, [seat(ana.id, 40)])), api.report("m1", roundReport(1, [seat(ana.id, 40)]))]);
  assert.deepEqual(both.map((r) => r.json().seats[0].status).sort(), ["duplicate", "paid"]);
  assert.equal((await profileOf(api, ana)).data.xp, 40);
  await api.app.close();
});

test("only a server the platform started may post a report", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  const body = roundReport(1, [seat(ana.id, 40)]);
  assert.equal((await api.report("m1", body, null)).statusCode, 401);
  assert.equal((await api.report("m1", body, "x".repeat(32))).statusCode, 401);
  // A player's own session is not a game server's secret: no client can post XP for a night.
  const asPlayer = await api.app.inject({ method: "POST", url: "/internal/matches/m1/report", headers: ana.headers, payload: body });
  assert.equal(asPlayer.statusCode, 401);
  assert.equal((await api.get(ana)).statusCode, 404); // nothing was paid
  await api.app.close();
});

test("a report is checked: its kind, a negative or huge amount, a bad day and too many lines are refused", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  const refused = async (body: unknown) => (await api.report("m1", body)).statusCode;
  assert.equal(await refused(roundReport(1, [seat(ana.id, 5)], "kill")), 400);
  assert.equal(await refused(roundReport(1, [seat(ana.id, -5)])), 400);
  assert.equal(await refused(roundReport(1, [seat(ana.id, NIGHT_CAP + 1)])), 400);
  assert.equal(await refused(roundReport(1, [seat(ana.id, 1.5)])), 400);
  assert.equal(await refused(roundReport(-1, [seat(ana.id, 5)])), 400);
  assert.equal(await refused(roundReport(1, [seat(ana.id, 5, { lines: { "BAD KEY": 1 } })])), 400);
  assert.equal(await refused({ kind: "round", round: 1 }), 400);
  assert.equal((await api.get(ana)).statusCode, 404);
  assert.equal(await refused(roundReport(1, [seat(ana.id, 5, { lines: { points: 12, boards: 3 } })])), 200);
  assert.equal((await api.store.getLedgerEntry(ana.id, "m1", "round", 1))?.reason.lines instanceof Object, true);
  await api.app.close();
});

test("a night pays one seat at most the night's cap, every report together", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  assert.equal((await api.report("m1", roundReport(1, [seat(ana.id, 1000)]))).json().seats[0].credited, 1000);
  assert.equal((await api.report("m1", roundReport(2, [seat(ana.id, 800)]))).json().seats[0].credited, 500); // cut at 1,500
  assert.equal((await api.report("m1", roundReport(3, [seat(ana.id, 50)]))).json().seats[0].credited, 0);
  assert.equal((await profileOf(api, ana)).data.xp, NIGHT_CAP);
  // The cap is for the night: the next match pays again.
  assert.equal((await api.report("m2", roundReport(1, [seat(ana.id, 70)]))).json().seats[0].credited, 70);
  assert.equal(await api.store.ledgerTotal(ana.id, "m1"), NIGHT_CAP);
  await api.app.close();
});

test("a report for an account that is not there pays nobody and does not stop the other seats", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  const r = await api.report("m1", roundReport(1, [seat("00000000-0000-4000-8000-000000000000", 50), seat(ana.id, 50)]));
  assert.deepEqual(r.json().seats.map((s: { status: string }) => s.status), ["unknown_user", "paid"]);
  await api.app.close();
});

/** A Guest with a paid report expires after 7 days (#1085): the account, its save and its ledger lines go, in either store (#1103). */
async function expiredGuestLeavesNoLedger(store: Store, clockStart: number) {
  const api = await backend(store);
  const guest = await api.guest("visitor");
  const matchId = `expire-${clockStart}`;
  const paid = await api.report(matchId, roundReport(1, [seat(guest.id, 40)]));
  assert.equal(paid.json().seats[0].status, "paid");
  await api.store.putSave(guest.id, "profile", { schemaVersion: 1, data: profile({ xp: 41 }) }, 1, { userId: guest.id, matchId: "", kind: "solo", round: 2, xp: 1, reason: {}, at: T0 });
  assert.equal(await api.store.ledgerTotal(guest.id, matchId), 40);
  assert.notEqual(await api.store.getLedgerEntry(guest.id, matchId, "round", 1), null);
  assert.equal(await api.store.lastLedgerAt(guest.id, "solo"), T0);

  assert.equal(await sweepIdleGuests(api.store, T0 + GUEST_TTL_SECONDS * 1000 + 1), 1);
  assert.equal(await api.store.getUser(guest.id), null);
  assert.equal(await api.store.getLedgerEntry(guest.id, matchId, "round", 1), null);
  assert.equal(await api.store.ledgerTotal(guest.id, matchId), 0);
  assert.equal(await api.store.lastLedgerAt(guest.id, "solo"), null);

  // The game server posts the same report again after the account is gone: it pays nobody and writes no line.
  const late = await api.report(matchId, roundReport(1, [seat(guest.id, 40)]));
  assert.equal(late.json().seats[0].status, "unknown_user");
  assert.equal(await api.store.getLedgerEntry(guest.id, matchId, "round", 1), null);
  assert.equal(await api.store.getSave(guest.id, "profile"), null);
  await api.app.close();
}

test("a Guest that expires after a paid report leaves no ledger lines, and a late report pays nobody", async () => {
  await expiredGuestLeavesNoLedger(new MemoryStore(), 1);
});

test("a report adds on top of the account's own latest, and the client's stale revision is read again", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  assert.equal((await api.put(ana, envelope(0, profile({ xp: 100 })))).json().revision, 1);
  await api.report("m1", roundReport(1, [seat(ana.id, 40)])); // revision 2, xp 140
  // The client still holds revision 1 with 100 XP: its write is stale, not lost and not merged.
  api.clock.now += MINUTE;
  const stale = await api.put(ana, envelope(1, profile({ xp: 130 })));
  assert.deepEqual([stale.statusCode, stale.json()], [409, { error: "revision_conflict", revision: 2 }]);
  // It reads the account's own latest and sends its change on top of that.
  const latest = await profileOf(api, ana);
  assert.equal(latest.data.xp, 140);
  const again = await api.put(ana, envelope(latest.revision, profile({ xp: 160 })));
  assert.deepEqual([again.statusCode, again.json().revision, again.json().data.xp], [200, 3, 160]);
  await api.app.close();
});

test("the first game of the day and the opening night are paid once, on the backend's own say", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  const TODAY = api.today();
  const first = (await api.report("m1", roundReport(1, [seat(ana.id, 25, { openingNight: true, bonusDay: TODAY })]))).json().seats[0];
  assert.deepEqual([first.credited, first.openingNight, first.firstGameOfTheDay], [25 + OPENING_NIGHT_XP + FIRST_GAME_OF_THE_DAY_XP, true, true]);
  let stored = (await profileOf(api, ana)).data;
  assert.deepEqual([stored.opening_night, stored.bonus_day, stored.xp], [true, TODAY, 175]);

  // Another match the same day: nothing more for either, however the server asks.
  const second = (await api.report("m2", roundReport(1, [seat(ana.id, 25, { openingNight: true, bonusDay: TODAY })]))).json().seats[0];
  assert.deepEqual([second.credited, second.openingNight, second.firstGameOfTheDay], [25, false, false]);

  // Tomorrow's first game pays again, the opening night never does.
  api.clock.now += DAY;
  const next = (await api.report("m3", roundReport(1, [seat(ana.id, 25, { openingNight: true, bonusDay: TODAY + 1 })]))).json().seats[0];
  assert.deepEqual([next.credited, next.openingNight, next.firstGameOfTheDay], [25 + FIRST_GAME_OF_THE_DAY_XP, false, true]);
  stored = (await profileOf(api, ana)).data;
  assert.deepEqual([stored.bonus_day, stored.xp], [TODAY + 1, 175 + 25 + 25 + 100]);

  // A day that is not close to the backend's date, or one already paid or older, is no first game.
  const far = (await api.report("m4", roundReport(1, [seat(ana.id, 10, { bonusDay: TODAY + 40 })]))).json().seats[0];
  assert.deepEqual([far.credited, far.firstGameOfTheDay], [10, false]);
  const old = (await api.report("m5", roundReport(1, [seat(ana.id, 10, { bonusDay: TODAY })]))).json().seats[0];
  assert.deepEqual([old.credited, old.firstGameOfTheDay], [10, false]);
  assert.equal((await profileOf(api, ana)).data.bonus_day, TODAY + 1);
  await api.app.close();
});

test("a report keeps the finished challenges of the profile, without losing earlier ones", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  await api.report("m1", roundReport(1, [seat(ana.id, 10, { done: ["daily_kills", "order_a"] })]));
  await api.report("m1", roundReport(2, [seat(ana.id, 10, { done: ["order_a", "order_b"] })]));
  assert.deepEqual((await profileOf(api, ana)).data.done, ["daily_kills", "order_a", "order_b"]);
  await api.app.close();
});

// ---- the signed-in solo client's write, and the clamp

test("a solo write adds at most 120 XP for each minute since the last write; the edge is accepted, one more is not", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  api.at(ana, 2); // two minutes since the session began
  const edge = 2 * SOLO_XP_PER_MINUTE;
  const over = await api.put(ana, envelope(0, profile({ xp: edge + 1 })));
  assert.deepEqual([over.statusCode, over.json()], [422, { error: "implausible_progress", added: edge + 1, allowed: edge, perMinute: SOLO_XP_PER_MINUTE }]);
  assert.equal((await api.get(ana)).statusCode, 404); // nothing was stored
  assert.equal((await api.put(ana, envelope(0, profile({ xp: edge })))).statusCode, 200);

  // The clock restarts at each write: one minute later, 120 more and not 121.
  api.clock.now += MINUTE;
  assert.equal((await api.put(ana, envelope(1, profile({ xp: edge + 121 })))).json().error, "implausible_progress");
  const ok = await api.put(ana, envelope(1, profile({ xp: edge + 120 })));
  assert.deepEqual([ok.statusCode, ok.json().revision], [200, 2]);

  // Waiting makes a refused write acceptable: a refusal is "too fast", not "never".
  assert.equal((await api.put(ana, envelope(2, profile({ xp: edge + 120 + 360 })))).statusCode, 422);
  api.clock.now += 3 * MINUTE;
  assert.equal((await api.put(ana, envelope(2, profile({ xp: edge + 120 + 360 })))).statusCode, 200);
  await api.app.close();
});

test("a silence is not banked: a day away allows an hour's worth, so the long-run rate is still the cap", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  api.at(ana, 5);
  assert.equal((await api.put(ana, envelope(0, profile({ xp: 100 })))).statusCode, 200);
  api.clock.now += DAY;
  const window = (SOLO_WINDOW_MS / MINUTE) * SOLO_XP_PER_MINUTE; // 7,200
  assert.equal((await api.put(ana, envelope(1, profile({ xp: 100 + window + 1 })))).json().error, "implausible_progress");
  assert.equal((await api.put(ana, envelope(1, profile({ xp: 100 + window })))).statusCode, 200);
  await api.app.close();
});

test("a first write counts from the session's start, and a new account cannot start with a pile of XP", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  api.at(ana, 0);
  const r = await api.put(ana, envelope(0, profile({ xp: 500 })));
  assert.deepEqual([r.statusCode, r.json().allowed], [422, 0]);
  api.at(ana, 1); // a minute in
  assert.equal((await api.put(ana, envelope(0, profile({ xp: SOLO_XP_PER_MINUTE })))).statusCode, 200);
  // Without a write for an hour the allowance is an hour's worth, no more, however long the session has been open.
  const late = await api.discord(2, "late");
  api.clock.now = T0 + 3 * DAY;
  assert.equal((await api.put(late, envelope(0, profile({ xp: 7201 })))).json().allowed, 7200);
  await api.app.close();
});

test("the opening night and the first game of the day widen one write by exactly their XP", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  api.at(ana, 1);
  const TODAY = api.today();
  const allowed = SOLO_XP_PER_MINUTE + OPENING_NIGHT_XP + FIRST_GAME_OF_THE_DAY_XP;
  const body = (xp: number) => envelope(0, profile({ xp, opening_night: true, bonus_day: TODAY }));
  assert.equal((await api.put(ana, body(allowed + 1))).json().allowed, allowed);
  assert.equal((await api.put(ana, body(allowed))).statusCode, 200);

  // Claimed already: the same flags again widen nothing.
  api.clock.now += MINUTE;
  assert.equal((await api.put(ana, envelope(1, profile({ xp: allowed + SOLO_XP_PER_MINUTE + 1, opening_night: true, bonus_day: TODAY })))).statusCode, 422);
  assert.equal((await api.put(ana, envelope(1, profile({ xp: allowed + SOLO_XP_PER_MINUTE, opening_night: true, bonus_day: TODAY })))).statusCode, 200);
  await api.app.close();
});

test("the first game's day is accepted once, within a day of the backend's date", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  api.at(ana, 1);
  const TODAY = api.today();
  for (const far of [TODAY + 2, TODAY - 2, TODAY + 400]) {
    const r = await api.put(ana, envelope(0, profile({ bonus_day: far })));
    assert.deepEqual([r.statusCode, r.json()], [422, { error: "implausible_day", bonus_day: far, today: TODAY }]);
  }
  assert.equal((await api.put(ana, envelope(0, profile({ bonus_day: TODAY + 1 })))).statusCode, 200); // a zone ahead of UTC
  // The day cannot go back to be paid again.
  const back = await api.put(ana, envelope(1, profile({ bonus_day: TODAY })));
  assert.deepEqual([back.statusCode, back.json()], [422, { error: "profile_regressed", field: "bonus_day" }]);
  await api.app.close();
});

test("a write cannot take anything away: XP, the opening night, a finished challenge", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  api.at(ana, 5);
  assert.equal((await api.put(ana, envelope(0, profile({ xp: 200, opening_night: true, done: ["a", "b"] })))).statusCode, 200);
  const field = async (data: Record<string, unknown>) => (await api.put(ana, envelope(1, profile(data)))).json();
  assert.deepEqual(await field({ xp: 199, opening_night: true, done: ["a", "b"] }), { error: "profile_regressed", field: "xp" });
  assert.deepEqual(await field({ xp: 200, opening_night: false, done: ["a", "b"] }), { error: "profile_regressed", field: "opening_night" });
  assert.deepEqual(await field({ xp: 200, opening_night: true, done: ["a"] }), { error: "profile_regressed", field: "done" });
  // What the client may change on its own: what it wears (and a finished challenge added).
  const worn = await api.put(ana, envelope(1, profile({ xp: 200, opening_night: true, done: ["a", "b", "c"], equipped: { card: "stub" } })));
  assert.deepEqual([worn.statusCode, worn.json().data.equipped], [200, { card: "stub" }]);
  await api.app.close();
});

test("a profile that does not read is refused, and so is a schema the backend does not know", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  api.at(ana, 1);
  const bad = async (data: unknown) => (await api.put(ana, envelope(0, data))).json();
  assert.deepEqual(await bad({ ...profile(), xp: -1 }), { error: "invalid_profile", field: "xp" });
  assert.deepEqual(await bad({ ...profile(), xp: 1.5 }), { error: "invalid_profile", field: "xp" });
  assert.deepEqual(await bad({ ...profile(), xp: "9" }), { error: "invalid_profile", field: "xp" });
  assert.deepEqual(await bad({ ...profile(), equipped: [] }), { error: "invalid_profile", field: "equipped" });
  assert.deepEqual(await bad({ ...profile(), done: [1] }), { error: "invalid_profile", field: "done" });
  assert.deepEqual(await bad({ ...profile(), opening_night: 1 }), { error: "invalid_profile", field: "opening_night" });
  assert.deepEqual(await bad({ ...profile(), bonus_day: -2 }), { error: "invalid_profile", field: "bonus_day" });
  assert.deepEqual(await bad({}), { error: "invalid_profile", field: "xp" });

  const unknown = await api.put(ana, envelope(0, profile(), 99));
  assert.deepEqual([unknown.statusCode, unknown.json().error, unknown.json().schemaVersion], [422, "unsupported_schema_version", 99]);
  assert.equal((await api.get(ana)).statusCode, 404);
  await api.app.close();
});

test("a solo write is a ledger line, and the clamp reads the last of them", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  api.at(ana, 3);
  await api.put(ana, envelope(0, profile({ xp: 90 })));
  assert.equal(await api.store.lastLedgerAt(ana.id, "solo"), api.clock.now);
  assert.deepEqual((await api.store.getLedgerEntry(ana.id, "", "solo", 1))?.xp, 90);
  // Equipping something adds no XP and no line, so it does not restart the clamp's clock.
  api.clock.now += MINUTE;
  await api.put(ana, envelope(1, profile({ xp: 90, equipped: { frame: "brass" } })));
  assert.equal(await api.store.lastLedgerAt(ana.id, "solo"), api.clock.now - MINUTE);
  await api.app.close();
});

// ---- a Guest account is an account

test("a Guest account has a profile slot and earns like any other account", async () => {
  const api = await backend();
  const visitor = await api.guest("Vee");
  const friend = await api.discord(2, "ben");
  const TODAY = api.today();
  assert.equal((await api.get(visitor)).statusCode, 404);
  assert.equal((await api.report("m1", roundReport(1, [seat(visitor.id, 60, { openingNight: true, bonusDay: TODAY })]))).json().seats[0].status, "paid");
  let stored = await profileOf(api, visitor);
  assert.deepEqual([stored.data.xp, stored.data.opening_night, stored.data.bonus_day], [60 + 150, true, TODAY]);

  // The same rules for its own writes: the clamp, the 409.
  api.at(visitor, 1);
  assert.equal((await api.put(visitor, envelope(0, profile({ xp: 500 })))).statusCode, 409);
  assert.equal((await api.put(visitor, envelope(1, { ...stored.data, xp: stored.data.xp + 121 }))).json().error, "implausible_progress");
  assert.equal((await api.put(visitor, envelope(1, { ...stored.data, xp: stored.data.xp + 120 }))).statusCode, 200);
  stored = await profileOf(api, visitor);
  const claims = await (await api.ticketClaims(visitor, friend))(visitor);
  assert.deepEqual([claims.level, claims.icon, claims.xp], [levelOf(stored.data.xp), iconOf(levelOf(stored.data.xp)), stored.data.xp]);
  assert.equal(levelOf(stored.data.xp), 4); // 330 XP
  await api.app.close();
});

test("the challenges slot is an ordinary save: the board's facts, a known schema, no clamp", async () => {
  const api = await backend();
  const ana = await api.discord(1, "ana");
  const board = { day: api.today(), lifetime: { kills: 400, rounds: 31 }, done_count: 3 };
  assert.equal((await api.put(ana, envelope(0, board), "challenges")).statusCode, 200);
  assert.deepEqual((await api.get(ana, "challenges")).json(), { revision: 1, schemaVersion: 1, data: board });
  assert.equal((await api.put(ana, envelope(1, board, 2), "challenges")).json().error, "unsupported_schema_version");
  assert.equal((await api.put(ana, envelope(0, board), "challenges")).statusCode, 409);
  await api.app.close();
});

// ---- end to end over real sockets: sign in, lobby, handoff, a round report from the game server, a better ticket

test("end to end: a player is handed a game server, the server reports a round, the next ticket carries the level", async () => {
  const config = loadConfig(env);
  const app = buildApp({ config, store: new MemoryStore(), discord: new StubDiscord(), registry: new GameServerRegistry() });
  const base = await app.listen({ host: "127.0.0.1", port: 0 });
  const gameServer = await startStubGameServer({
    id: "gs-progress",
    port: 0,
    ticketSecret: config.ticketSecret,
    publicUrl: "ws://127.0.0.1:0",
    activityPath: "/gs/progress",
    backendUrl: base,
    gameServerSecret: config.gameServerSecret,
  });
  try {
    await fetch(`${base}/internal/servers/heartbeat`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${config.gameServerSecret}` },
      body: JSON.stringify({ id: "gs-progress", url: `ws://127.0.0.1:${gameServer.port}`, activityPath: "/gs/progress", capacity: 2, matchIds: [] }),
    });
    const alice = await signIn(base, "stub:3001:alice");
    const lobby = await api.createLobby(base, alice, { maxPlayers: 2 });
    await api.start(base, alice, lobby.id);
    const first = await api.ticket(base, alice, lobby.id);
    const welcome = await connect(first.address.url, first.ticket);
    assert.deepEqual([welcome.level, welcome.icon, welcome.xp], [1, "level_01", 0]);

    // Round 1 ends: one post for the seat (never one per kill). The same post again pays nothing.
    const seats = [{ userId: alice.userId, xp: 300 }];
    const paid = (await gameServer.report(first.matchId, "round", 1, seats)) as { seats: { status: string }[] };
    const again = (await gameServer.report(first.matchId, "round", 1, seats)) as { seats: { status: string }[] };
    assert.deepEqual([paid.seats[0]!.status, again.seats[0]!.status], ["paid", "duplicate"]);

    const second = await api.ticket(base, alice, lobby.id);
    const welcomed = await connect(second.address.url, second.ticket);
    assert.deepEqual([welcomed.level, welcomed.icon, welcomed.xp], [4, "level_04", 300]);
    const saved = await fetch(`${base}/saves/profile`, { headers: { Authorization: `Bearer ${alice.token}` } });
    assert.equal(((await saved.json()) as { data: { xp: number } }).data.xp, 300);
  } finally {
    await gameServer.close();
    await app.close();
  }
});

// ---- Postgres: the same rules against the real store, when a database is given (TEST_DATABASE_URL)

const databaseUrl = process.env.TEST_DATABASE_URL;

test("Postgres: a report pays once, survives a restart and a retry after it pays nothing", { skip: !databaseUrl }, async () => {
  const first = await backend(await PgStore.connect(databaseUrl!));
  const ana = await first.discord(Date.now(), "pg-ana");
  const matchId = `pg-${Date.now()}`;
  const body = roundReport(1, [seat(ana.id, 40, { openingNight: true, bonusDay: first.today(), lines: { points: 4000 } })]);
  // Two posts of the same report at once: one pays, one is told it was paid.
  const both = await Promise.all([first.report(matchId, body), first.report(matchId, body)]);
  assert.deepEqual(both.map((r) => r.json().seats[0].status).sort(), ["duplicate", "paid"]);
  const before = (await first.get(ana)).json();
  assert.deepEqual([before.revision, before.data.xp], [1, 40 + OPENING_NIGHT_XP + FIRST_GAME_OF_THE_DAY_XP]);
  await first.app.close();
  await first.store.close();

  // A new process on a new connection: the profile and the ledger are what the database kept.
  const second = await backend(await PgStore.connect(databaseUrl!));
  assert.deepEqual((await second.get(ana)).json(), before);
  const retry = await second.report(matchId, body);
  assert.deepEqual([retry.json().seats[0].status, retry.json().seats[0].credited], ["duplicate", 190]);
  assert.deepEqual((await second.store.getLedgerEntry(ana.id, matchId, "round", 1))?.reason.lines, { points: 4000 });
  assert.deepEqual((await second.get(ana)).json(), before); // the retry changed nothing
  await second.app.close();
  await second.store.close();
});

test("Postgres: a ledger entry and its save are one step, and a stale revision or a duplicate leaves neither", { skip: !databaseUrl }, async () => {
  const store = await PgStore.connect(databaseUrl!);
  try {
    const user = await store.upsertUser(`stub:pg-ledger-${Date.now()}`, "pg");
    const entry = (round: number, xp: number) => ({ userId: user.id, matchId: "m", kind: "round" as const, round, xp, reason: { lines: { a: 1 } }, at: T0 });
    const data = (xp: number) => ({ xp, equipped: {}, done: [], opening_night: false, bonus_day: -1 });
    const one = await store.putSave(user.id, "profile", { schemaVersion: 1, data: data(10) }, 0, entry(1, 10));
    assert.equal(one.revision, 1);
    await assert.rejects(store.putSave(user.id, "profile", { schemaVersion: 1, data: data(20) }, 1, entry(1, 10)), DuplicateLedger);
    await assert.rejects(store.putSave(user.id, "profile", { schemaVersion: 1, data: data(99) }, 0, entry(2, 89)), RevisionConflict);
    assert.equal(await store.getLedgerEntry(user.id, "m", "round", 2), null); // the refused write left no line
    assert.equal(await store.ledgerTotal(user.id, "m"), 10);
    assert.equal((await store.getSave(user.id, "profile"))?.data.xp, 10);
    await store.putSave(user.id, "profile", { schemaVersion: 1, data: data(30) }, 1, { ...entry(1, 20), matchId: "", kind: "solo" });
    assert.equal(await store.ledgerTotal(user.id, "m"), 10); // a solo line is not the match's
    assert.equal(await store.lastLedgerAt(user.id, "solo"), T0);
    assert.equal(await store.lastLedgerAt(user.id, "nothing"), null);
  } finally {
    await store.close();
  }
});

test("Postgres: a Guest that expires after a paid report leaves no ledger lines, and a late report pays nobody", { skip: !databaseUrl }, async () => {
  const store = await PgStore.connect(databaseUrl!);
  try {
    await expiredGuestLeavesNoLedger(store, Date.now());
  } finally {
    await store.close();
  }
});
