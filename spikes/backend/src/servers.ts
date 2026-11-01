// The pool of running game servers. Railway cannot start a container per match from inside a request without its
// API (a cloud-resource decision), so the spike uses a static pool: each headless Godot server announces itself with
// a heartbeat, and the backend hands matches to the least loaded one that is alive.
//
// Capacity is counted from the matches the BACKEND assigned (`allocate`), not from what a server reports it has
// seen: a started match nobody has joined yet is already a match. A match leaves the count when it ends (`release`,
// from the match-ended call, from the lobby's maximum age, or because the server's heartbeat stopped listing it).

export interface GameServerInfo {
  id: string;
  /** Public WebSocket URL, for clients outside Discord (web build, tests). */
  url: string;
  /** Path under the Activity's discordsays.com proxy that the Developer Portal maps to this server. */
  activityPath: string;
  capacity: number;
  /** Matches assigned to this server and not ended yet (computed by the registry, not reported by the server). */
  matches: number;
}

/** What a server announces in a heartbeat: itself, and the ids of the matches it is running right now. */
export interface Heartbeat {
  id: string;
  url: string;
  activityPath: string;
  capacity: number;
  matchIds: string[];
}

interface Entry {
  id: string;
  url: string;
  activityPath: string;
  capacity: number;
  seenAt: number;
}

interface Assignment {
  serverId: string;
  assignedAt: number;
}

/** How long a match may stay out of its server's heartbeat list before it counts as ended: time to join it. */
export const MATCH_JOIN_GRACE_MS = 5 * 60_000;

export class GameServerRegistry {
  private readonly entries = new Map<string, Entry>();
  private readonly assignments = new Map<string, Assignment>();
  private readonly endedListeners: ((matchId: string) => void)[] = [];

  private readonly staleAfterMs: number;
  private readonly now: () => number;
  private readonly joinGraceMs: number;

  constructor(staleAfterMs: number = 15_000, now: () => number = Date.now, joinGraceMs: number = MATCH_JOIN_GRACE_MS) {
    this.staleAfterMs = staleAfterMs;
    this.now = now;
    this.joinGraceMs = joinGraceMs;
  }

  /** Called with the id of every match the registry stops counting because the server no longer lists it. */
  onMatchEnded(listener: (matchId: string) => void): void {
    this.endedListeners.push(listener);
  }

  heartbeat(beat: Heartbeat): void {
    const now = this.now();
    this.entries.set(beat.id, { id: beat.id, url: beat.url, activityPath: beat.activityPath, capacity: beat.capacity, seenAt: now });
    const listed = new Set(beat.matchIds);
    // A running match the backend does not know (it restarted since) still takes a slot.
    for (const matchId of listed) {
      if (!this.assignments.has(matchId)) this.assignments.set(matchId, { serverId: beat.id, assignedAt: now });
    }
    // An assigned match the server does not list: still being joined (inside the grace) or over.
    for (const [matchId, assignment] of [...this.assignments]) {
      if (assignment.serverId !== beat.id || listed.has(matchId)) continue;
      if (now - assignment.assignedAt >= this.joinGraceMs && this.release(matchId)) {
        for (const listener of this.endedListeners) listener(matchId);
      }
    }
  }

  private load(serverId: string): number {
    let count = 0;
    for (const assignment of this.assignments.values()) if (assignment.serverId === serverId) count++;
    return count;
  }

  alive(): GameServerInfo[] {
    const cutoff = this.now() - this.staleAfterMs;
    return [...this.entries.values()]
      .filter((entry) => entry.seenAt >= cutoff)
      .map((entry) => ({
        id: entry.id,
        url: entry.url,
        activityPath: entry.activityPath,
        capacity: entry.capacity,
        matches: this.load(entry.id),
      }));
  }

  /** Picks the least loaded live server with room and assigns the match to it. */
  allocate(matchId: string): GameServerInfo | null {
    const candidates = this.alive().filter((server) => server.matches < server.capacity);
    candidates.sort((a, b) => a.matches / a.capacity - b.matches / b.capacity);
    const chosen = candidates[0];
    if (!chosen) return null;
    this.assignments.set(matchId, { serverId: chosen.id, assignedAt: this.now() });
    return { ...chosen, matches: chosen.matches + 1 };
  }

  /** The match is over: its slot is free again. Returns false when the registry was not counting it. */
  release(matchId: string): boolean {
    return this.assignments.delete(matchId);
  }
}
