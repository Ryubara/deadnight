// Permanent progression on the backend: the profile slot, the game server's round reports and the XP clamp.
// The design is docs/design/progression.md#storage-and-trust. The game owns the profile's layout (`Profile` in
// game/gameplay/progression/profile.gd) and the level curve (`LevelCurve`); the numbers below are copies of the
// game's, held equal by test/progression.test.ts, which reads the GDScript files.
//
// Two ways to write XP, never one write per kill:
//  - the game server posts a round report (`applyReport`): each seat's XP, once, keyed by match, kind and round;
//  - a signed-in solo client writes its profile (`soloWrite`), and the backend caps how fast the XP may rise.
// A Guest account is an account: both ways are the same for it. There is no offline XP and no merge of an offline
// save, so a stale write (409) is read again and sent again on the account's own latest.
import { checkSave, MAX_SAVE_BYTES, SaveRejected } from "./saves.ts";
import { type LedgerEntry, DuplicateLedger, RevisionConflict, type Save, type Store } from "./store.ts";

/** The slot the profile is saved in. */
export const PROFILE_SLOT = "profile";
/**
 * The slot of the player's challenge board: an ordinary save the backend does not read. A game server reads it when a
 * seat sits down (`ProgressService.boardOf`) and writes it back in a round report (`SeatReport.board`).
 */
export const CHALLENGES_SLOT = "challenges";

/** XP to leave each level of a tier of five, tier by tier (`LevelCurve.TIER_COSTS`). */
export const TIER_COSTS: readonly number[] = [85, 135, 185, 235, 290, 340, 390, 440, 490, 540, 590];
export const TIER_SIZE = 5;
export const MAX_LEVEL = 55;

/** The most one night pays a seat, every line and every challenge together (`XpRules.NIGHT_CAP`). */
export const NIGHT_CAP = 1500;
export const OPENING_NIGHT_XP = 50;
export const FIRST_GAME_OF_THE_DAY_XP = 100;

/**
 * The most a signed-in solo client may add to its XP a minute of wall clock since its last write. A strong
 * four-player night is about 35 XP a minute on the 8-hour curve, so this is about three times that; retune with the
 * telemetry.
 */
export const SOLO_XP_PER_MINUTE = 120;
/** The wall clock a single write may count: a longer silence is not banked, so the long-run rate is still the cap. */
export const SOLO_WINDOW_MS = 60 * 60_000;
/** The day number may differ from the backend's own date by this many days (time zones, a night over midnight). */
export const DAY_TOLERANCE = 1;
export const DAY_MS = 86_400_000;
/** Largest raw XP a profile may hold (a sanity bound, far above level 55's 18,010). */
export const MAX_PROFILE_XP = 1_000_000_000;
export const MAX_DONE = 2000;
/** How many finished challenges a ticket carries, when it carries a calling card or an emblem. */
export const TICKET_DONE = 256;
/** A calling card's or an emblem's id as the game writes them: lower case, digits and underscores. */
const PIECE_ID = /^[a-z0-9_]{1,40}$/;

/** What a ticket says about a seat's progression (the game's `TicketVerifier.account_of` reads it). */
export interface TicketClaims {
  level: number;
  icon: string;
  xp: number;
  card?: string;
  emblem?: string;
  done?: string[];
}

/** What an account is known as between requests: its level and what it chose to wear. */
interface Known {
  level: number;
  card?: string;
  emblem?: string;
}

function knownOf(profile: ProfileData): Known {
  return { level: levelOf(profile.xp), card: pieceId(profile.equipped.card), emblem: pieceId(profile.equipped.emblem) };
}

/** A piece id from the profile's `equipped`, or undefined when it is not one. */
function pieceId(value: unknown): string | undefined {
  return typeof value === "string" && PIECE_ID.test(value) ? value : undefined;
}
const NO_DAY = -1;

const MATCH_KINDS = ["round", "night"] as const;
export type ReportKind = (typeof MATCH_KINDS)[number];

