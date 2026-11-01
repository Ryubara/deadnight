// The pool of running game servers. Railway cannot start a container per match from inside a request without its
// API (a cloud-resource decision), so the spike uses a static pool: each headless Godot server announces itself with
// a heartbeat, and the backend hands matches to the least loaded one that is alive.

export interface GameServerInfo {
  id: string;
  /** Public WebSocket URL, for clients outside Discord (web build, tests). */
  url: string;
  /** Path under the Activity's discordsays.com proxy that the Developer Portal maps to this server. */
  activityPath: string;
  capacity: number;
  matches: number;
}

interface Entry extends GameServerInfo {
  seenAt: number;
}

export class GameServerRegistry {
  private readonly entries = new Map<string, Entry>();

  private readonly staleAfterMs: number;
  private readonly now: () => number;

  constructor(staleAfterMs: number = 15_000, now: () => number = Date.now) {
    this.staleAfterMs = staleAfterMs;
    this.now = now;
  }

  heartbeat(info: GameServerInfo): void {
    this.entries.set(info.id, { ...info, seenAt: this.now() });
  }

  alive(): GameServerInfo[] {
    const cutoff = this.now() - this.staleAfterMs;
    return [...this.entries.values()].filter((entry) => entry.seenAt >= cutoff);
  }

  /** Picks the least loaded live server with room and counts the match against it until the next heartbeat. */
  allocate(): GameServerInfo | null {
    const candidates = this.alive().filter((server) => server.matches < server.capacity);
    candidates.sort((a, b) => a.matches / a.capacity - b.matches / b.capacity);
    const chosen = candidates[0];
    if (!chosen) return null;
    const entry = this.entries.get(chosen.id)!;
    entry.matches += 1;
    return { ...chosen, matches: entry.matches };
  }
}
