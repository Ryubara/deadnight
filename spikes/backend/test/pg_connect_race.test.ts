// Connecting runs the schema, and two connections doing that at once on an empty database must both succeed (#1118):
// `CREATE TABLE IF NOT EXISTS` is not safe when two sessions run it together (one fails with a duplicate key on
// pg_type_typname_nsp_index). It happens for two test files of `node --test` (they run in parallel) and for two backend
// instances starting together. The test connects many at once to a fresh schema, many times over.
import assert from "node:assert/strict";
import { test } from "node:test";
import { PgStore } from "../src/pg-store.ts";

const databaseUrl = process.env.TEST_DATABASE_URL;

const ROUNDS = 15;
const CONNECTIONS = 12;

test("Postgres: many stores connecting at once to an empty schema all succeed", { skip: !databaseUrl }, async () => {
  const { default: pg } = await import("pg");
  const pool = new pg.Pool({ connectionString: databaseUrl });
  try {
    for (let round = 0; round < ROUNDS; round++) {
      const schema = `race_${Date.now()}_${round}`;
      await pool.query(`CREATE SCHEMA ${schema}`);
      const url = new URL(databaseUrl!);
      url.searchParams.set("options", `-c search_path=${schema}`);
      try {
        const results = await Promise.allSettled(Array.from({ length: CONNECTIONS }, () => PgStore.connect(url.toString())));
        const failed = results.filter((r): r is PromiseRejectedResult => r.status === "rejected");
        await Promise.all(results.map((r) => (r.status === "fulfilled" ? r.value.close() : undefined)));
        assert.equal(failed.length, 0, `round ${round}: ${failed.map((f) => String(f.reason)).slice(0, 2).join("; ")}`);
        const tables = await pool.query("SELECT table_name FROM information_schema.tables WHERE table_schema = $1 ORDER BY 1", [schema]);
        assert.deepEqual(tables.rows.map((r) => r.table_name), ["ledger", "saves", "users"]);
      } finally {
        await pool.query(`DROP SCHEMA IF EXISTS ${schema} CASCADE`);
      }
    }
  } finally {
    await pool.end();
  }
});
