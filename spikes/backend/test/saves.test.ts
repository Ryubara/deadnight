// The save format: an envelope `{revision, schemaVersion, data}`, a closed set of known versions, and a rule for
// numbers JSON cannot carry exactly (64-bit values).
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { StubDiscord } from "../src/discord.ts";
import { PgStore } from "../src/pg-store.ts";
import { findUnsafeNumber, SAVE_SCHEMA_VERSIONS } from "../src/saves.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore, RevisionConflict, type Store } from "../src/store.ts";

const env = {
  SESSION_SECRET: "s".repeat(32),
  TICKET_SECRET: "t".repeat(32),
  GAME_SERVER_SECRET: "g".repeat(32),
  DISCORD_MODE: "stub",
  ALLOW_STUB_SIGN_IN: "1",
};

/** The 64-bit RNG state of a rules snapshot, the value the issue is about: above 2^53, so a JSON number loses it. */
const BIG = "18446744073709551557";

async function saveApi(store: Store = new MemoryStore()) {
  const app = buildApp({ config: loadConfig(env), store, discord: new StubDiscord(), registry: new GameServerRegistry() });
  const signedIn = await app.inject({ method: "POST", url: "/auth/discord", payload: { code: "stub:7:ivy" } });
  const headers = { authorization: `Bearer ${signedIn.json().token}`, "content-type": "application/json" };
  return {
    app,
    /** Sends `body` exactly as written: JSON.stringify cannot write a 64-bit literal, a real client can. */
    put: (body: string, slot = "main") => app.inject({ method: "PUT", url: `/saves/${slot}`, headers, payload: body }),
    get: (slot = "main") => app.inject({ method: "GET", url: `/saves/${slot}`, headers }),
  };
}

test("a save is an envelope: the backend returns the revision, the schema version and the data", async () => {
  const { app, put, get } = await saveApi();
  const stored = await put('{"revision":0,"schemaVersion":1,"data":{"night":3}}');
  assert.deepEqual([stored.statusCode, stored.json()], [200, { revision: 1, schemaVersion: 1, data: { night: 3 } }]);
  assert.deepEqual((await get()).json(), { revision: 1, schemaVersion: 1, data: { night: 3 } });
  await app.close();
});

test("a save without a schemaVersion, or with one the backend does not know, is refused and changes nothing", async () => {
  const { app, put, get } = await saveApi();
  assert.equal((await put('{"revision":0,"data":{"night":1}}')).statusCode, 400); // no version
  assert.equal((await put('{"revision":0,"schemaVersion":0,"data":{}}')).statusCode, 400);

  const unknown = await put('{"revision":0,"schemaVersion":99,"data":{"night":1}}');
  assert.equal(unknown.statusCode, 422);
  assert.deepEqual(unknown.json(), { error: "unsupported_schema_version", supported: SAVE_SCHEMA_VERSIONS, schemaVersion: 99 });
  assert.equal((await get()).statusCode, 404); // nothing was stored
  await app.close();
});

test("a 64-bit value above 2^53 comes back unchanged as a string or as an opaque base64 blob", async () => {
  const { app, put, get } = await saveApi();
  const blob = Buffer.from([0x40, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xc5]).toString("base64"); // var_to_bytes stand-in
  const body = `{"revision":0,"schemaVersion":1,"data":{"rng":{"state":"${BIG}","inc":"1442695040888963407"},"wire":"${blob}"}}`;
  assert.equal((await put(body)).statusCode, 200);
  const read = (await get()).json();
  assert.deepEqual(read.data, { rng: { state: BIG, inc: "1442695040888963407" }, wire: blob });
  assert.equal(read.data.rng.state, BIG);
  assert.equal(BigInt(read.data.rng.state), 18446744073709551557n); // the string is the exact integer
  await app.close();
});

test("a 64-bit value sent as a JSON number is refused, not silently rounded", async () => {
  const { app, put, get } = await saveApi();
  // JSON.parse("18446744073709551557") is 18446744073709552000: the low digits are gone before the backend sees it.
  assert.equal(JSON.parse(BIG), 18446744073709552000);
  const bad = await put(`{"revision":0,"schemaVersion":1,"data":{"rng":{"state":${BIG}}}}`);
  assert.deepEqual([bad.statusCode, bad.json()], [422, { error: "unsafe_integer", path: "/rng/state" }]);
  const edge = await put('{"revision":0,"schemaVersion":1,"data":{"list":[1,9007199254740993]}}'); // 2^53 + 1
  assert.deepEqual(edge.json(), { error: "unsafe_integer", path: "/list/1" });
  assert.equal((await get()).statusCode, 404); // nothing was stored

  // The largest exact integer, ordinary floats and negatives are fine.
  const ok = await put('{"revision":0,"schemaVersion":1,"data":{"a":9007199254740991,"b":-9007199254740991,"c":0.1,"d":-3.5e10}}');
  assert.equal(ok.statusCode, 200);
  await app.close();
});

