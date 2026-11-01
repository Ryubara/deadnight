// What the Activity does, as a small test client: sign in, lobby, ticket, connect to the game server.
import { WebSocket } from "ws";

export interface Session {
  token: string;
  userId: string;
  name: string;
}

async function call<T>(base: string, method: string, path: string, token: string | null, body?: unknown): Promise<T> {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = response.status === 204 ? null : await response.json();
  if (!response.ok) throw new Error(`${method} ${path} -> ${response.status} ${JSON.stringify(json)}`);
  return json as T;
}

export async function signIn(base: string, code: string): Promise<Session> {
  const body = await call<{ token: string; user: { id: string; name: string } }>(base, "POST", "/auth/discord", null, { code });
  return { token: body.token, userId: body.user.id, name: body.user.name };
}

export const api = {
  createLobby: (base: string, s: Session, body: object = {}) => call<{ id: string; code: string }>(base, "POST", "/lobbies", s.token, body),
  joinByCode: (base: string, s: Session, code: string) => call<{ id: string }>(base, "POST", "/lobbies/join-by-code", s.token, { code }),
  start: (base: string, s: Session, id: string) => call<{ matchId: string }>(base, "POST", `/lobbies/${id}/start`, s.token),
  ticket: (base: string, s: Session, id: string) =>
    call<{ matchId: string; ticket: string; address: { url: string; activityPath: string } }>(base, "POST", `/lobbies/${id}/ticket`, s.token),
};

/** Connects with the ticket and resolves with the server's first message. */
export function connect(url: string, ticket: string): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(`${url}?ticket=${encodeURIComponent(ticket)}`);
    socket.once("message", (data) => {
      socket.close();
      resolve(JSON.parse(data.toString()) as Record<string, unknown>);
    });
    socket.once("close", (code) => reject(new Error(`closed ${code}`)));
    socket.once("error", reject);
  });
}
