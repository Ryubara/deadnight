// The Server Browser's data: the public nights a player can be shown to join (Deadnight #1179, the screen is #1180).
// One row a night, built from what the lobby already knows; nothing is stored for it. The people count is people only:
// a bot never holds a seat of the room, so it is in neither `players` nor the cap (`bots` is what the host set, for a row
// that wants to say "+3 bots").
import { type Lobby, type LobbyService } from "./lobbies.ts";
import { DEFAULT_MAP } from "./settings.ts";

/** Most rows one answer carries: a screen shows a page, and a poll stays small however many nights there are. */
export const LIST_LIMIT = 50;
/** One account may ask for the list this often: a screen polls every few seconds and a Refresh button adds a few. */
export const LIST_PER_WINDOW = 20;
export const LIST_WINDOW_MS = 10_000;

export interface NightRow {
  id: string;
  /** The code a player joins by (`/lobbies/join-by-code`): a public night's code is no secret, it is in this row. */
  code: string;
  /** The map's id (the game knows its name and picture). */
  map: string;
  hostName: string;
  /** People in the night now, bots not counted; the game server's count once it has said one. */
  players: number;
  /** People the night takes, bots not counted. */
  maxPlayers: number;
  /** Bots the host set (0 when none): they hold no seat. */
  bots: number;
  /** `lobby` is still waiting for its host to start; `match` is a night in progress, which takes newcomers while it has room. */
  kind: "lobby" | "match";
  /** The same in the lobby's own words: `open` waits for its host to start; `started` is in progress. */
  state: "open" | "started";
  /** The round a match is in (null until the game server has said one); null for a lobby that waits. */
  round: number | null;
  /** No room for another person. Listed last, so a screen can show it greyed out. */
  full: boolean;
}

export function nightRow(lobby: Lobby, full: boolean): NightRow {
  return {
    id: lobby.id,
    code: lobby.code,
    map: lobby.settings?.map ?? DEFAULT_MAP,
    hostName: lobby.members.find((m) => m.userId === lobby.hostId)?.name ?? "",
    players: lobby.state === "started" ? (lobby.players ?? lobby.members.length) : lobby.members.length,
    maxPlayers: lobby.maxPlayers,
    bots: lobby.settings?.bots ?? 0,
    kind: lobby.state === "started" ? "match" : "lobby",
    state: lobby.state,
    round: lobby.state === "started" ? lobby.round : null,
    full,
  };
}

/**
 * The listed nights, with room first, then the most people, then the newest; at most `LIST_LIMIT`.
 * `total` is how many were listed before the cut.
 */
export function listNights(lobbies: LobbyService): { nights: NightRow[]; total: number } {
  const rows = lobbies
    .listed()
    .map((lobby) => ({ lobby, row: nightRow(lobby, lobbies.isFull(lobby)) }))
    .sort(
      (a, b) =>
        Number(a.row.full) - Number(b.row.full) || b.row.players - a.row.players || b.lobby.createdAt - a.lobby.createdAt,
    );
  return { nights: rows.slice(0, LIST_LIMIT).map((entry) => entry.row), total: rows.length };
}
