// Lobbies are short-lived and live in memory of one backend instance. That is fine for the spike and for the first
// release (one backend replica); running more replicas needs them in Postgres or Redis (see the research page).
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
}

export type LobbyError = "not_found" | "full" | "not_host" | "already_started" | "no_server" | "not_member" | "not_started";

export class LobbyFailure extends Error {
  readonly reason: LobbyError;

  constructor(reason: LobbyError) {
    super(reason);
    this.reason = reason;
  }
}

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function makeCode(): string {
  return Array.from(randomBytes(6), (byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
}

export class LobbyService {
  private readonly lobbies = new Map<string, Lobby>();

  private readonly allocateServer: () => GameServerInfo | null;

  constructor(allocateServer: () => GameServerInfo | null) {
    this.allocateServer = allocateServer;
  }

  create(host: Member, maxPlayers: number, instanceId: string | null): Lobby {
    const lobby: Lobby = {
      id: randomUUID(),
      code: makeCode(),
      instanceId,
      hostId: host.userId,
      maxPlayers,
      members: [host],
      state: "open",
      match: null,
    };
    this.lobbies.set(lobby.id, lobby);
    return lobby;
  }

  get(id: string): Lobby {
    const lobby = this.lobbies.get(id);
    if (!lobby) throw new LobbyFailure("not_found");
    return lobby;
  }

  findByInstance(instanceId: string): Lobby | null {
    return [...this.lobbies.values()].find((l) => l.instanceId === instanceId && l.state === "open") ?? null;
  }

  findByCode(code: string): Lobby | null {
    return [...this.lobbies.values()].find((l) => l.code === code.toUpperCase()) ?? null;
  }

  join(id: string, member: Member): Lobby {
    const lobby = this.get(id);
    if (lobby.members.some((m) => m.userId === member.userId)) return lobby;
    if (lobby.state !== "open") throw new LobbyFailure("already_started");
    if (lobby.members.length >= lobby.maxPlayers) throw new LobbyFailure("full");
    lobby.members.push(member);
    return lobby;
  }

  /** The host starts the match: a game server is allocated and the lobby is closed to newcomers. */
  start(id: string, userId: string): Lobby {
    const lobby = this.get(id);
    if (lobby.hostId !== userId) throw new LobbyFailure("not_host");
    if (lobby.state === "started") throw new LobbyFailure("already_started");
    const server = this.allocateServer();
    if (!server) throw new LobbyFailure("no_server");
    lobby.state = "started";
    lobby.match = { id: randomUUID(), server };
    return lobby;
  }

  isMember(lobby: Lobby, userId: string): boolean {
    return lobby.members.some((m) => m.userId === userId);
  }
}
