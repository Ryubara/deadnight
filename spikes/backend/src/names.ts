// The names players see: what a guest typed, or what Discord calls someone. Anyone can send anything to the backend,
// so every name is cleaned here, once, before it is stored, shown on a scoreboard or signed into a ticket.

/** The longest name a player has, in characters. */
export const MAX_NAME = 24;

// A basic filter, not a moderation system: the words nobody wants under a friend's head on a scoreboard. A stem
// matches inside a word (the long ones that no honest word contains); the rest match whole words only, so a name
// like "Dickinson", "Cockburn" or "Scunthorpe" stays.
const STEMS = ["fuck", "shit", "nigg", "faggot", "bitch", "whore", "pussy", "bastard", "asshole"];
const WORDS = ["cunt", "slut", "dick", "cock", "fag", "retard", "rape", "rapist", "nazi", "cum", "tits", "twat", "wank"];

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", $: "s", "!": "i" };

/** The text with look-alike digits and marks read as letters, lowercase and without accents. */
function plain(text: string): string {
  const folded = text.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase();
  return [...folded].map((c) => LEET[c] ?? c).join("");
}

/** Whether a name passes the basic filter (spacing and symbols between letters do not hide a word). */
export function isClean(name: string): boolean {
  const text = plain(name);
  const squashed = text.replace(/[^a-z]/g, "");
  if (STEMS.some((stem) => squashed.includes(stem))) return false;
  // "d i c k" and "d.i.c.k" are one word: a run of single letters is joined before the whole-word check.
  const words: string[] = [];
  let run = "";
  for (const token of text.split(/[^a-z]+/).filter(Boolean)) {
    if (token.length === 1) {
      run += token;
      continue;
    }
    if (run) words.push(run);
    run = "";
    words.push(token);
  }
  if (run) words.push(run);
  return !words.some((word) => WORDS.includes(word));
}

/** The name with only letters, digits, spaces and a few marks, spaces squeezed, at most `MAX_NAME` characters; "" if none is left. */
export function tidy(given: string | undefined | null): string {
  const kept = (given ?? "").replace(/[^\p{L}\p{N} _.'-]/gu, "");
  return [...kept.replace(/ +/g, " ").trim()].slice(0, MAX_NAME).join("").trim();
}

/** `Guest 1234`: what a guest who gave no (or no usable) name is called. */
export function fallbackName(prefix = "Guest"): string {
  return `${prefix} ${1000 + Math.floor(Math.random() * 9000)}`;
}

/** The first of `candidates` that is left after tidying and passes the filter, else null. */
export function firstUsable(candidates: Array<string | undefined | null>): string | null {
  for (const candidate of candidates) {
    const name = tidy(candidate);
    if (name.length > 0 && isClean(name)) return name;
  }
  return null;
}

/** The first of `candidates` that is left after tidying and passes the filter, else `Guest 1234` (or `prefix`). */
export function chooseName(candidates: Array<string | undefined | null>, prefix = "Guest"): string {
  return firstUsable(candidates) ?? fallbackName(prefix);
}