/** XP the level curve asks to go from `level` to the next (0 at the top). */
function toLeave(level: number): number {
  if (level < 1 || level >= MAX_LEVEL) return 0;
  return TIER_COSTS[Math.floor((level - 1) / TIER_SIZE)]!;
}

/** The level raw XP has reached, 1 to 55 (XP past the top stays on the top). */
export function levelOf(xp: number): number {
  let level = 1;
  let left = Math.max(0, Math.floor(xp));
  while (level < MAX_LEVEL && left >= toLeave(level)) {
    left -= toLeave(level);
    level += 1;
  }
  return level;
}

/** The id of a level's icon, the file name in game/assets/ui/levels/ without its extension. */
export function iconOf(level: number): string {
  return `level_${String(Math.min(Math.max(level, 1), MAX_LEVEL)).padStart(2, "0")}`;
}

/** Day number `ms` falls on: whole days since 1970, UTC. The game's day is the player's local one; the tolerance covers it. */
export function dayNumber(ms: number): number {
  return Math.floor(ms / DAY_MS);
}

/** What a profile holds, as `Profile.to_dict` writes it. */
export interface ProfileData extends Record<string, unknown> {
  xp: number;
  equipped: Record<string, unknown>;
  done: string[];
  opening_night: boolean;
  bonus_day: number;
}

export function freshProfile(): ProfileData {
  return { xp: 0, equipped: {}, done: [], opening_night: false, bonus_day: NO_DAY };
}

const isCount = (value: unknown): value is number => typeof value === "number" && Number.isInteger(value);

/**
 * The profile a `data` object holds, or throws 422 `invalid_profile` naming the field. Fields the backend does not read
 * (the game may add some) pass through untouched.
 */
export function checkProfile(data: Record<string, unknown>): ProfileData {
  const bad = (field: string): never => {
    throw new SaveRejected("invalid_profile", { field });
  };
  if (!isCount(data.xp) || data.xp < 0 || data.xp > MAX_PROFILE_XP) bad("xp");
  if (data.equipped === null || typeof data.equipped !== "object" || Array.isArray(data.equipped)) bad("equipped");
  const done = data.done;
  if (!Array.isArray(done) || done.length > MAX_DONE) bad("done");
  for (const id of done as unknown[]) if (typeof id !== "string" || id.length === 0 || id.length > 64) bad("done");
  if (typeof data.opening_night !== "boolean") bad("opening_night");
  if (!isCount(data.bonus_day) || data.bonus_day < NO_DAY) bad("bonus_day");
  return data as ProfileData;
}

/** A stored profile, or a fresh one when none was saved (or the stored one does not read: it never breaks a night). */
export function profileOf(save: Save | null): ProfileData {
  if (!save) return freshProfile();
  try {
    return checkProfile(save.data);
  } catch {
    return freshProfile();
  }
}

/** Whether `day` is a day number the backend accepts today: within a day of its own date. */
export function dayPlausible(day: number, nowMs: number): boolean {
  return Math.abs(day - dayNumber(nowMs)) <= DAY_TOLERANCE;
}

/** Throws 422 `profile_regressed` when `next` takes away something `current` has: XP, the opening night, the day, a finished challenge. */
function checkNoRegress(current: ProfileData, next: ProfileData): void {
  const lost = (field: string): never => {
    throw new SaveRejected("profile_regressed", { field });
  };
  if (next.xp < current.xp) lost("xp");
  if (current.opening_night && !next.opening_night) lost("opening_night");
  if (next.bonus_day < current.bonus_day) lost("bonus_day");
  const kept = new Set(next.done);
  if (current.done.some((id) => !kept.has(id))) lost("done");
}

/** What a client's write of the profile adds, and the most it may add. */
export interface SoloProgress {
  /** XP added over the profile on file. */
  added: number;
  /** The most the wall clock since the last write (and the one-offs this write claims) allows. */
  allowed: number;
  openingNight: boolean;
  bonusDay: boolean;
}

