// A Guest account lasts (#1080): the guest credential signs a guest back in to the same account for 7 days after its last
// sign-in, a credential that is not ours or not in date gets a new guest, an account idle for 7 days is deleted with its
// saves, and a Discord account never is. The backend's clock is a number the test moves by hand.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp, GUEST_ID_PREFIX, GUEST_TTL_SECONDS, GUESTS_IN_ALL_PER_HOUR, GUESTS_PER_ADDRESS_PER_HOUR, sweepIdleGuests } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { StubDiscord } from "../src/discord.ts";
import { PgStore } from "../src/pg-store.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore, type Store } from "../src/store.ts";
import { signToken, verifyToken } from "../src/tokens.ts";

const DAY = 24 * 60 * 60_000;
const secrets = { SESSION_SECRET: "s".repeat(32), TICKET_SECRET: "t".repeat(32), GAME_SERVER_SECRET: "g".repeat(32) };
const config = loadConfig({ ...secrets, DISCORD_MODE: "stub", ALLOW_STUB_SIGN_IN: "1", GUEST_SIGN_IN: "1" });

interface Answer {
  status: number;
  token: string;
  guestToken: string;
  guestExpiresIn: number;
  returning: boolean;
  user: { id: string; name: string; guest: boolean };
}

function platform(store: Store = new MemoryStore()) {
  const clock = { now: Date.UTC(2026, 10, 4, 12) };
  const app = buildApp({ config, store, discord: new StubDiscord(), registry: new GameServerRegistry(), now: () => clock.now });
  let nextAddress = 0;
  /** A guest signs in: from a new address each time unless one is given; `guestToken` is the credential it kept. */
  const signIn = async (body: { name?: string; guestToken?: string } = {}, address?: string): Promise<Answer> => {
    nextAddress++;
    const from = address ?? `10.1.${Math.floor(nextAddress / 250)}.${nextAddress % 250}`;
    const response = await app.inject({ method: "POST", url: "/auth/guest", payload: body, remoteAddress: from });
    return { status: response.statusCode, ...response.json() } as Answer;
  };
  const auth = (answer: Answer) => ({ authorization: `Bearer ${answer.token}`, "content-type": "application/json" });
  const putSave = (answer: Answer, data: object) =>
    app.inject({ method: "PUT", url: "/saves/challenges", headers: auth(answer), payload: { revision: 0, schemaVersion: 1, data } });
  const getSave = (answer: Answer) => app.inject({ method: "GET", url: "/saves/challenges", headers: auth(answer) });
  return { app, store, clock, signIn, putSave, getSave };
}

test("a guest signs back in with its credential: the same account, its own save, a fresh credential", async () => {
  const { app, clock, signIn, putSave, getSave } = platform();
  const first = await signIn({ name: "Ann" });
  assert.equal(first.status, 201);
  assert.equal(first.returning, false);
  assert.equal(first.guestExpiresIn, GUEST_TTL_SECONDS);
  assert.equal(GUEST_TTL_SECONDS, 7 * 24 * 3600);
  assert.equal((await putSave(first, { xp: 120 })).statusCode, 200);

  // The page was closed and opened a day later: the session is long gone, the credential was kept.
  clock.now += DAY;
  const second = await signIn({ guestToken: first.guestToken });
  assert.equal(second.status, 200);
  assert.equal(second.returning, true);
  assert.equal(second.user.id, first.user.id);
  assert.equal(second.user.guest, true);
  assert.deepEqual((await getSave(second)).json(), { revision: 1, schemaVersion: 1, data: { xp: 120 } });

  // The new credential is good for 7 days from this sign-in, not from the first.
  const claims = verifyToken(config.sessionSecret, "guest", second.guestToken, Math.floor(clock.now / 1000));
  assert.equal(claims?.sub, first.user.id);
  assert.equal(claims!.exp - claims!.iat, GUEST_TTL_SECONDS);
  assert.equal(claims!.iat, Math.floor(clock.now / 1000));
  await app.close();
});

