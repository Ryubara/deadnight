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
  /** How many perks a player may carry: 0 the shop's own limit, 1 unlimited. Absent: 0. */
  perk_limit?: number;
}

export const MIN_COUNT_MULTIPLIER = 0.25;
export const MAX_COUNT_MULTIPLIER = 5;
export const MAX_ALIVE = 120;
export const MIN_BREAK = 1;
export const MAX_BREAK = 120;
export const MAX_BOTS = 7;
export const MAX_BOT_SKILL = 2;
export const MAX_PERK_LIMIT = 1;

/** The map every night had before there was a choice. */
export const DEFAULT_MAP = "drive_in";
/** The maps the game can play now (its `MapRegistry.playable`, which a game test compares this list with). */
export const PLAYABLE_MAPS = ["drive_in", "small_indoor"];

/** The keys every settings object has; `map` and `bots` may be left out by a client from before them (default map, 0 bots). */
const KEYS = ["count_multiplier", "max_alive", "break_seconds"];
const OPTIONAL_KEYS = ["map", "bots", "bot_skill", "perk_limit"];
/**
 * Every setting this backend takes, the game's `MatchSettings.KEYS`. `/health` publishes it, a test compares it with the
 * game's list, and the deploy script compares the live backend's with the checkout's, so a backend that is behind the
 * client is found, not discovered by a host whose choices vanish (Deadnight #944).
 */
export const SETTINGS_KEYS: readonly string[] = [...KEYS, ...OPTIONAL_KEYS];

const inRange = (value: unknown, low: number, high: number): value is number =>
  typeof value === "number" && Number.isFinite(value) && value >= low && value <= high;

/** What is wrong with the settings a client sent, in a sentence that names the setting (never a value). */
export type SettingsProblem = string;

/**
 * The settings `value` holds, or why it is not settings the game takes: a key that is not one of the game's
 * ("unknown setting a_rule"), a missing one, or one outside its bounds. Nothing is dropped silently.
 */
export function checkSettings(value: unknown): { settings: MatchSettings } | { problem: SettingsProblem } {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return { problem: "settings are not an object" };
  const given = value as Record<string, unknown>;
  const unknown = Object.keys(given).filter((key) => !SETTINGS_KEYS.includes(key));
  if (unknown.length > 0) return { problem: `unknown setting ${unknown.sort().join(", ")}` };
  const missing = KEYS.filter((key) => !(key in given));
  if (missing.length > 0) return { problem: `missing setting ${missing.join(", ")}` };
  const { count_multiplier, max_alive, break_seconds, map } = given;
  const bots = "bots" in given ? given.bots : undefined;
  const botSkill = "bot_skill" in given ? given.bot_skill : undefined;
  const perkLimit = "perk_limit" in given ? given.perk_limit : undefined;
  if (!inRange(count_multiplier, MIN_COUNT_MULTIPLIER, MAX_COUNT_MULTIPLIER)) return { problem: "bad count_multiplier" };
  if (!inRange(max_alive, 0, MAX_ALIVE) || !Number.isInteger(max_alive)) return { problem: "bad max_alive" };
  if (break_seconds !== 0 && !inRange(break_seconds, MIN_BREAK, MAX_BREAK)) return { problem: "bad break_seconds" };
  if (map !== undefined && !(typeof map === "string" && PLAYABLE_MAPS.includes(map))) return { problem: "bad map" };
  if (bots !== undefined && (!inRange(bots, 0, MAX_BOTS) || !Number.isInteger(bots))) return { problem: "bad bots" };
  if (botSkill !== undefined && (!inRange(botSkill, 0, MAX_BOT_SKILL) || !Number.isInteger(botSkill))) {
    return { problem: "bad bot_skill" };
  }
  if (perkLimit !== undefined && (!inRange(perkLimit, 0, MAX_PERK_LIMIT) || !Number.isInteger(perkLimit))) {
    return { problem: "bad perk_limit" };
  }
  const out: MatchSettings = { count_multiplier, max_alive, break_seconds: break_seconds as number };
  return {
    settings: {
      ...out,
      ...(map === undefined ? {} : { map: map as string }),
      ...(bots === undefined ? {} : { bots }),
      ...(botSkill === undefined ? {} : { bot_skill: botSkill }),
      ...(perkLimit === undefined ? {} : { perk_limit: perkLimit }),
    },
  };
}

/** The settings `value` holds, or null when `checkSettings` finds fault with it. */
export function parseSettings(value: unknown): MatchSettings | null {
  const checked = checkSettings(value);
  return "settings" in checked ? checked.settings : null;
}
