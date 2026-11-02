// The rules of a match that its host chooses before the night begins (the game's `MatchSettings`,
// game/gameplay/rules/match_settings.gd). The backend does not play them: it checks the host's answer is one the
// game would take, keeps it on the lobby and signs it into every ticket of the match, so the game server that opens
// the room applies them (docs/research/platform-backend.md, "Match settings"). The keys are the game's own, so the
// game server reads them with `MatchSettings.from_dict` as they are. The bounds mirror `MatchSettings` and
// `RoundTuning.alive_cap_ceiling`; the game server checks again, so a drift here costs a refused value, not a crash.

export interface MatchSettings {
  /** The night's intensity, 0.25 to 5. */
  count_multiplier: number;
  /** Most zombies alive at once; 0 is the tuned curve. */
  max_alive: number;
  /** Seconds of break between rounds; 0 is the tuned break, else 1 to 120. */
  break_seconds: number;
}

export const MIN_COUNT_MULTIPLIER = 0.25;
export const MAX_COUNT_MULTIPLIER = 5;
export const MAX_ALIVE = 120;
export const MIN_BREAK = 1;
export const MAX_BREAK = 120;

const KEYS = ["count_multiplier", "max_alive", "break_seconds"];

const inRange = (value: unknown, low: number, high: number): value is number =>
  typeof value === "number" && Number.isFinite(value) && value >= low && value <= high;

/** The settings `value` holds, or null when it is not exactly the three keys, each in its bounds. */
export function parseSettings(value: unknown): MatchSettings | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const given = value as Record<string, unknown>;
  if (Object.keys(given).length !== KEYS.length || !KEYS.every((key) => key in given)) return null;
  const { count_multiplier, max_alive, break_seconds } = given;
  if (!inRange(count_multiplier, MIN_COUNT_MULTIPLIER, MAX_COUNT_MULTIPLIER)) return null;
  if (!inRange(max_alive, 0, MAX_ALIVE) || !Number.isInteger(max_alive)) return null;
  if (break_seconds !== 0 && !inRange(break_seconds, MIN_BREAK, MAX_BREAK)) return null;
  return { count_multiplier, max_alive, break_seconds: break_seconds as number };
}
