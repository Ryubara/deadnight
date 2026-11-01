// Persistent data: users and saves. Lobbies are deliberately not here (see lobbies.ts).
import { randomUUID } from "node:crypto";

export interface User {
  id: string;
  discordId: string;
  name: string;
}

export interface Save {
  revision: number;
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
  upsertUser(discordId: string, name: string): Promise<User>;
  getUser(id: string): Promise<User | null>;
  getSave(userId: string, slot: string): Promise<Save | null>;
  /** Optimistic concurrency: `expectedRevision` is the revision the client last read (0 for a new slot). */
  putSave(userId: string, slot: string, data: Record<string, unknown>, expectedRevision: number): Promise<Save>;
  /** Throws when the store cannot be reached (readiness check). */
  ping(): Promise<void>;
  close(): Promise<void>;
}

export class MemoryStore implements Store {
  private readonly users = new Map<string, User>();
  private readonly byDiscord = new Map<string, string>();
  private readonly saves = new Map<string, Save>();

  async upsertUser(discordId: string, name: string): Promise<User> {
    const existingId = this.byDiscord.get(discordId);
    const user: User = { id: existingId ?? randomUUID(), discordId, name };
    this.users.set(user.id, user);
    this.byDiscord.set(discordId, user.id);
    return user;
  }

  async getUser(id: string): Promise<User | null> {
    return this.users.get(id) ?? null;
  }

  async getSave(userId: string, slot: string): Promise<Save | null> {
    return this.saves.get(`${userId}/${slot}`) ?? null;
  }

  async putSave(userId: string, slot: string, data: Record<string, unknown>, expectedRevision: number): Promise<Save> {
    const key = `${userId}/${slot}`;
    const current = this.saves.get(key)?.revision ?? 0;
    if (current !== expectedRevision) throw new RevisionConflict(current);
    const save = { revision: current + 1, data };
    this.saves.set(key, save);
    return save;
  }

  async ping(): Promise<void> {}

  async close(): Promise<void> {}
}
