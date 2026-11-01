// Lobbies are short-lived and live in memory of one backend instance. That is fine for the spike and for the first
// release (one backend replica); running more replicas needs them in Postgres or Redis (see the research page).
//
// They do not live forever: an open lobby expires after it has been idle, a started one when its match ends (the
// game server says so) or at a maximum age. A user is in at most one open lobby. Every time comes from an injected
// clock, so tests move time by hand.
import { randomBytes, randomUUID } from "node:crypto";
import type { GameServerInfo } from "./servers.ts";

export interface Member {
  userId: string;
  name: string;
}

export interface Match {
  id: string;
  server: GameServerInfo;
}

export interface Lobby {
  id: string;
  /** Short code to join by hand. */
  code: string;
  /** The Discord Activity instance this lobby belongs to, when it was created from one. */
  instanceId: string | null;
  hostId: string;
  maxPlayers: number;
  members: Member[];
  state: "open" | "started";
  match: Match | null;
  createdAt: number;
  /** Last create, join, leave, start or poll by a member; an open lobby expires when this is old. */
  lastActiveAt: number;
  startedAt: number | null;
}

export type LobbyError =
  | "not_found"
  | "full"
  | "not_host"
  | "already_started"
  | "no_server"
  | "not_member"
  | "not_started"
  | "already_in_lobby";

export class LobbyFailure extends Error {
  readonly reason: LobbyError;

  constructor(reason: LobbyError) {
    super(reason);
    this.reason = reason;
  }
}

export interface LobbyLimits {
  /** An open lobby nobody touched for this long is dropped. */
  openIdleMs: number;
  /** A started lobby is dropped at this age even when the game server never said its match ended. */
  startedMaxAgeMs: number;
}

export const DEFAULT_LOBBY_LIMITS: LobbyLimits = { openIdleMs: 10 * 60_000, startedMaxAgeMs: 2 * 60 * 60_000 };