/**
 * The rules for a signed-in solo client's write of its profile; throws a `SaveRejected` when the write is not allowed.
 *  - the profile reads (`invalid_profile`), and takes nothing away (`profile_regressed`);
 *  - the first-game-of-the-day number moves forward once and lies within a day of the backend's date (`implausible_day`);
 *  - the XP added is at most `SOLO_XP_PER_MINUTE` for each minute since `sinceMs` (the last write, else the session's
 *    start), counting at most `SOLO_WINDOW_MS`, plus the opening night and the first game of the day when this write
 *    claims them (`implausible_progress`). Waiting makes a refused write acceptable.
 */
export function checkSoloWrite(current: ProfileData, next: ProfileData, nowMs: number, sinceMs: number): SoloProgress {
  checkNoRegress(current, next);
  const bonusDay = next.bonus_day !== current.bonus_day;
  if (bonusDay && !dayPlausible(next.bonus_day, nowMs)) {
    throw new SaveRejected("implausible_day", { bonus_day: next.bonus_day, today: dayNumber(nowMs) });
  }
  const openingNight = next.opening_night && !current.opening_night;
  const elapsedMs = Math.min(Math.max(nowMs - sinceMs, 0), SOLO_WINDOW_MS);
  const allowed =
    Math.floor((elapsedMs / 60_000) * SOLO_XP_PER_MINUTE) +
    (openingNight ? OPENING_NIGHT_XP : 0) +
    (bonusDay ? FIRST_GAME_OF_THE_DAY_XP : 0);
  const added = next.xp - current.xp;
  if (added > allowed) throw new SaveRejected("implausible_progress", { added, allowed, perMinute: SOLO_XP_PER_MINUTE });
  return { added, allowed, openingNight, bonusDay };
}

/** One seat of a round report. */
export interface SeatReport {
  userId: string;
  /** XP the seat earned since the last report, whole XP, without the two one-offs below (the backend pays those). */
  xp: number;
  /** The seat finished a round of the night: the backend pays the opening night once, if it was never paid. */
  openingNight?: boolean;
  /** The day number of that round's end: the backend pays the first game of the day once, if it is a new day. */
  bonusDay?: number;
  /** Challenge ids finished since the last report. */
  done?: string[];
  /**
   * The seat's challenge board as the game server's tracker holds it, the envelope the `challenges` slot takes
   * (`{schemaVersion, data}`; the backend sets the revision). It replaces the stored board (the server read the stored
   * one when the seat sat down and counted on top of it) and never blocks the XP: a board that is refused is
   * reported as `refused` and the XP is paid all the same.
   */
  board?: { schemaVersion: number; data: Record<string, unknown> };
  /** What the round did, by line (rounds, points, boards, ...), kept in the ledger for support and tuning. */
  lines?: Record<string, number>;
}

export interface SeatResult {
  userId: string;
  /** `paid`: credited now. `duplicate`: this report was already applied, nothing changed. `unknown_user`: no such account (a Guest that expired). */
  status: "paid" | "duplicate" | "unknown_user";
  /** XP the profile gained from this report (less than the seat's `xp` when the night's cap cut it). */
  credited: number;
  openingNight: boolean;
  firstGameOfTheDay: boolean;
  /** The profile's raw XP and level after the report (0 and 0 for an unknown user). */
  xp: number;
  level: number;
  /** Only when the seat's report held a board: `saved`, or `refused` (it did not read, or was too big). */
  board?: "saved" | "refused";
}

/** Attempts at a read-modify-write of a profile that a client or another report keeps moving. */
const WRITE_ATTEMPTS = 8;

export class ProgressService {
  private readonly store: Store;
  private readonly now: () => number;
  /** What each account was last known as (level, card, emblem), so a lobby's member list (which is built without waiting) can show it. */
  private readonly known = new Map<string, Known>();

  constructor(store: Store, now: () => number = Date.now) {
    this.store = store;
    this.now = now;
  }

  /** The level an account has reached (1 for one with no profile): what a host's level is, for the map gate. */
  async levelFor(userId: string): Promise<number> {
    return levelOf(profileOf(await this.store.getSave(userId, PROFILE_SLOT)).xp);
  }

