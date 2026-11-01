// The rules for what a save may contain. The backend stores `data` without understanding it, so it guards only the
// two things it can: the format version (a version it does not know is refused) and numbers JSON cannot carry.

/**
 * The save formats this backend accepts. `data` is opaque to the backend; the game owns its layout and migrates it.
 * To change the layout: add the new version here and deploy the backend first, then the game, which reads any known
 * version, migrates it and writes back the newest. Remove a version only when no client writes it any more.
 */
export const SAVE_SCHEMA_VERSIONS: readonly number[] = [1];

export const CURRENT_SAVE_SCHEMA_VERSION = 1;

/** A save the backend refuses to store because of what it contains, not because of who sent it. */
export class SaveRejected extends Error {
  readonly reason: "unsupported_schema_version" | "unsafe_integer";
  readonly detail: Record<string, unknown>;

  constructor(reason: SaveRejected["reason"], detail: Record<string, unknown>) {
    super(reason);
    this.reason = reason;
    this.detail = detail;
  }
}

/**
 * The path of the first number in `value` that JSON cannot carry exactly, or null. A number parsed from JSON is a
 * double: an integer of 2^53 or more has lost low digits (`JSON.parse("18446744073709551557")` gives
 * 18446744073709552000) and this cannot be undone, so it is refused before it is stored. 64-bit values (RNG states,
 * ids) must travel as decimal strings, or the whole snapshot as one base64 string of `var_to_bytes`.
 * Walks with a stack, not recursion, so a deeply nested save cannot overflow the call stack.
 */
export function findUnsafeNumber(value: unknown): string | null {
  const stack: [unknown, string][] = [[value, ""]];
  while (stack.length > 0) {
    const [current, path] = stack.pop()!;
    if (typeof current === "number") {
      if (Number.isInteger(current) && !Number.isSafeInteger(current)) return path === "" ? "/" : path;
    } else if (Array.isArray(current)) {
      current.forEach((item, index) => stack.push([item, `${path}/${index}`]));
    } else if (current !== null && typeof current === "object") {
      for (const [key, item] of Object.entries(current)) stack.push([item, `${path}/${key}`]);
    }
  }
  return null;
}

/** Throws `SaveRejected` when the backend must not store this save. */
export function checkSave(schemaVersion: number, data: unknown): void {
  if (!SAVE_SCHEMA_VERSIONS.includes(schemaVersion)) {
    throw new SaveRejected("unsupported_schema_version", { supported: SAVE_SCHEMA_VERSIONS, schemaVersion });
  }
  const unsafe = findUnsafeNumber(data);
  if (unsafe !== null) throw new SaveRejected("unsafe_integer", { path: unsafe.slice(0, 256) });
}
