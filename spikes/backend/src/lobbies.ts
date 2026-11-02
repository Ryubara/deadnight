// Lobbies are short-lived and live in memory of one backend instance. That is fine for the spike and for the first
// release (one backend replica); running more replicas needs them in Postgres or Redis (see the research page).
//
// They do not live forever: an open lobby expires after it has been idle, a started one when its match ends (the
// game server says so) or at a maximum age. A user is in at most one open lobby. Every time comes from an injected
// clock, so tests move time by hand.
import { randomBytes, randomUUID } from "node:crypto";
import type { GameServerInfo } from "./servers.ts";
import { type MatchSettings, parseSettings } from "./settings.ts";

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
  /** A public night is one Quick join may put a stranger in; a private one is for whoever has its code. */
  visibility: "private" | "public";
  members: Member[];
  /** When each member was last heard from (create, join, a poll): who is still on the lobby screen. */
  seen: Map<string, number>;
  /** Players on the game server now, as it last said (null until it has, or before the match starts). */
  players: number | null;
  /** The round the night is in, as the game server last said (null until it has, or before the match starts). */
  round: number | null;
  state: "open" | "started";
  /** What the host chose for the night (null: the game's defaults); fixed when the match starts. */
  settings: MatchSettings | null;
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
  | "already_in_lobby"
  | "bad_settings";

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
  /** A member of an open lobby not heard from for this long has gone (a closed tab) while someone else is still there. */
  memberAwayMs: number;
  /** Shown as `away` after this long without a poll: a client polls every couple of seconds. */
  memberQuietMs: number;
}

/** Most people who may ever hold a seat of one started night (who left is not tracked, only who is there now). */
export const MAX_SEATS_EVER = 32;

// A tab in the background stops polling (the game's frames stop), so a host who goes to a chat to paste the invite is
// quiet for a while: a minute is long enough for that and short enough that a closed tab does not hold a seat for long.
export const DEFAULT_LOBBY_LIMITS: LobbyLimits = {
  openIdleMs: 10 * 60_000,
  startedMaxAgeMs: 2 * 60 * 60_000,
  memberAwayMs: 60_000,
  memberQuietMs: 15_000,
};