export interface LobbyHooks {
  /** Assigns the match to a live game server with room, or returns null. */
  allocate(matchId: string): GameServerInfo | null;
  /** Gives the match's slot back. */
  release(matchId: string): void;
  now?: () => number;
  limits?: LobbyLimits;
}

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function makeCode(): string {
  return Array.from(randomBytes(6), (byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
}

export class LobbyService {
  private readonly lobbies = new Map<string, Lobby>();
  // Indexes, so a lookup does not scan every lobby.
  private readonly byCode = new Map<string, string>();
  private readonly byInstance = new Map<string, string>();
  /** The one open lobby each user is in. */
  private readonly openLobbyOf = new Map<string, string>();
  private readonly byMatch = new Map<string, string>();

  private readonly hooks: LobbyHooks;
  private readonly now: () => number;
  private readonly limits: LobbyLimits;

  constructor(hooks: LobbyHooks) {
    this.hooks = hooks;
    this.now = hooks.now ?? Date.now;
    this.limits = hooks.limits ?? DEFAULT_LOBBY_LIMITS;
  }

  get size(): number {
    return this.lobbies.size;
  }

  private expired(lobby: Lobby): boolean {
    const now = this.now();
    return lobby.state === "open"
      ? now - lobby.lastActiveAt > this.limits.openIdleMs
      : now - (lobby.startedAt ?? lobby.createdAt) > this.limits.startedMaxAgeMs;
  }

  /** Forgets the lobby and frees what it held. Idempotent. */
  private remove(lobby: Lobby): void {
    if (this.lobbies.get(lobby.id) !== lobby) return;
    this.lobbies.delete(lobby.id);
    this.byCode.delete(lobby.code);
    if (lobby.instanceId && this.byInstance.get(lobby.instanceId) === lobby.id) this.byInstance.delete(lobby.instanceId);
    for (const m of lobby.members) if (this.openLobbyOf.get(m.userId) === lobby.id) this.openLobbyOf.delete(m.userId);
    if (lobby.match) {
      this.byMatch.delete(lobby.match.id);
      this.hooks.release(lobby.match.id);
    }
  }

  /** Drops every expired lobby; the app calls this on a timer. Returns how many went. */
  sweep(): number {
    let dropped = 0;
    for (const lobby of [...this.lobbies.values()]) {
      if (this.expired(lobby)) {
        this.remove(lobby);
        dropped++;
      }
    }
    return dropped;
  }

  create(host: Member, maxPlayers: number, instanceId: string | null): Lobby {
    if (this.openLobbyOf.has(host.userId)) throw new LobbyFailure("already_in_lobby");
    let code = makeCode();
    while (this.byCode.has(code)) code = makeCode();
    const now = this.now();
    const lobby: Lobby = {
      id: randomUUID(),
      code,
      instanceId,
      hostId: host.userId,
      maxPlayers,
      members: [host],
      state: "open",
      match: null,
      createdAt: now,
      lastActiveAt: now,
      startedAt: null,
    };
    this.lobbies.set(lobby.id, lobby);
    this.byCode.set(code, lobby.id);
    if (instanceId) this.byInstance.set(instanceId, lobby.id);
    this.openLobbyOf.set(host.userId, lobby.id);
    return lobby;
  }

  get(id: string): Lobby {
    const lobby = this.lobbies.get(id);
    if (!lobby) throw new LobbyFailure("not_found");
    if (this.expired(lobby)) {
      this.remove(lobby);
      throw new LobbyFailure("not_found");
    }
    return lobby;
  }

  /** A member reads the lobby (a poll): that counts as activity. */
  view(id: string, userId: string): Lobby {
    const lobby = this.get(id);
    if (!this.isMember(lobby, userId)) throw new LobbyFailure("not_member");
    lobby.lastActiveAt = this.now();
    return lobby;
  }

  private find(index: Map<string, string>, key: string): Lobby | null {
    const id = index.get(key);
    if (!id) return null;
    try {
      return this.get(id);
    } catch {
      return null;
    }
  }

  findByInstance(instanceId: string): Lobby | null {
    const lobby = this.find(this.byInstance, instanceId);
    return lobby?.state === "open" ? lobby : null;
  }

  findByCode(code: string): Lobby | null {
    return this.find(this.byCode, code.toUpperCase());
  }

  join(id: string, member: Member): Lobby {
    const lobby = this.get(id);
    if (lobby.members.some((m) => m.userId === member.userId)) return lobby;
    if (lobby.state !== "open") throw new LobbyFailure("already_started");
    if (this.openLobbyOf.has(member.userId)) throw new LobbyFailure("already_in_lobby");
    if (lobby.members.length >= lobby.maxPlayers) throw new LobbyFailure("full");
    lobby.members.push(member);
    lobby.lastActiveAt = this.now();
    this.openLobbyOf.set(member.userId, lobby.id);
    return lobby;
  }

  /** A member leaves. The host role passes to the next member; an empty lobby is dropped (its match ends). */
  leave(id: string, userId: string): void {
    const lobby = this.get(id);
    if (!this.isMember(lobby, userId)) throw new LobbyFailure("not_member");
    lobby.members = lobby.members.filter((m) => m.userId !== userId);
    if (this.openLobbyOf.get(userId) === lobby.id) this.openLobbyOf.delete(userId);
    lobby.lastActiveAt = this.now();
    if (lobby.members.length === 0) return this.remove(lobby);
    if (lobby.hostId === userId) lobby.hostId = lobby.members[0]!.userId;
  }

  /** The host starts the match: a game server is allocated and the lobby is closed to newcomers. */
  start(id: string, userId: string): Lobby {
    const lobby = this.get(id);
    if (lobby.hostId !== userId) throw new LobbyFailure("not_host");
    if (lobby.state === "started") throw new LobbyFailure("already_started");
    const matchId = randomUUID();
    const server = this.hooks.allocate(matchId);
    if (!server) throw new LobbyFailure("no_server");
    const now = this.now();
    lobby.state = "started";
    lobby.startedAt = now;
    lobby.lastActiveAt = now;
    lobby.match = { id: matchId, server };
    this.byMatch.set(matchId, lobby.id);
    // A started lobby is no longer an open one: its members may open or join another.
    for (const m of lobby.members) if (this.openLobbyOf.get(m.userId) === lobby.id) this.openLobbyOf.delete(m.userId);
    if (lobby.instanceId && this.byInstance.get(lobby.instanceId) === lobby.id) this.byInstance.delete(lobby.instanceId);
    return lobby;
  }

  /** The match is over (the game server said so, or stopped listing it): its lobby goes. Unknown ids are ignored. */
  matchEnded(matchId: string): void {
    const lobbyId = this.byMatch.get(matchId);
    const lobby = lobbyId ? this.lobbies.get(lobbyId) : undefined;
    if (lobby) this.remove(lobby);
    else this.hooks.release(matchId);
  }

  isMember(lobby: Lobby, userId: string): boolean {
    return lobby.members.some((m) => m.userId === userId);
  }
}
