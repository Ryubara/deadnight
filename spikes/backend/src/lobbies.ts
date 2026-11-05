// Lobbies are short-lived and live in memory of one backend instance. That is fine for the spike and for the first
// release (one backend replica); running more replicas needs them in Postgres or Redis (see the research page).
//
// They do not live forever: an open lobby expires after it has been idle, a started one when its match ends (the
// game server says so) or at a maximum age. A user is in at most one lobby, open or started, and creating or joining
// another one takes them out of it (nobody is ever refused for being somewhere else); a lobby with no member left is
// gone at once. Every time comes from an injected clock, so tests move time by hand.
import { randomBytes, randomUUID } from "node:crypto";
import type { GameServerInfo } from "./servers.ts";
import { DEFAULT_MAP, type MatchSettings, checkSettings, mapOpenAt } from "./settings.ts";

export interface Member {
  userId: string;
  name: string;
}

export interface Match {
  id: string;
  server: GameServerInfo;
  /**
   * The level of the lobby's host when the match started: signed into EVERY ticket of the match (a guest's too), so the
   * game server decides the map from one number whatever order the players arrive in or whoever the host becomes.
   */
  hostLevel: number;
}

export interface Lobby {
  id: string;
  /** Short code to join by hand. */
  code: string;
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
  /**
   * When a finished night opened this lobby again, until a member first reads it. The night screen asks for it every
   * half second for a few seconds, so a reopened lobby nobody has read within `memberAwayMs` has no one coming back to
   * it (they went to the menu or closed the tab): it goes then, not after the long idle time.
   */
  reopenedAt: number | null;
}

export type LobbyError =
  | "not_found"
  | "full"
  | "not_host"
  | "already_started"
  | "no_server"
  | "not_member"
  | "not_started"
  | "bad_settings";

export class LobbyFailure extends Error {
  readonly reason: LobbyError;
  /** What the client can be told about the refusal beyond the reason (the setting it sent that is wrong). */
  readonly detail: string | undefined;

  constructor(reason: LobbyError, detail?: string) {
    super(reason);
    this.reason = reason;
    this.detail = detail;
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
/** Seats in a room, people and bots together: the game server's `NightHost.MAX_PLAYERS`, which a lobby may not exceed. */
export const MAX_PLAYERS = 8;

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
  /** The one lobby each user is in, open or started: creating or joining another takes them out of it. */
  private readonly lobbyOf = new Map<string, string>();
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
    if (lobby.reopenedAt !== null) return now - lobby.reopenedAt > this.limits.memberAwayMs;
    return lobby.state === "open"
      ? now - lobby.lastActiveAt > this.limits.openIdleMs
      : now - (lobby.startedAt ?? lobby.createdAt) > this.limits.startedMaxAgeMs;
  }

