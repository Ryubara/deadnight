// Stand-in for the headless Godot server, so the whole handoff can be tested without Godot. It does what the real
// one must do: announce itself to the backend, and admit only players that hold a valid ticket: signed with the
// ticket secret, unexpired, issued for THIS server, and not used before. The ticket arrives as the first WebSocket
// message, never in the URL.
import { type RawData, WebSocket, WebSocketServer } from "ws";
import { verifyToken } from "./tokens.ts";

export interface StubGameServerOptions {
  id: string;
  port: number;
  ticketSecret: string;
  /** Where players reach this server from outside Discord. */
  publicUrl: string;
  /** The Activity proxy path mapped to this server. */
  activityPath: string;
  capacity?: number;
  /** Backend base URL and shared secret for heartbeats; omit to run without a backend. */
  backendUrl?: string;
  gameServerSecret?: string;
  heartbeatMs?: number;
  /** How long a new socket may stay silent before it is closed. */
  joinTimeoutMs?: number;
}

/** The close code for every refused join (bad, expired, foreign or replayed ticket); the reason says which. */
export const CLOSE_BAD_TICKET = 4401;
export const CLOSE_NO_TICKET = 4408;
export const CLOSE_REPLACED = 4409;
export const CLOSE_MATCH_ENDED = 4410;
/** A join message is a few hundred bytes; nothing larger is read from a socket that has not been admitted yet. */
const MAX_PAYLOAD_BYTES = 4096;

export async function startStubGameServer(options: StubGameServerOptions) {
  const matches = new Set<string>();
  /** Ticket ids already used, until the ticket would have expired anyway. */
  const usedTickets = new Map<string, number>();
  /** One live socket per seat: a new join replaces the old connection. */
  const seats = new Map<string, WebSocket>();
  const wss = new WebSocketServer({ port: options.port, maxPayload: MAX_PAYLOAD_BYTES });
  await new Promise<void>((resolve) => wss.once("listening", resolve));

  /** Returns the reason a join is refused, or null after admitting the socket. */
  const admit = (socket: WebSocket, data: RawData, isBinary: boolean): string | null => {
    let message: { type?: unknown; ticket?: unknown };
    try {
      if (isBinary) return "join must be text";
      message = JSON.parse(data.toString()) as typeof message;
    } catch {
      return "join must be JSON";
    }
    if (message === null || message.type !== "join" || typeof message.ticket !== "string") return "expected a join message";
    const claims = verifyToken(options.ticketSecret, "ticket", message.ticket);
    if (!claims || typeof claims.matchId !== "string") return "bad ticket";
    if (claims.serverId !== options.id) return "ticket is for another server";
    if (typeof claims.jti !== "string") return "bad ticket";
    const now = Math.floor(Date.now() / 1000);
    for (const [jti, exp] of usedTickets) if (exp <= now) usedTickets.delete(jti);
    if (usedTickets.has(claims.jti)) return "ticket already used";
    usedTickets.set(claims.jti, claims.exp);

    matches.add(claims.matchId);
    const seat = `${claims.matchId}/${claims.sub}`;
    seats.get(seat)?.close(CLOSE_REPLACED, "replaced by a newer connection");
    seats.set(seat, socket);
    socket.once("close", () => {
      if (seats.get(seat) === socket) seats.delete(seat);
    });
    // The level, icon and XP are the backend's word in the ticket, passed on as they are (the real server shows them over heads).
    const { level, icon, xp } = claims as { level?: number; icon?: string; xp?: number };
    socket.send(JSON.stringify({ type: "welcome", serverId: options.id, matchId: claims.matchId, userId: claims.sub, name: claims.name, level, icon, xp }));
    return null;
  };

  wss.on("connection", (socket) => {
    const silence = setTimeout(() => socket.close(CLOSE_NO_TICKET, "no ticket"), options.joinTimeoutMs ?? 5000);
    socket.once("close", () => clearTimeout(silence));
    socket.once("message", (data, isBinary) => {
      clearTimeout(silence);
      const refusal = admit(socket, data, isBinary);
      if (refusal) socket.close(CLOSE_BAD_TICKET, refusal);
    });
  });

  const backendHeaders = { "Content-Type": "application/json", Authorization: `Bearer ${options.gameServerSecret}` };

  const beat = async (): Promise<void> => {
    if (!options.backendUrl) return;
    try {
      await fetch(`${options.backendUrl}/internal/servers/heartbeat`, {
        method: "POST",
        headers: backendHeaders,
        body: JSON.stringify({
          id: options.id,
          url: options.publicUrl,
          activityPath: options.activityPath,
          capacity: options.capacity ?? 10,
          matchIds: [...matches],
        }),
      });
    } catch {
      // The backend may still be starting; the next beat retries.
    }
  };
  await beat();
  const timer = setInterval(() => void beat(), options.heartbeatMs ?? 5000);

  return {
    port: (wss.address() as { port: number }).port,
    /** The match is over (the real server does this when the game concludes): tell the backend, free the slot. */
    async endMatch(matchId: string): Promise<void> {
      matches.delete(matchId);
      for (const [seat, socket] of seats) if (seat.startsWith(`${matchId}/`)) socket.close(CLOSE_MATCH_ENDED, "match ended");
      if (options.backendUrl) {
        await fetch(`${options.backendUrl}/internal/matches/${encodeURIComponent(matchId)}/end`, {
          method: "POST",
          headers: backendHeaders,
        });
      }
    },
    /**
     * A round (or the night) is over: post each seat's XP to the backend, as the real server does at a round's end
     * (never per kill). Resolves with the backend's answer, a result per seat.
     */
    async report(matchId: string, kind: "round" | "night", round: number, seats: { userId: string; xp: number }[]): Promise<unknown> {
      const response = await fetch(`${options.backendUrl}/internal/matches/${encodeURIComponent(matchId)}/report`, {
        method: "POST",
        headers: backendHeaders,
        body: JSON.stringify({ kind, round, seats }),
      });
      if (!response.ok) throw new Error(`report -> ${response.status}`);
      return response.json();
    },
    async close(): Promise<void> {
      clearInterval(timer);
      for (const client of wss.clients) client.terminate();
      await new Promise<void>((resolve) => wss.close(() => resolve()));
    },
  };
}

// Run as a process: configuration from the environment.
if (import.meta.main) {
  const env = process.env;
  const need = (name: string): string => {
    const value = env[name];
    if (!value) throw new Error(`environment variable ${name} is required`);
    return value;
  };
  const server = await startStubGameServer({
    id: env.GAME_SERVER_ID ?? "gs-1",
    port: Number(env.PORT ?? 8080),
    ticketSecret: need("TICKET_SECRET"),
    publicUrl: need("PUBLIC_URL"),
    activityPath: env.ACTIVITY_PATH ?? "/gs/1",
    backendUrl: need("BACKEND_URL"),
    gameServerSecret: need("GAME_SERVER_SECRET"),
  });
  console.log(JSON.stringify({ msg: "game server stub listening", port: server.port }));
  const stop = () => void server.close().then(() => process.exit(0));
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);
}