test("each sign-in restarts the 7 days: an account visited every 5 days outlives 7", async () => {
  const { app, clock, signIn, putSave, getSave } = platform();
  let answer = await signIn({ name: "Ann" });
  const id = answer.user.id;
  await putSave(answer, { xp: 1 });
  for (let visit = 0; visit < 4; visit++) {
    clock.now += 5 * DAY;
    answer = await signIn({ guestToken: answer.guestToken });
    assert.equal(answer.user.id, id, `visit ${visit + 1} (day ${5 * (visit + 1)})`);
  }
  assert.equal((await getSave(answer)).statusCode, 200);
  await app.close();
});

test("the chosen name updates on sign-in, and a guest that gives none keeps its name", async () => {
  const { app, signIn } = platform();
  const first = await signIn({ name: "Ann" });
  assert.equal((await signIn({ guestToken: first.guestToken })).user.name, "Ann");
  assert.equal((await signIn({ guestToken: first.guestToken, name: "" })).user.name, "Ann");
  assert.equal((await signIn({ guestToken: first.guestToken, name: "sh1t" })).user.name, "Ann"); // not a usable name
  const renamed = await signIn({ guestToken: first.guestToken, name: "  Ann  Lee " });
  assert.equal(renamed.user.name, "Ann Lee");
  assert.equal(renamed.user.id, first.user.id);
  assert.equal((await signIn({ guestToken: renamed.guestToken })).user.name, "Ann Lee");
  await app.close();
});

test("a credential that is forged, expired, of another kind or of nobody gets a new guest, never another's account", async () => {
  const { app, store, clock, signIn, putSave, getSave } = platform();
  const victim = await signIn({ name: "Vic" });
  await putSave(victim, { xp: 999 });
  const nowSeconds = Math.floor(clock.now / 1000);

  const [header, payload, signature] = victim.guestToken.split(".") as [string, string, string];
  const swapped = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as Record<string, unknown>;
  const forgeries: Record<string, string> = {
    "signed with another secret": signToken("x".repeat(32), "guest", victim.user.id, GUEST_TTL_SECONDS, {}, nowSeconds),
    "the signature cut off": `${header}.${payload}.`,
    "a payload changed after it was signed": `${header}.${Buffer.from(JSON.stringify({ ...swapped, exp: nowSeconds + 10 * GUEST_TTL_SECONDS })).toString("base64url")}.${signature}`,
    "a session token": victim.token,
    "a ticket": signToken(config.ticketSecret, "ticket", victim.user.id, 60, {}, nowSeconds),
    "the bare account id": victim.user.id,
    garbage: "not.a.token",
    empty: "",
  };
  // A well-signed credential naming an account that is not a guest's, or that never existed.
  const discord = await store.upsertUser("42", "Dee", clock.now);
  forgeries["a signed credential of a Discord account"] = signToken(config.sessionSecret, "guest", discord.id, GUEST_TTL_SECONDS, {}, nowSeconds);
  forgeries["a signed credential of no account"] = signToken(config.sessionSecret, "guest", "00000000-0000-4000-8000-000000000000", GUEST_TTL_SECONDS, {}, nowSeconds);

  for (const [what, guestToken] of Object.entries(forgeries)) {
    const stranger = await signIn({ guestToken });
    assert.equal(stranger.status, 201, what);
    assert.equal(stranger.returning, false, what);
    assert.notEqual(stranger.user.id, victim.user.id, what);
    assert.notEqual(stranger.user.id, discord.id, what);
    assert.equal((await getSave(stranger)).statusCode, 404, `${what}: a new, empty account`);
  }

  // Expired: the credential itself runs out 7 days after it was signed, whatever the account says.
  clock.now += GUEST_TTL_SECONDS * 1000;
  const late = await signIn({ guestToken: victim.guestToken });
  assert.equal(late.returning, false);
  assert.notEqual(late.user.id, victim.user.id);

  // A credential is no session.
  assert.equal((await app.inject({ method: "GET", url: "/saves/profile", headers: { authorization: `Bearer ${victim.guestToken}` } })).statusCode, 401);
  assert.equal((await store.getUser(discord.id))?.name, "Dee");
  await app.close();
});