  /** Forgets the lobby and frees what it held. Idempotent. */
  private remove(lobby: Lobby): void {
    if (this.lobbies.get(lobby.id) !== lobby) return;
    this.lobbies.delete(lobby.id);
    this.byCode.delete(lobby.code);
    for (const m of lobby.members) if (this.lobbyOf.get(m.userId) === lobby.id) this.lobbyOf.delete(m.userId);
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

  create(host: Member, maxPlayers: number, visibility: "private" | "public" = "private"): Lobby {
    this.depart(host.userId);
    let code = makeCode();
    while (this.byCode.has(code)) code = makeCode();
    const now = this.now();
    const lobby: Lobby = {
      id: randomUUID(),
      code,
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
      reopenedAt: null,
    };
    this.lobbies.set(lobby.id, lobby);
    this.byCode.set(code, lobby.id);
    this.lobbyOf.set(host.userId, lobby.id);
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
    if (this.lobbyOf.get(userId) === lobby.id) this.lobbyOf.delete(userId);
    if (lobby.hostId === userId && lobby.members.length > 0) lobby.hostId = lobby.members[0]!.userId;
  }

  /**
   * Takes the user out of the lobby they are in, whatever its state: the host role passes on, and a lobby left with
   * nobody is gone at once with its code and its match (the people in it are the members; bots are not counted).
   */
  private depart(userId: string): void {
    const id = this.lobbyOf.get(userId);
    const lobby = id ? this.lobbies.get(id) : undefined;
    this.lobbyOf.delete(userId);
    if (!lobby || !this.isMember(lobby, userId)) return;
    this.removeMember(lobby, userId);
    lobby.lastActiveAt = this.now();
    if (lobby.members.length === 0) this.remove(lobby);
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
    lobby.reopenedAt = null;
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

  findByCode(code: string): Lobby | null {
    return this.find(this.byCode, code.toUpperCase());
  }

  join(id: string, member: Member): Lobby {
    const lobby = this.get(id);
    if (lobby.members.some((m) => m.userId === member.userId)) return lobby;
    // A night in progress takes newcomers while it has room (the game server's own count when it has said one); an
    // open lobby while it has a seat. A player who is refused stays where they were; one who is taken in has left
    // the lobby they were in.
    if (this.isFull(lobby)) throw new LobbyFailure("full");
    this.depart(member.userId);
    lobby.members.push(member);
    lobby.lastActiveAt = this.now();
    lobby.seen.set(member.userId, lobby.lastActiveAt);
    this.lobbyOf.set(member.userId, lobby.id);
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
   * host, only before the start (they are fixed from then on), and only a value the game takes: a map must be one the
   * host's level (`hostLevel`, read by the caller from the stored profile) opens.
   */
  setSettings(id: string, userId: string, hostLevel: number, settings: unknown): Lobby {
    const lobby = this.get(id);
    if (lobby.hostId !== userId) throw new LobbyFailure("not_host");
    if (lobby.state === "started") throw new LobbyFailure("already_started");
    const checked = checkSettings(settings, hostLevel);
    if ("problem" in checked) throw new LobbyFailure("bad_settings", checked.problem);
    lobby.settings = checked.settings;
    lobby.lastActiveAt = this.now();
    return lobby;
  }

  /**
   * The host starts the match: a game server is allocated and the lobby is closed to newcomers. The rules are the
   * ones sent with the start, else the ones the host set while waiting (`setSettings`), else the game's own.
   * `hostLevel` is the starting host's level, read now: it is kept on the match and signed into every ticket. Rules sent
   * with the start name a map that level opens (else `bad_settings`); rules kept from the waiting, set by a host who
   * has left and whose level opened a map the new host's does not, start the match on the default map instead (the
   * game server does the same with a ticket, `MatchSettings.fit_host`).
   */
  start(id: string, userId: string, hostLevel: number, settings: unknown = undefined): Lobby {
    const lobby = this.get(id);
    if (lobby.hostId !== userId) throw new LobbyFailure("not_host");
    if (lobby.state === "started") throw new LobbyFailure("already_started");
    const given = settings !== undefined && settings !== null;
    let chosen = lobby.settings;
    if (given) {
      const checked = checkSettings(settings, hostLevel);
      if ("problem" in checked) throw new LobbyFailure("bad_settings", checked.problem);
      chosen = checked.settings;
    } else if (chosen?.map !== undefined && !mapOpenAt(chosen.map, hostLevel)) {
      chosen = { ...chosen, map: DEFAULT_MAP };
    }
    const matchId = randomUUID();
    const server = this.hooks.allocate(matchId);
    if (!server) throw new LobbyFailure("no_server");
    const now = this.now();
    lobby.state = "started";
    lobby.settings = chosen;
    lobby.startedAt = now;
    lobby.lastActiveAt = now;
    lobby.match = { id: matchId, server, hostLevel };
    this.byMatch.set(matchId, lobby.id);
    return lobby;
  }

  /** Quick join: a public night with room (open or started), else a new public one, started at once. */
  quick(member: Member, hostLevel: number, maxPlayers = MAX_PLAYERS): Lobby {
    for (const lobby of [...this.lobbies.values()]) {
      if (lobby.visibility !== "public" || this.expired(lobby)) continue;
      if (lobby.members.some((m) => m.userId === member.userId)) return lobby;
      try {
        return this.join(lobby.id, member);
      } catch (error) {
        if (!(error instanceof LobbyFailure)) throw error;
      }
    }
    const lobby = this.create(member, maxPlayers, "public");
    try {
      return this.start(lobby.id, member.userId, hostLevel);
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

  /**
   * The match is over (the game server said so, or stopped listing it): its lobby goes. Unknown ids are ignored.
   *
   * A night that ran its end-of-night intermission out is `finished` instead (`present`: the users the game server had
   * at that moment): the lobby opens again for the people who were there, with its code, its host (the next seat when
   * the host is not among them), and the settings the host chose (map, bots, rules), ready for
   * the host to start the next night. `present` is who was still connected when the room closed: a member who is not
   * (they left, or went to another lobby, which took them out of this one) is not put back, and a lobby none of them
   * can come back to is gone. A player put back is still free to create or join another lobby at once.
   */
  matchEnded(matchId: string, finished?: { present: string[] }): void {
    const lobbyId = this.byMatch.get(matchId);
    const lobby = lobbyId ? this.lobbies.get(lobbyId) : undefined;
    if (!lobby) {
      this.hooks.release(matchId);
      return;
    }
    const back = finished ? lobby.members.filter((m) => finished.present.includes(m.userId)) : [];
    if (back.length === 0) {
      this.remove(lobby);
      return;
    }
    this.byMatch.delete(matchId);
    this.hooks.release(matchId);
    const now = this.now();
    lobby.state = "open";
    lobby.match = null;
    lobby.players = null;
    lobby.round = null;
    lobby.startedAt = null;
    for (const m of lobby.members) if (!back.includes(m) && this.lobbyOf.get(m.userId) === lobby.id) this.lobbyOf.delete(m.userId);
    lobby.members = back;
    lobby.seen = new Map(back.map((m) => [m.userId, now]));
    lobby.lastActiveAt = now;
    lobby.reopenedAt = now;
    if (!back.some((m) => m.userId === lobby.hostId)) lobby.hostId = back[0]!.userId;
  }

  /**
   * The game server says a person's seat in the match is empty (they pressed Leave, closed the tab, or their dropped
   * connection was not taken back in time): they are out of the lobby at once, the host role passes on, and a night
   * with no person left is over. Unknown matches and users are ignored; it is safe to say twice.
   */
  memberLeft(matchId: string, userId: string): boolean {
    const lobbyId = this.byMatch.get(matchId);
    const lobby = lobbyId ? this.lobbies.get(lobbyId) : undefined;
    if (!lobby || !this.isMember(lobby, userId)) return false;
    this.removeMember(lobby, userId);
    lobby.lastActiveAt = this.now();
    if (lobby.members.length === 0) this.remove(lobby);
    return true;
  }

  isMember(lobby: Lobby, userId: string): boolean {
    return lobby.members.some((m) => m.userId === userId);
  }
}
