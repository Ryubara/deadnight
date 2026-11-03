// The rules of a match that its host chooses before the night begins (the game's `MatchSettings`,
// game/gameplay/rules/match_settings.gd). The backend does not play them: it checks the host's answer is one the
// game would take, keeps it on the lobby and signs it into every ticket of the match, so the game server that opens
// the room applies them (docs/research/platform-backend.md, "Match settings"). The keys are the game's own, so the
// game server reads them with `MatchSettings.from_dict` as they are. The bounds mirror `MatchSettings` and
// `RoundTuning.alive_cap_ceiling`; the game server checks again, so a drift here costs a refused value, not a crash.
// The map is an id of the game's `MapRegistry` (game/world/maps/): only a map that can be played is taken, and a
// settings object without one means the default map (a game from before the choice sends none).

export interface MatchSettings {
  /** The night's intensity, 0.25 to 5. */
  count_multiplier: number;
  /** Most zombies alive at once; 0 is the tuned curve. */
  max_alive: number;
  /** Seconds of break between rounds; 0 is the tuned break, else 1 to 120. */
  break_seconds: number;
  /** The id of the map the night is played on; absent means `DEFAULT_MAP`. */
  map?: string;
  /** Bots that fill the empty seats of the night, 0 to 7 (the room takes only as many as the people leave free). Absent: 0. */
  bots?: number;
  /** How well the bots play: 0 rookie, 1 regular, 2 veteran. Absent: 1. */
  bot_skill?: number;
}

export const MIN_COUNT_MULTIPLIER = 0.25;
export const MAX_COUNT_MULTIPLIER = 5;
export const MAX_ALIVE = 120;
export const MIN_BREAK = 1;
export const MAX_BREAK = 120;
export const MAX_BOTS = 7;
export const MAX_BOT_SKILL = 2;

/** The map every night had before there was a choice. */
export const DEFAULT_MAP = "drive_in";
/** The maps the game can play now (its `MapRegistry.playable`, which a game test compares this list with). */
export const PLAYABLE_MAPS = ["drive_in"];

/** The keys every settings object has; `map` and `bots` may be left out by a client from before them (default map, 0 bots). */
const KEYS = ["count_multiplier", "max_alive", "break_seconds"];
const OPTIONAL_KEYS = ["map", "bots", "bot_skill"];

const inRange = (value: unknown, low: number, high: number): value is number =>
  typeof value === "number" && Number.isFinite(value) && value >= low && value <= high;

/** The settings `value` holds, or null when it is not the three keys (and optionally a map, bots and their skill), each in its bounds. */
export function parseSettings(value: unknown): MatchSettings | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const given = value as Record<string, unknown>;
  const known = [...KEYS, ...OPTIONAL_KEYS];
  if (!KEYS.every((key) => key in given) || !Object.keys(given).every((key) => known.includes(key))) return null;
  const { count_multiplier, max_alive, break_seconds, map } = given;
  const bots = "bots" in given ? given.bots : undefined;
  const botSkill = "bot_skill" in given ? given.bot_skill : undefined;
  if (!inRange(count_multiplier, MIN_COUNT_MULTIPLIER, MAX_COUNT_MULTIPLIER)) return null;
  if (!inRange(max_alive, 0, MAX_ALIVE) || !Number.isInteger(max_alive)) return null;
  if (break_seconds !== 0 && !inRange(break_seconds, MIN_BREAK, MAX_BREAK)) return null;
  if (map !== undefined && !(typeof map === "string" && PLAYABLE_MAPS.includes(map))) return null;
  if (bots !== undefined && (!inRange(bots, 0, MAX_BOTS) || !Number.isInteger(bots))) return null;
  if (botSkill !== undefined && (!inRange(botSkill, 0, MAX_BOT_SKILL) || !Number.isInteger(botSkill))) return null;
  const out: MatchSettings = { count_multiplier, max_alive, break_seconds: break_seconds as number };
  return {
    ...out,
    ...(map === undefined ? {} : { map: map as string }),
    ...(bots === undefined ? {} : { bots }),
    ...(botSkill === undefined ? {} : { bot_skill: botSkill }),
  };
}