  /** The stored challenge board of an account (the envelope), or null when it has none: what a game server follows. */
  async boardOf(userId: string): Promise<Save | null> {
    return this.store.getSave(userId, CHALLENGES_SLOT);
  }

  /**
   * The claims a ticket carries for a seat, read from the stored profile and never the client's word on this call:
   * the level, its icon and the raw XP; the calling card and the emblem the player chose (`equipped`, absent for none
   * or for an id that is not a plain name), and the challenges they finished, which the game server holds those two
   * choices to (it owns the list of what each gives). The list is the last `TICKET_DONE` ids, far more than the game
   * has challenges.
   */
  async claimsFor(userId: string): Promise<TicketClaims> {
    const profile = profileOf(await this.store.getSave(userId, PROFILE_SLOT));
    const level = levelOf(profile.xp);
    this.known.set(userId, knownOf(profile));
    const claims: TicketClaims = { level, icon: iconOf(level), xp: profile.xp };
    const { card, emblem } = knownOf(profile);
    if (card) claims.card = card;
    if (emblem) claims.emblem = emblem;
    if (card || emblem) claims.done = profile.done.slice(-TICKET_DONE);
    return claims;
  }

  /**
   * The level and icon an account was last seen at (a ticket, a lobby join, a report) with the calling card and emblem
   * it chose, or null when this process has not seen it yet. The lobby's list shows them as chosen; the game server
   * holds them to what the account owns when the night starts (`PlateTable`).
   */
  knownLevel(userId: string): { level: number; icon: string; card?: string; emblem?: string } | null {
    const known = this.known.get(userId);
    return known === undefined ? null : { level: known.level, icon: iconOf(known.level), ...(known.card ? { card: known.card } : {}), ...(known.emblem ? { emblem: known.emblem } : {}) };
  }

  /**
   * `PUT /saves/profile`: the signed-in client writes its profile at a round's end. `sessionStartSeconds` is when the
   * session began, the clamp's start for a first write. A stale revision is a `RevisionConflict`.
   */
  async soloWrite(
    userId: string,
    incoming: { revision: number; schemaVersion: number; data: Record<string, unknown> },
    sessionStartSeconds: number,
  ): Promise<Save> {
    const next = checkProfile(incoming.data);
    const nowMs = this.now();
    const saved = await this.store.getSave(userId, PROFILE_SLOT);
    const revision = saved?.revision ?? 0;
    if (revision !== incoming.revision) throw new RevisionConflict(revision);
    const current = profileOf(saved);
    const since = (await this.store.lastLedgerAt(userId, "solo")) ?? sessionStartSeconds * 1000;
    const progress = checkSoloWrite(current, next, nowMs, since);
    const ledger: LedgerEntry | undefined =
      progress.added > 0
        ? {
            userId,
            matchId: "",
            kind: "solo",
            round: revision + 1,
            xp: progress.added,
            reason: { openingNight: progress.openingNight, firstGameOfTheDay: progress.bonusDay },
            at: nowMs,
          }
        : undefined;
    return this.store.putSave(userId, PROFILE_SLOT, { schemaVersion: incoming.schemaVersion, data: next }, revision, ledger);
  }

  /**
   * A game server's report of one round (`kind: "round"`) or of the night's end (`"night"`) of match `matchId`. Each seat
   * is keyed by (match, kind, round, user): applying the same report again pays nothing, a seat at a time, so a retry
   * after a partial failure finishes the job. A seat's night total is held to `NIGHT_CAP`.
   */
  async applyReport(matchId: string, kind: ReportKind, round: number, seats: SeatReport[]): Promise<SeatResult[]> {
    const results: SeatResult[] = [];
    for (const seat of seats) results.push(await this.applySeat(matchId, kind, round, seat));
    return results;
  }

