import pg from "pg";
import { RevisionConflict, type Save, type Store, type User } from "./store.ts";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  discord_id text NOT NULL UNIQUE,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
-- When the account last signed in: a Guest account is deleted 7 days after it. Accounts made before this column
-- count as seen at the time it is added.
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen timestamptz NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS users_last_seen ON users (last_seen);
CREATE TABLE IF NOT EXISTS saves (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  slot text NOT NULL,
  revision integer NOT NULL,
  data jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, slot)
);
-- Saves written before the format was versioned are version 1 by definition.
ALTER TABLE saves ADD COLUMN IF NOT EXISTS schema_version integer NOT NULL DEFAULT 1;`;

export class PgStore implements Store {
  private readonly pool: pg.Pool;

  private constructor(pool: pg.Pool) {
    this.pool = pool;
  }

  /** Connects and creates the tables if they are missing (a real service would use migrations). */
  static async connect(databaseUrl: string): Promise<PgStore> {
    const pool = new pg.Pool({ connectionString: databaseUrl, max: 5 });
    await pool.query(SCHEMA);
    return new PgStore(pool);
  }

  async upsertUser(discordId: string, name: string, nowMs: number = Date.now()): Promise<User> {
    const { rows } = await this.pool.query(
      `INSERT INTO users (discord_id, name, last_seen) VALUES ($1, $2, to_timestamp($3::double precision / 1000))
       ON CONFLICT (discord_id) DO UPDATE SET name = EXCLUDED.name, last_seen = EXCLUDED.last_seen
       RETURNING ${USER_COLUMNS}`,
      [discordId, name, nowMs],
    );
    return toUser(rows[0]);
  }

  async getUser(id: string): Promise<User | null> {
    const { rows } = await this.pool.query(`SELECT ${USER_COLUMNS} FROM users WHERE id = $1`, [id]);
    return rows[0] ? toUser(rows[0]) : null;
  }

  // The saves go with the user (ON DELETE CASCADE).
  async deleteUser(id: string): Promise<void> {
    await this.pool.query("DELETE FROM users WHERE id = $1", [id]);
  }

  async deleteIdleUsers(prefix: string, lastSeenAtOrBefore: number): Promise<number> {
    const { rowCount } = await this.pool.query(
      "DELETE FROM users WHERE starts_with(discord_id, $1) AND last_seen <= to_timestamp($2::double precision / 1000)",
      [prefix, lastSeenAtOrBefore],
    );
    return rowCount ?? 0;
  }

  async getSave(userId: string, slot: string): Promise<Save | null> {
    const { rows } = await this.pool.query(
      "SELECT revision, schema_version, data FROM saves WHERE user_id = $1 AND slot = $2",
      [userId, slot],
    );
    return rows[0] ? { revision: rows[0].revision, schemaVersion: rows[0].schema_version, data: rows[0].data } : null;
  }

  async putSave(
    userId: string,
    slot: string,
    { schemaVersion, data }: { schemaVersion: number; data: Record<string, unknown> },
    expectedRevision: number,
  ): Promise<Save> {
    const insert = expectedRevision === 0;
    const sql = insert
      ? `INSERT INTO saves (user_id, slot, revision, data, schema_version) VALUES ($1, $2, 1, $3, $4)
         ON CONFLICT DO NOTHING RETURNING revision`
      : `UPDATE saves SET revision = revision + 1, data = $3, schema_version = $4, updated_at = now()
         WHERE user_id = $1 AND slot = $2 AND revision = $5 RETURNING revision`;
    const params = insert ? [userId, slot, data, schemaVersion] : [userId, slot, data, schemaVersion, expectedRevision];
    const { rows } = await this.pool.query(sql, params);
    if (rows[0]) return { revision: rows[0].revision, schemaVersion, data };
    const current = await this.getSave(userId, slot);
    throw new RevisionConflict(current?.revision ?? 0);
  }

  async ping(): Promise<void> {
    await this.pool.query("SELECT 1");
  }

  async close(): Promise<void> {
    await this.pool.end();
  }
}

// `last_seen` is read as epoch milliseconds (node-postgres would hand a Date, and a clock a test moves is a number).
const USER_COLUMNS = "id, discord_id, name, (extract(epoch FROM last_seen) * 1000)::double precision AS last_seen_ms";

function toUser(row: { id: string; discord_id: string; name: string; last_seen_ms: number }): User {
  return { id: row.id, discordId: row.discord_id, name: row.name, lastSeen: Math.round(Number(row.last_seen_ms)) };
}