test("findUnsafeNumber finds the number wherever it is and survives deep nesting", () => {
  assert.equal(findUnsafeNumber({ a: [{ b: 2 ** 53 }] }), "/a/0/b");
  assert.equal(findUnsafeNumber({ a: [1, 2, { b: "text", c: null, d: true }] }), null);
  assert.equal(findUnsafeNumber(-(2 ** 60)), "/");
  let deep: unknown = 2 ** 70;
  for (let i = 0; i < 200_000; i++) deep = [deep]; // a recursive walk would overflow the stack
  assert.ok(findUnsafeNumber(deep)?.startsWith("/0/0"));
});

test("GET validates the slot like PUT", async () => {
  const { app, put, get } = await saveApi();
  for (const slot of ["Main", "a%20b", "x".repeat(33), "a.b"]) {
    assert.equal((await get(slot)).statusCode, 400, `GET ${slot}`);
    assert.equal((await put('{"revision":0,"schemaVersion":1,"data":{}}', slot)).statusCode, 400, `PUT ${slot}`);
  }
  assert.equal((await get("slot-1_ok")).statusCode, 404); // a valid slot with nothing in it
  await app.close();
});

test("a stored save cannot be changed through a reference the caller kept", async () => {
  const store = new MemoryStore();
  const data = { night: 1 };
  await store.putSave("u", "main", { schemaVersion: 1, data }, 0);
  data.night = 99;
  const read = await store.getSave("u", "main");
  assert.equal(read?.data.night, 1);
  (read!.data as { night: number }).night = 50;
  assert.equal((await store.getSave("u", "main"))?.data.night, 1);
});

// ---- Postgres: the same rules against the real store, when a database is given (TEST_DATABASE_URL)

const databaseUrl = process.env.TEST_DATABASE_URL;

test("Postgres keeps the envelope, exact strings and optimistic concurrency", { skip: !databaseUrl }, async () => {
  const store = await PgStore.connect(databaseUrl!);
  try {
    const user = await store.upsertUser(`stub:pg-${Date.now()}`, "pg");
    const first = await store.putSave(user.id, "main", { schemaVersion: 1, data: { rng: BIG } }, 0);
    assert.deepEqual(first, { revision: 1, schemaVersion: 1, data: { rng: BIG } });
    assert.deepEqual(await store.getSave(user.id, "main"), { revision: 1, schemaVersion: 1, data: { rng: BIG } });
    await assert.rejects(store.putSave(user.id, "main", { schemaVersion: 1, data: {} }, 0), RevisionConflict);
    const second = await store.putSave(user.id, "main", { schemaVersion: 1, data: { rng: "2", list: [1, 2.5] } }, 1);
    assert.equal(second.revision, 2);
    assert.deepEqual((await store.getSave(user.id, "main"))?.data, { rng: "2", list: [1, 2.5] });
  } finally {
    await store.close();
  }
});

test("Postgres adds the version column to a saves table made before saves were versioned", { skip: !databaseUrl }, async () => {
  const { default: pg } = await import("pg");
  const pool = new pg.Pool({ connectionString: databaseUrl });
  const table = `legacy_${Date.now()}`;
  try {
    // A throwaway schema, so the shared tables are untouched: the old table definition, one row, then connect.
    await pool.query(`CREATE SCHEMA ${table}`);
    const url = new URL(databaseUrl!);
    url.searchParams.set("options", `-c search_path=${table}`);
    await pool.query(`CREATE TABLE ${table}.users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), discord_id text NOT NULL UNIQUE, name text NOT NULL, created_at timestamptz NOT NULL DEFAULT now())`);
    await pool.query(`CREATE TABLE ${table}.saves (user_id uuid NOT NULL REFERENCES ${table}.users(id) ON DELETE CASCADE, slot text NOT NULL, revision integer NOT NULL, data jsonb NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (user_id, slot))`);
    const { rows } = await pool.query(`INSERT INTO ${table}.users (discord_id, name) VALUES ('old', 'old') RETURNING id`);
    await pool.query(`INSERT INTO ${table}.saves (user_id, slot, revision, data) VALUES ($1, 'main', 3, '{"night": 2}')`, [rows[0].id]);

    const store = await PgStore.connect(url.toString());
    try {
      assert.deepEqual(await store.getSave(rows[0].id, "main"), { revision: 3, schemaVersion: 1, data: { night: 2 } });
    } finally {
      await store.close();
    }
  } finally {
    await pool.query(`DROP SCHEMA IF EXISTS ${table} CASCADE`);
    await pool.end();
  }
});
