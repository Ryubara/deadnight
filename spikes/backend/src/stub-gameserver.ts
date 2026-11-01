// Stand-in for the headless Godot server, so the whole handoff can be tested without Godot. It does what the real
// one must do: announce itself to the backend, and admit only players that hold a valid, unexpired ticket.
import { WebSocketServer } from "ws";
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
}

export const CLOSE_BAD_TICKET = 4401;

export async function startStubGameServer(options: StubGameServerOptions) {
  const matches = new Set<string>();
  const wss = new WebSocketServer({ port: options.port });
  await new Promise<void>((resolve) => wss.once("listening", resolve));

  wss.on("connection", (socket, request) => {
    const ticket = new URL(request.url ?? "/", "http://localhost").searchParams.get("ticket") ?? "";
    const claims = verifyToken(options.ticketSecret, "ticket", ticket);
    if (!claims || typeof claims.matchId !== "string") {
      socket.close(CLOSE_BAD_TICKET, "bad ticket");
      return;
    }
    matches.add(claims.matchId);
    socket.send(JSON.stringify({ type: "welcome", serverId: options.id, matchId: claims.matchId, userId: claims.sub, name: claims.name }));
  });

  const beat = async (): Promise<void> => {
    if (!options.backendUrl) return;
    try {
      await fetch(`${options.backendUrl}/internal/servers/heartbeat`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${options.gameServerSecret}` },
        body: JSON.stringify({
          id: options.id,
          url: options.publicUrl,
          activityPath: options.activityPath,
          capacity: options.capacity ?? 10,
          matches: matches.size,
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
