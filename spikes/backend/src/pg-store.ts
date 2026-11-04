import pg from "pg";
import { DuplicateLedger, type LedgerEntry, RevisionConflict, type Save, type Store, type User } from "./store.ts";

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
);
-- Saves written before the format was versioned are version 1 by definition.
ALTER TABLE saves ADD COLUMN IF NOT EXISTS schema_version integer NOT NULL DEFAULT 1;
-- Why an account's XP moved, append only; its key is also a round report's idempotency key (a retry pays nothing).
-- A solo client's write has the empty match, kind 'solo' and its new revision as the round.
CREATE TABLE IF NOT EXISTS ledger (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  match_id text NOT NULL,
  kind text NOT NULL,
  round integer NOT NULL,
  xp integer NOT NULL,
  reason jsonb NOT NULL,
  at timestamptz NOT NULL,
  PRIMARY KEY (user_id, match_id, kind, round)
);
CREATE INDEX IF NOT EXISTS ledger_user_kind_at ON ledger (user_id, kind, at DESC);`;

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
    const { rows } = await this.pool.query(
      "SELECT revision, schema_version, data FROM saves WHERE user_id = $1 AND slot = $2",
      [userId, slot],
    );
    return rows[0] ? { revision: rows[0].revision, schemaVersion: rows[0].schema_version, data: rows[0].data } : null;
  }

  async putSave(
    userId: string,
    slot: string,
    incoming: { schemaVersion: number; data: Record<string, unknown> },
    expectedRevision: number,
    ledger?: LedgerEntry,
  ): Promise<Save> {
    if (!ledger) {
      const written = await this.writeSave(this.pool, userId, slot, incoming, expectedRevision);
      if (written) return written;
      throw new RevisionConflict((await this.getSave(userId, slot))?.revision ?? 0);
    }
    // The entry and the save are one transaction: a crash between them neither pays without a record nor records
    // without paying, and the entry's primary key is what makes a second report with the same key a no-op.
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const { rowCount } = await client.query(
        `INSERT INTO ledger (user_id, match_id, kind, round, xp, reason, at)
         VALUES ($1, $2, $3, $4, $5, $6, to_timestamp($7::double precision / 1000)) ON CONFLICT DO NOTHING`,
        [ledger.userId, ledger.matchId, ledger.kind, ledger.round, ledger.xp, ledger.reason, ledger.at],
      );
      if (rowCount === 0) {
        await client.query("ROLLBACK");
        throw new DuplicateLedger();
      }
      const written = await this.writeSave(client, userId, slot, incoming, expectedRevision);
      if (!written) {
        await client.query("ROLLBACK");
        throw new RevisionConflict((await this.getSave(userId, slot))?.revision ?? 0);
      }
      await client.query("COMMIT");
      return written;
    } catch (error) {
      if (!(error instanceof DuplicateLedger) && !(error instanceof RevisionConflict)) await client.query("ROLLBACK").catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  /** The revision-checked write of one save; null when the revision is not the stored one. */
  private async writeSave(
    db: { query: pg.Pool["query"] },
    userId: string,
    slot: string,
    { schemaVersion, data }: { schemaVersion: number; data: Record<string, unknown> },
    expectedRevision: number,
  ): Promise<Save | null> {
    const insert = expectedRevision === 0;
    const sql = insert
      ? `INSERT INTO saves (user_id, slot, revision, data, schema_version) VALUES ($1, $2, 1, $3, $4)
         ON CONFLICT DO NOTHING RETURNING revision`
      : `UPDATE saves SET revision = revision + 1, data = $3, schema_version = $4, updated_at = now()
         WHERE user_id = $1 AND slot = $2 AND revision = $5 RETURNING revision`;
    const params = insert ? [userId, slot, data, schemaVersion] : [userId, slot, data, schemaVersion, expectedRevision];
    const { rows } = await db.query(sql, params);
    return rows[0] ? { revision: rows[0].revision, schemaVersion, data } : null;
  }

  async getLedgerEntry(userId: string, matchId: string, kind: string, round: number): Promise<LedgerEntry | null> {
    const { rows } = await this.pool.query(
      `SELECT user_id, match_id, kind, round, xp, reason, (extract(epoch FROM at) * 1000)::double precision AS at_ms
       FROM ledger WHERE user_id = $1 AND match_id = $2 AND kind = $3 AND round = $4`,
      [userId, matchId, kind, round],
    );
    const row = rows[0];
    if (!row) return null;
    return { userId: row.user_id, matchId: row.match_id, kind: row.kind, round: row.round, xp: row.xp, reason: row.reason, at: Math.round(Number(row.at_ms)) };
  }

  async ledgerTotal(userId: string, matchId: string): Promise<number> {
    const { rows } = await this.pool.query(
      "SELECT COALESCE(SUM(xp), 0)::integer AS total FROM ledger WHERE user_id = $1 AND match_id = $2 AND kind <> 'solo'",
      [userId, matchId],
    );
    return rows[0].total;
  }

  async lastLedgerAt(userId: string, kind: string): Promise<number | null> {
    const { rows } = await this.pool.query(
      "SELECT (extract(epoch FROM max(at)) * 1000)::double precision AS at_ms FROM ledger WHERE user_id = $1 AND kind = $2",
      [userId, kind],
    );
    return rows[0]?.at_ms === null || rows[0]?.at_ms === undefined ? null : Math.round(Number(rows[0].at_ms));
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
