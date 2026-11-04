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
  /** Optimistic concurrency: `expectedRevision` is the revision the client last read (0 for a new slot). */
  putSave(
    userId: string,
    slot: string,
    incoming: { schemaVersion: number; data: Record<string, unknown> },
    expectedRevision: number,
  ): Promise<Save>;
  /** Throws when the store cannot be reached (readiness check). */
  ping(): Promise<void>;
  close(): Promise<void>;
}

export class MemoryStore implements Store {
  private readonly users = new Map<string, User>();
  private readonly byDiscord = new Map<string, string>();
  private readonly saves = new Map<string, Save>();

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
  ): Promise<Save> {
    const key = `${userId}/${slot}`;
    const current = this.saves.get(key)?.revision ?? 0;
    if (current !== expectedRevision) throw new RevisionConflict(current);
    const save = JSON.parse(JSON.stringify({ revision: current + 1, ...incoming })) as Save;
    this.saves.set(key, save);
    return JSON.parse(JSON.stringify(save)) as Save;
  }

  async ping(): Promise<void> {}

  async close(): Promise<void> {}
}