test("an account idle for 7 days is gone with its saves at its next sign-in, and one idle for 6 days is not", async () => {
  const { app, store, clock, signIn, putSave } = platform();
  const six = await signIn({ name: "Six" });
  const seven = await signIn({ name: "Seven" });
  await putSave(six, { xp: 6 });
  await putSave(seven, { xp: 7 });

  clock.now += 7 * DAY - 1; // 6 days 23 h 59 min 59.999 s: the credential and the account are in date
  const back = await signIn({ guestToken: six.guestToken });
  assert.equal(back.returning, true);
  assert.equal(back.user.id, six.user.id);
  assert.notEqual(await store.getSave(six.user.id, "challenges"), null);

  clock.now += 1; // 7 days to the millisecond since `seven` signed in
  const gone = await signIn({ guestToken: seven.guestToken });
  assert.equal(gone.returning, false);
  assert.notEqual(gone.user.id, seven.user.id);
  assert.equal(await store.getUser(seven.user.id), null);
  assert.equal(await store.getSave(seven.user.id, "challenges"), null);
  await app.close();
});

test("the sweep deletes guests idle 7 days with their saves, keeps those idle 6, and never touches a Discord account", async () => {
  const { app, store, clock, signIn, putSave } = platform();
  const old = await signIn({ name: "Old" });
  const recent = await signIn({ name: "Recent" });
  const discord = await store.upsertUser("77", "Dee", clock.now);
  await putSave(old, { xp: 1 });
  await putSave(recent, { xp: 2 });
  await store.putSave(discord.id, "profile", { schemaVersion: 1, data: { xp: 3 } }, 0);

  clock.now += 1 * DAY;
  await signIn({ guestToken: recent.guestToken }); // `recent` signs in on day 1, `old` and Dee on day 0
  clock.now += 6 * DAY - 1; // day 7 less a millisecond for `old`: nothing is 7 days idle yet
  assert.equal(await sweepIdleGuests(store, clock.now), 0);
  clock.now += 1; // `old` is 7 days idle; `recent` 6
  assert.equal(await sweepIdleGuests(store, clock.now), 1);
  assert.equal(await store.getUser(old.user.id), null);
  assert.equal(await store.getSave(old.user.id, "challenges"), null);
  assert.notEqual(await store.getSave(recent.user.id, "challenges"), null);

  clock.now += 400 * DAY; // a year on: every guest is idle, the Discord account is not a guest
  assert.equal(await sweepIdleGuests(store, clock.now), 1);
  assert.equal(await store.getUser(recent.user.id), null);
  assert.equal((await store.getUser(discord.id))?.name, "Dee");
  assert.deepEqual(await store.getSave(discord.id, "profile"), { revision: 1, schemaVersion: 1, data: { xp: 3 } });
  assert.equal(discord.discordId.startsWith(GUEST_ID_PREFIX), false);
  await app.close();
});

test("a Discord account does not expire: it signs in after a year to the same account and save", async () => {
  const { app, store, clock } = platform();
  const first = await app.inject({ method: "POST", url: "/auth/discord", payload: { code: "stub:7:ivy" } });
  const id = first.json().user.id as string;
  await store.putSave(id, "profile", { schemaVersion: 1, data: { xp: 5 } }, 0);
  clock.now += 365 * DAY;
  await sweepIdleGuests(store, clock.now);
  const again = await app.inject({ method: "POST", url: "/auth/discord", payload: { code: "stub:7:ivy" } });
  assert.equal(again.json().user.id, id);
  assert.equal((await store.getSave(id, "profile"))?.data.xp, 5);
  await app.close();
});

test("the guest limits still hold: one address 30 an hour (returning guests count), all addresses 2000 new accounts an hour", async () => {
  const { app, clock, signIn } = platform();
  const first = await signIn({ name: "Ann" }, "9.9.9.9");
  for (let i = 1; i < GUESTS_PER_ADDRESS_PER_HOUR; i++) assert.equal((await signIn({ guestToken: first.guestToken }, "9.9.9.9")).status, 200);
  const refused = await signIn({ guestToken: first.guestToken }, "9.9.9.9"); // the 31st, with a good credential
  assert.equal(refused.status, 429);
  assert.equal((refused as unknown as { error: string }).error, "too_many_guests");
  assert.equal((await signIn({}, "9.9.9.9")).status, 429); // and without one
  clock.now += 60 * 60_000;
  assert.equal((await signIn({ guestToken: first.guestToken }, "9.9.9.9")).status, 200); // the hour passed

  // All addresses together: new accounts stop at the limit, and a guest who is back is not turned away by it.
  for (let i = 0; i < GUESTS_IN_ALL_PER_HOUR; i++) assert.equal((await signIn({}, `20.${i >> 8}.${i & 255}.1`)).status, 201, `new guest ${i + 1}`);
  assert.equal((await signIn({}, "30.0.0.1")).status, 429);
  assert.equal((await signIn({ guestToken: first.guestToken }, "30.0.0.2")).status, 200);
  await app.close();
});

