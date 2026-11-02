// A small fixed-window counter per key, for the routes anyone can call (guest sign-in). In memory, like the lobbies:
// one backend replica. The clock is injected, so tests move time by hand.
export class RateLimit {
  private readonly counts = new Map<string, { windowStart: number; count: number }>();
  private readonly max: number;
  private readonly windowMs: number;
  private readonly now: () => number;

  constructor(max: number, windowMs: number, now: () => number = Date.now) {
    this.max = max;
    this.windowMs = windowMs;
    this.now = now;
  }

  /** True (and counted) when `key` may act now; false once it has used its `max` in the window. */
  allow(key: string): boolean {
    const now = this.now();
    if (this.counts.size > 10_000) this.sweep(now);
    const entry = this.counts.get(key);
    if (!entry || now - entry.windowStart >= this.windowMs) {
      this.counts.set(key, { windowStart: now, count: 1 });
      return true;
    }
    if (entry.count >= this.max) return false;
    entry.count++;
    return true;
  }

  private sweep(now: number): void {
    for (const [key, entry] of this.counts) if (now - entry.windowStart >= this.windowMs) this.counts.delete(key);
  }
}