export interface LobbyHooks {
  /** Assigns the match to a live game server with room, or returns null. */
  allocate(matchId: string): GameServerInfo | null;
  /** Gives the match's slot back. */
  release(matchId: string): void;
  now?: () => number;
  limits?: Partial<LobbyLimits>;
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
    this.limits = { ...DEFAULT_LOBBY_LIMITS, ...hooks.limits };
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
      } else {
        this.dropAbsent(lobby);
      }
    }
    return dropped;
  }

  create(host: Member, maxPlayers: number, instanceId: string | null, visibility: "private" | "public" = "private"): Lobby {
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
      visibility,
      members: [host],
      seen: new Map([[host.userId, now]]),
      players: null,
      round: null,
      state: "open",
      settings: null,
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
    this.dropAbsent(lobby);
    return lobby;
  }

  /**
   * Members of an open lobby who stopped polling have gone (a closed tab never says so). They leave as if they had
   * pressed Leave, the host role passing on, but only while someone else is still there: a lobby whose members are all
   * quiet (every tab in the background) is left to expire as an idle one does, never emptied by this.
   */
  private dropAbsent(lobby: Lobby): void {
    if (lobby.state !== "open") return;
    const now = this.now();
    const absent = (m: Member) => now - (lobby.seen.get(m.userId) ?? 0) > this.limits.memberAwayMs;
    if (lobby.members.every(absent)) return;
    for (const gone of lobby.members.filter(absent)) this.removeMember(lobby, gone.userId);
  }

  /** Takes a member out: their place, their seat, and the host role when it was theirs (to the next seat). */
  private removeMember(lobby: Lobby, userId: string): void {
    lobby.members = lobby.members.filter((m) => m.userId !== userId);
    lobby.seen.delete(userId);
    if (this.openLobbyOf.get(userId) === lobby.id) this.openLobbyOf.delete(userId);
    if (lobby.hostId === userId && lobby.members.length > 0) lobby.hostId = lobby.members[0]!.userId;
  }

  /** Whether another player cannot take a seat now: the game server's count once started, the seats before. */
  isFull(lobby: Lobby): boolean {
    if (lobby.state === "started") return (lobby.players ?? lobby.members.length) >= lobby.maxPlayers || lobby.members.length >= MAX_SEATS_EVER;
    return lobby.members.length >= lobby.maxPlayers;
  }

  /** Whether the member was heard from in the last moments (a client polls every couple of seconds). */
  isQuiet(lobby: Lobby, userId: string): boolean {
    return this.now() - (lobby.seen.get(userId) ?? 0) > this.limits.memberQuietMs;
  }

  /** A member reads the lobby (a poll): that counts as activity. */
  view(id: string, userId: string): Lobby {
    const lobby = this.get(id);
    if (!this.isMember(lobby, userId)) throw new LobbyFailure("not_member");
    lobby.lastActiveAt = this.now();
    lobby.seen.set(userId, lobby.lastActiveAt);
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
    // A started night counts too: the friends who open the Activity later land in the same night.
    return this.find(this.byInstance, instanceId);
  }

  findByCode(code: string): Lobby | null {
    return this.find(this.byCode, code.toUpperCase());
  }

  join(id: string, member: Member): Lobby {
    const lobby = this.get(id);
    if (lobby.members.some((m) => m.userId === member.userId)) return lobby;
    if (lobby.state === "started") {
      // A night in progress takes newcomers while it has room: the game server's own count when it has said one.
      if (this.isFull(lobby)) throw new LobbyFailure("full");
      lobby.members.push(member);
      lobby.lastActiveAt = this.now();
      lobby.seen.set(member.userId, lobby.lastActiveAt);
      return lobby;
    }
    if (this.openLobbyOf.has(member.userId)) throw new LobbyFailure("already_in_lobby");
    if (this.isFull(lobby)) throw new LobbyFailure("full");
    lobby.members.push(member);
    lobby.lastActiveAt = this.now();
    lobby.seen.set(member.userId, lobby.lastActiveAt);
    this.openLobbyOf.set(member.userId, lobby.id);
    return lobby;
  }

  /** A member leaves. The host role passes to the next member; an empty lobby is dropped (its match ends). */
  leave(id: string, userId: string): void {
    const lobby = this.get(id);
    if (!this.isMember(lobby, userId)) throw new LobbyFailure("not_member");
    this.removeMember(lobby, userId);
    lobby.lastActiveAt = this.now();
    if (lobby.members.length === 0) this.remove(lobby);
  }

  /**
   * The host sets the rules of the night while the lobby waits: every member reads them on their next poll. Only the
   * host, only before the start (they are fixed from then on), and only a value the game takes.
   */
  setSettings(id: string, userId: string, settings: unknown): Lobby {
    const lobby = this.get(id);
    if (lobby.hostId !== userId) throw new LobbyFailure("not_host");
    if (lobby.state === "started") throw new LobbyFailure("already_started");
    const chosen = parseSettings(settings);
    if (chosen === null) throw new LobbyFailure("bad_settings");
    lobby.settings = chosen;
    lobby.lastActiveAt = this.now();
    return lobby;
  }

  /**
   * The host starts the match: a game server is allocated and the lobby is closed to newcomers. The rules are the
   * ones sent with the start, else the ones the host set while waiting (`setSettings`), else the game's own.
   */
  start(id: string, userId: string, settings: unknown = undefined): Lobby {
    const lobby = this.get(id);
    if (lobby.hostId !== userId) throw new LobbyFailure("not_host");
    if (lobby.state === "started") throw new LobbyFailure("already_started");
    const given = settings !== undefined && settings !== null;
    const chosen = given ? parseSettings(settings) : lobby.settings;
    if (given && chosen === null) throw new LobbyFailure("bad_settings");
    const matchId = randomUUID();
    const server = this.hooks.allocate(matchId);
    if (!server) throw new LobbyFailure("no_server");
    const now = this.now();
    lobby.state = "started";
    lobby.settings = chosen;
    lobby.startedAt = now;
    lobby.lastActiveAt = now;
    lobby.match = { id: matchId, server };
    this.byMatch.set(matchId, lobby.id);
    // A started lobby is no longer an open one: its members may open or join another.
    for (const m of lobby.members) if (this.openLobbyOf.get(m.userId) === lobby.id) this.openLobbyOf.delete(m.userId);
    return lobby;
  }

  /** Quick join: a public night with room (open or started), else a new public one, started at once. */
  quick(member: Member, maxPlayers = 4): Lobby {
    for (const lobby of this.lobbies.values()) {
      if (lobby.visibility !== "public" || this.expired(lobby)) continue;
      if (lobby.members.some((m) => m.userId === member.userId)) return lobby;
      try {
        return this.join(lobby.id, member);
      } catch (error) {
        if (!(error instanceof LobbyFailure)) throw error;
      }
    }
    const lobby = this.create(member, maxPlayers, null, "public");
    try {
      return this.start(lobby.id, member.userId);
    } catch (error) {
      this.remove(lobby);
      throw error;
    }
  }

  /** The game server's count of the players in a match, from its heartbeat. Unknown matches are ignored. */
  setPlayers(matchId: string, players: number): void {
    const lobbyId = this.byMatch.get(matchId);
    const lobby = lobbyId ? this.lobbies.get(lobbyId) : undefined;
    if (lobby) lobby.players = players;
  }

  /** The game server's round of a match, from its heartbeat. Unknown matches are ignored. */
  setRound(matchId: string, round: number): void {
    const lobbyId = this.byMatch.get(matchId);
    const lobby = lobbyId ? this.lobbies.get(lobbyId) : undefined;
    if (lobby) lobby.round = round;
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