  private async applySeat(matchId: string, kind: ReportKind, round: number, seat: SeatReport): Promise<SeatResult> {
    const { userId } = seat;
    const user = await this.store.getUser(userId);
    if (!user) {
      return { userId, status: "unknown_user", credited: 0, openingNight: false, firstGameOfTheDay: false, xp: 0, level: 0 };
    }
    for (let attempt = 0; attempt < WRITE_ATTEMPTS; attempt++) {
      const saved = await this.store.getSave(userId, PROFILE_SLOT);
      const profile = profileOf(saved);
      const earlier = await this.store.getLedgerEntry(userId, matchId, kind, round);
      if (earlier) return this.result(userId, "duplicate", earlier.xp, profile, earlier.reason, await this.keepBoard(userId, seat));
      const nowMs = this.now();
      const openingNight = seat.openingNight === true && !profile.opening_night;
      const firstGame =
        seat.bonusDay !== undefined && seat.bonusDay > profile.bonus_day && dayPlausible(seat.bonusDay, nowMs);
      const wanted = seat.xp + (openingNight ? OPENING_NIGHT_XP : 0) + (firstGame ? FIRST_GAME_OF_THE_DAY_XP : 0);
      const room = Math.max(0, NIGHT_CAP - (await this.store.ledgerTotal(userId, matchId)));
      const credited = Math.min(wanted, room);
      const next: ProfileData = { ...profile, xp: Math.min(profile.xp + credited, MAX_PROFILE_XP) };
      if (seat.openingNight === true) next.opening_night = true;
      if (firstGame) next.bonus_day = seat.bonusDay!;
      if (seat.done?.length) {
        const merged = new Set([...profile.done, ...seat.done]);
        next.done = [...merged].slice(0, MAX_DONE);
      }
      const reason = { lines: seat.lines ?? {}, openingNight, firstGameOfTheDay: firstGame, requested: seat.xp };
      const ledger: LedgerEntry = { userId, matchId, kind, round, xp: credited, reason, at: nowMs };
      try {
        const written = await this.store.putSave(userId, PROFILE_SLOT, { schemaVersion: 1, data: next }, saved?.revision ?? 0, ledger);
        return this.result(userId, "paid", credited, profileOf(written), reason, await this.keepBoard(userId, seat));
      } catch (error) {
        if (error instanceof DuplicateLedger) continue; // read again: the next pass sees the entry and says `duplicate`
        if (error instanceof RevisionConflict) continue; // the client (or another report) wrote first: add on top of theirs
        throw error;
      }
    }
    throw new RevisionConflict(0);
  }

  /**
   * Stores the board a seat reported over the challenges slot. A report applied again writes it again (a board is a
   * snapshot, and a retry is how a board the first attempt lost gets through), and a board that is refused never
   * takes the XP with it.
   */
  private async keepBoard(userId: string, seat: SeatReport): Promise<SeatResult["board"]> {
    const board = seat.board;
    if (!board) return undefined;
    try {
      checkSave(board.schemaVersion, board.data);
    } catch (error) {
      if (error instanceof SaveRejected) return "refused";
      throw error;
    }
    if (Buffer.byteLength(JSON.stringify(board.data)) > MAX_SAVE_BYTES) return "refused";
    for (let attempt = 0; attempt < WRITE_ATTEMPTS; attempt++) {
      const saved = await this.store.getSave(userId, CHALLENGES_SLOT);
      try {
        await this.store.putSave(userId, CHALLENGES_SLOT, { schemaVersion: board.schemaVersion, data: board.data }, saved?.revision ?? 0);
        return "saved";
      } catch (error) {
        if (!(error instanceof RevisionConflict)) throw error; // the player's own client wrote first: read again, write on top
      }
    }
    return "refused";
  }

  private result(
    userId: string,
    status: "paid" | "duplicate",
    credited: number,
    profile: ProfileData,
    reason: Record<string, unknown>,
    board: SeatResult["board"],
  ): SeatResult {
    this.known.set(userId, knownOf(profile));
    return {
      userId,
      status,
      credited,
      openingNight: reason.openingNight === true,
      firstGameOfTheDay: reason.firstGameOfTheDay === true,
      xp: profile.xp,
      level: levelOf(profile.xp),
      ...(board ? { board } : {}),
    };
  }
}