test("guest sign-in off still answers 404, credential or not", async () => {
  const off = loadConfig({ ...secrets, DISCORD_MODE: "stub", ALLOW_STUB_SIGN_IN: "1" });
  const app = buildApp({ config: off, store: new MemoryStore(), discord: new StubDiscord(), registry: new GameServerRegistry() });
  const response = await app.inject({ method: "POST", url: "/auth/guest", payload: { guestToken: "x" } });
  assert.equal(response.statusCode, 404);
  await app.close();
});

// ---- Postgres: the same rules against the real store, when a database is given (TEST_DATABASE_URL)

const databaseUrl = process.env.TEST_DATABASE_URL;

test("Postgres keeps when an account last signed in, deletes idle guests with their saves and leaves the others", { skip: !databaseUrl }, async () => {
  const { default: pg } = await import("pg");
  const pool = new pg.Pool({ connectionString: databaseUrl });
  const schema = `guests_${Date.now()}`;
  try {
    // A throwaway schema holding the tables as they were before `last_seen`: connecting adds the column to what is there.
    await pool.query(`CREATE SCHEMA ${schema}`);
    await pool.query(`CREATE TABLE ${schema}.users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), discord_id text NOT NULL UNIQUE, name text NOT NULL, created_at timestamptz NOT NULL DEFAULT now())`);
    await pool.query(`INSERT INTO ${schema}.users (discord_id, name) VALUES ('guest:legacy', 'Legacy')`);
    const url = new URL(databaseUrl!);
    url.searchParams.set("options", `-c search_path=${schema}`);
    const store = await PgStore.connect(url.toString());
    try {
      // The account made before the column counts as seen when the column was added (now), not as seen in 1970.
      const legacyId = (await pool.query(`SELECT id FROM ${schema}.users WHERE discord_id = 'guest:legacy'`)).rows[0].id as string;
      assert.ok(Math.abs(((await store.getUser(legacyId))?.lastSeen ?? 0) - Date.now()) < 60_000);
      await store.deleteUser(legacyId);

      const t0 = Date.UTC(2026, 10, 4, 12);
      const old = await store.upsertUser("guest:old", "Old", t0);
      const recent = await store.upsertUser("guest:recent", "Recent", t0 + DAY);
      const discord = await store.upsertUser("123456789", "Dee", t0);
      assert.equal(old.lastSeen, t0);
      await store.putSave(old.id, "profile", { schemaVersion: 1, data: { xp: 1 } }, 0);
      await store.putSave(discord.id, "profile", { schemaVersion: 1, data: { xp: 2 } }, 0);

      assert.equal((await store.upsertUser("guest:recent", "Renamed", t0 + 2 * DAY)).id, recent.id); // same account, seen again
      assert.equal((await store.getUser(recent.id))?.lastSeen, t0 + 2 * DAY);
      assert.equal(await sweepIdleGuests(store, t0 + 7 * DAY - 1), 0);
      assert.equal(await sweepIdleGuests(store, t0 + 7 * DAY), 1);
      assert.equal(await store.getUser(old.id), null);
      assert.equal(await store.getSave(old.id, "profile"), null);
      assert.notEqual(await store.getUser(recent.id), null);
      assert.equal((await store.getUser(discord.id))?.name, "Dee");
      assert.notEqual(await store.getSave(discord.id, "profile"), null);

      await store.deleteUser(recent.id);
      assert.equal(await store.getUser(recent.id), null);
    } finally {
      await store.close();
    }
  } finally {
    await pool.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
    await pool.end();
  }
});
