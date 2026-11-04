// Persistent data: users and saves. Lobbies are deliberately not here (see lobbies.ts).
import { randomUUID } from "node:crypto";

export interface User {
  id: string;
  discordId: string;
  name: string;
  /** When the account last signed in (ms since the epoch): a Guest account is deleted 7 days after it. */
  lastSeen: number;
}

export interface Save {
  revision: number;
  /** The format of `data` (see saves.ts); the backend checks it is a known one and never changes it. */
  schemaVersion: number;
  data: Record<string, unknown>;
}

export class RevisionConflict extends Error {
  readonly currentRevision: number;

  constructor(currentRevision: number) {
    super("save revision conflict");
    this.currentRevision = currentRevision;
  }
}

/**
 * One line of the append-only XP ledger (docs/design/progression.md#storage-and-trust): why an account's XP moved. The
 * key (`userId`, `matchId`, `kind`, `round`) is also the idempotency key of a game server's round report: a second
 * report with the same key pays nothing. A solo client's write has the empty match, kind `solo` and its new revision.
 */
export interface LedgerEntry {
  userId: string;
  matchId: string;
  kind: "round" | "night" | "solo";
  round: number;
  /** Whole XP the account gained from this entry. */
  xp: number;
  /** What the entry did, for support and tuning (the report's lines, the one-offs paid). */
  reason: Record<string, unknown>;
  /** When it was written, ms since the epoch. */
  at: number;
}

/** The ledger already holds this entry: the report was applied before. */
export class DuplicateLedger extends Error {
  constructor() {
    super("ledger entry exists");
  }
}

export interface Store {
  /** Makes the user, or renames the one with this `discordId`; either way the sign-in is `nowMs`, its `lastSeen`. */
  upsertUser(discordId: string, name: string, nowMs?: number): Promise<User>;
  getUser(id: string): Promise<User | null>;
  /** Deletes the user and every save of it. */
  deleteUser(id: string): Promise<void>;
  /**
   * Deletes the users whose `discordId` starts with `prefix` and who last signed in at or before `lastSeenAtOrBefore`,
   * with their saves; the number deleted. Users of other kinds are never touched.
   */
  deleteIdleUsers(prefix: string, lastSeenAtOrBefore: number): Promise<number>;
  getSave(userId: string, slot: string): Promise<Save | null>;
  /**
   * Optimistic concurrency: `expectedRevision` is the revision the client last read (0 for a new slot). With `ledger`,
   * the entry is written in the same step as the save (both or neither); an entry with the same key throws
   * `DuplicateLedger` and the save is not written.
   */
  putSave(
    userId: string,
    slot: string,
    incoming: { schemaVersion: number; data: Record<string, unknown> },
    expectedRevision: number,
    ledger?: LedgerEntry,
  ): Promise<Save>;
  getLedgerEntry(userId: string, matchId: string, kind: string, round: number): Promise<LedgerEntry | null>;
  /** Whole XP the account was paid for one match (kinds `round` and `night`). */
  ledgerTotal(userId: string, matchId: string): Promise<number>;
  /** When the account's last entry of `kind` was written (ms since the epoch), or null. */
  lastLedgerAt(userId: string, kind: string): Promise<number | null>;
  /** Throws when the store cannot be reached (readiness check). */
  ping(): Promise<void>;
  close(): Promise<void>;
}

export class MemoryStore implements Store {
  private readonly users = new Map<string, User>();
  private readonly byDiscord = new Map<string, string>();
  private readonly saves = new Map<string, Save>();
  private readonly ledger = new Map<string, LedgerEntry>();

  async upsertUser(discordId: string, name: string, nowMs: number = Date.now()): Promise<User> {
    const existingId = this.byDiscord.get(discordId);
    const user: User = { id: existingId ?? randomUUID(), discordId, name, lastSeen: nowMs };
    this.users.set(user.id, user);
    this.byDiscord.set(discordId, user.id);
    return user;
  }

  async getUser(id: string): Promise<User | null> {
    const user = this.users.get(id);
    return user ? { ...user } : null;
  }

  async deleteUser(id: string): Promise<void> {
    const user = this.users.get(id);
    if (!user) return;
    this.users.delete(id);
    this.byDiscord.delete(user.discordId);
    for (const key of [...this.saves.keys()]) if (key.startsWith(`${id}/`)) this.saves.delete(key);
    // As Postgres cascades the delete to the ledger: the account's lines go with it.
    for (const [key, entry] of [...this.ledger]) if (entry.userId === id) this.ledger.delete(key);
  }

  async deleteIdleUsers(prefix: string, lastSeenAtOrBefore: number): Promise<number> {
    const idle = [...this.users.values()].filter((u) => u.discordId.startsWith(prefix) && u.lastSeen <= lastSeenAtOrBefore);
    for (const user of idle) await this.deleteUser(user.id);
    return idle.length;
  }

  // Saves go through a JSON round trip, as they do through Postgres `jsonb`: what is read back is what a database
  // would return, and a caller cannot change a stored save by keeping a reference to it.
  async getSave(userId: string, slot: string): Promise<Save | null> {
    const save = this.saves.get(`${userId}/${slot}`);
    return save ? (JSON.parse(JSON.stringify(save)) as Save) : null;
  }

  async putSave(
    userId: string,
    slot: string,
    incoming: { schemaVersion: number; data: Record<string, unknown> },
    expectedRevision: number,
    ledger?: LedgerEntry,
  ): Promise<Save> {
    const key = `${userId}/${slot}`;
    const current = this.saves.get(key)?.revision ?? 0;
    if (ledger && this.ledger.has(ledgerKey(ledger))) throw new DuplicateLedger();
    if (current !== expectedRevision) throw new RevisionConflict(current);
    if (ledger) this.ledger.set(ledgerKey(ledger), JSON.parse(JSON.stringify(ledger)) as LedgerEntry);
    const save = JSON.parse(JSON.stringify({ revision: current + 1, ...incoming })) as Save;
    this.saves.set(key, save);
    return JSON.parse(JSON.stringify(save)) as Save;
  }

  async getLedgerEntry(userId: string, matchId: string, kind: string, round: number): Promise<LedgerEntry | null> {
    const entry = this.ledger.get(ledgerKey({ userId, matchId, kind, round }));
    return entry ? (JSON.parse(JSON.stringify(entry)) as LedgerEntry) : null;
  }

  async ledgerTotal(userId: string, matchId: string): Promise<number> {
    let total = 0;
    for (const entry of this.ledger.values()) {
      if (entry.userId === userId && entry.matchId === matchId && entry.kind !== "solo") total += entry.xp;
    }
    return total;
  }

  async lastLedgerAt(userId: string, kind: string): Promise<number | null> {
    let last: number | null = null;
    for (const entry of this.ledger.values()) {
      if (entry.userId === userId && entry.kind === kind && (last === null || entry.at > last)) last = entry.at;
    }
    return last;
  }

  async ping(): Promise<void> {}

  async close(): Promise<void> {}
}

function ledgerKey(entry: { userId: string; matchId: string; kind: string; round: number }): string {
  return JSON.stringify([entry.userId, entry.matchId, entry.kind, entry.round]);
}
