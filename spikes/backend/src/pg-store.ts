import pg from "pg";
import { RevisionConflict, type Save, type Store, type User } from "./store.ts";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  discord_id text NOT NULL UNIQUE,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS saves (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  slot text NOT NULL,
  revision integer NOT NULL,
  data jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, slot)
);`;

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

  async upsertUser(discordId: string, name: string): Promise<User> {
    const { rows } = await this.pool.query(
      `INSERT INTO users (discord_id, name) VALUES ($1, $2)
       ON CONFLICT (discord_id) DO UPDATE SET name = EXCLUDED.name
       RETURNING id, discord_id, name`,
      [discordId, name],
    );
    return toUser(rows[0]);
  }

  async getUser(id: string): Promise<User | null> {
    const { rows } = await this.pool.query("SELECT id, discord_id, name FROM users WHERE id = $1", [id]);
    return rows[0] ? toUser(rows[0]) : null;
  }

  async getSave(userId: string, slot: string): Promise<Save | null> {
    const { rows } = await this.pool.query("SELECT revision, data FROM saves WHERE user_id = $1 AND slot = $2", [
      userId,
      slot,
    ]);
    return rows[0] ? { revision: rows[0].revision, data: rows[0].data } : null;
  }

  async putSave(userId: string, slot: string, data: Record<string, unknown>, expectedRevision: number): Promise<Save> {
    const insert = expectedRevision === 0;
    const sql = insert
      ? `INSERT INTO saves (user_id, slot, revision, data) VALUES ($1, $2, 1, $3)
         ON CONFLICT DO NOTHING RETURNING revision`
      : `UPDATE saves SET revision = revision + 1, data = $3, updated_at = now()
         WHERE user_id = $1 AND slot = $2 AND revision = $4 RETURNING revision`;
    const params = insert ? [userId, slot, data] : [userId, slot, data, expectedRevision];
    const { rows } = await this.pool.query(sql, params);
    if (rows[0]) return { revision: rows[0].revision, data };
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

function toUser(row: { id: string; discord_id: string; name: string }): User {
  return { id: row.id, discordId: row.discord_id, name: row.name };
}
