// The HTTP API. Everything is wired through `Deps`, so tests build the same app with stubs and in-memory parts.
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import { timingSafeEqual } from "node:crypto";
import type { Config } from "./config.ts";
import type { DiscordClient } from "./discord.ts";
import { type Lobby, LobbyFailure, LobbyService } from "./lobbies.ts";
import { GameServerRegistry } from "./servers.ts";
import { RevisionConflict, type Store } from "./store.ts";
import { signToken, verifyToken } from "./tokens.ts";

export const SESSION_TTL_SECONDS = 60 * 60;
export const TICKET_TTL_SECONDS = 60;
export const MAX_SAVE_BYTES = 64 * 1024;

export interface Deps {
  config: Pick<Config, "sessionSecret" | "ticketSecret" | "gameServerSecret">;
  store: Store;
  discord: DiscordClient;
  registry: GameServerRegistry;
  logger?: boolean | object;
}

declare module "fastify" {
  interface FastifyRequest {
    userId: string;
  }
}

const LOBBY_STATUS: Record<string, number> = {
  not_found: 404,
  full: 409,
  not_host: 403,
  already_started: 409,
  no_server: 503,
  not_started: 409,
  not_member: 403,
};

function sameSecret(given: string, expected: string): boolean {
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function buildApp(deps: Deps): FastifyInstance {
  const { config, store, discord, registry } = deps;
  const app = Fastify({
    logger: deps.logger ?? false,
    bodyLimit: MAX_SAVE_BYTES + 1024,
    // Heartbeats and health checks arrive every few seconds and would drown the log.
    disableRequestLogging: (request) => request.url === "/health" || request.url.startsWith("/internal/"),
  });
  const lobbies = new LobbyService(() => registry.allocate());

  const bearer = (request: FastifyRequest): string | null => {
    const header = request.headers.authorization;
    return header?.startsWith("Bearer ") ? header.slice(7) : null;
  };

  const requireUser = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const token = bearer(request);
    const claims = token ? verifyToken(config.sessionSecret, "session", token) : null;
    if (!claims) return reply.code(401).send({ error: "unauthorized" });
    request.userId = claims.sub;
  };

  const requireGameServer = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const token = bearer(request);
    if (!token || !sameSecret(token, config.gameServerSecret)) return reply.code(401).send({ error: "unauthorized" });
  };

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof LobbyFailure) return reply.code(LOBBY_STATUS[error.reason] ?? 400).send({ error: error.reason });
    if (error instanceof RevisionConflict) return reply.code(409).send({ error: "revision_conflict", revision: error.currentRevision });
    const status = (error as { statusCode?: number }).statusCode ?? 500;
    if (status >= 500) app.log.error({ err: error }, "unhandled error");
    return reply.code(status).send({ error: status >= 500 ? "internal" : "bad_request" });
  });

  // ---- operations
  app.get("/health", async () => ({ status: "ok" }));
  app.get("/ready", async (_request, reply) => {
    try {
      await store.ping();
      return { status: "ready", gameServers: registry.alive().length };
    } catch {
      return reply.code(503).send({ status: "database_unavailable" });
    }
  });

  // ---- sign-in
  app.post<{ Body: { code: string } }>(
    "/auth/discord",
    { schema: { body: { type: "object", required: ["code"], properties: { code: { type: "string", maxLength: 512 } } } } },
    async (request, reply) => {
      let signIn;
      try {
        signIn = await discord.exchangeCode(request.body.code);
      } catch (error) {
        request.log.warn({ err: (error as Error).message }, "discord sign-in rejected");
        return reply.code(401).send({ error: "invalid_code" });
      }
      const user = await store.upsertUser(signIn.user.id, signIn.user.username);
      const token = signToken(config.sessionSecret, "session", user.id, SESSION_TTL_SECONDS, { name: user.name });
      // access_token goes back because the Embedded App SDK needs it for authenticate().
      return { token, expiresIn: SESSION_TTL_SECONDS, access_token: signIn.accessToken, user: { id: user.id, name: user.name } };
    },
  );

  // ---- lobbies
  const lobbyView = (lobby: Lobby) => ({
    id: lobby.id,
    code: lobby.code,
    instanceId: lobby.instanceId,
    hostId: lobby.hostId,
    maxPlayers: lobby.maxPlayers,
    members: lobby.members,
    state: lobby.state,
    matchId: lobby.match?.id ?? null,
  });

  const member = async (userId: string) => {
    const user = await store.getUser(userId);
    if (!user) throw new LobbyFailure("not_found");
    return { userId: user.id, name: user.name };
  };

  app.post<{ Body: { maxPlayers?: number; instanceId?: string } }>(
    "/lobbies",
    {
      onRequest: requireUser,
      schema: {
        body: {
          type: "object",
          properties: { maxPlayers: { type: "integer", minimum: 1, maximum: 8 }, instanceId: { type: "string", maxLength: 128 } },
        },
      },
    },
    async (request, reply) => {
      const { maxPlayers = 4, instanceId = null } = request.body ?? {};
      // One open lobby per Activity instance: friends in the same voice-channel Activity land in the same lobby.
      const existing = instanceId ? lobbies.findByInstance(instanceId) : null;
      const lobby = existing ? lobbies.join(existing.id, await member(request.userId)) : lobbies.create(await member(request.userId), maxPlayers, instanceId);
      return reply.code(existing ? 200 : 201).send(lobbyView(lobby));
    },
  );

  app.post<{ Body: { code: string } }>(
    "/lobbies/join-by-code",
    { onRequest: requireUser, schema: { body: { type: "object", required: ["code"], properties: { code: { type: "string", maxLength: 16 } } } } },
    async (request) => {
      const found = lobbies.findByCode(request.body.code);
      if (!found) throw new LobbyFailure("not_found");
      return lobbyView(lobbies.join(found.id, await member(request.userId)));
    },
  );

  app.get<{ Params: { id: string } }>("/lobbies/:id", { onRequest: requireUser }, async (request) => {
    const lobby = lobbies.get(request.params.id);
    if (!lobbies.isMember(lobby, request.userId)) throw new LobbyFailure("not_member");
    return lobbyView(lobby);
  });

  app.post<{ Params: { id: string } }>("/lobbies/:id/start", { onRequest: requireUser }, async (request) =>
    lobbyView(lobbies.start(request.params.id, request.userId)),
  );

  // The handoff: a member of a started lobby gets the game server's address and a one-minute ticket for their seat.
  app.post<{ Params: { id: string } }>("/lobbies/:id/ticket", { onRequest: requireUser }, async (request) => {
    const lobby = lobbies.get(request.params.id);
    const seat = lobby.members.find((m) => m.userId === request.userId);
    if (!seat) throw new LobbyFailure("not_member");
    if (!lobby.match) throw new LobbyFailure("not_started");
    const ticket = signToken(config.ticketSecret, "ticket", seat.userId, TICKET_TTL_SECONDS, {
      matchId: lobby.match.id,
      name: seat.name,
    });
    const { server } = lobby.match;
    return { matchId: lobby.match.id, address: { url: server.url, activityPath: server.activityPath }, ticket };
  });

  // ---- saves
  app.get<{ Params: { slot: string } }>("/saves/:slot", { onRequest: requireUser }, async (request, reply) => {
    const save = await store.getSave(request.userId, request.params.slot);
    return save ?? reply.code(404).send({ error: "not_found" });
  });

  app.put<{ Params: { slot: string }; Body: { revision: number; data: Record<string, unknown> } }>(
    "/saves/:slot",
    {
      onRequest: requireUser,
      schema: {
        params: { type: "object", properties: { slot: { type: "string", pattern: "^[a-z0-9_-]{1,32}$" } } },
        body: {
          type: "object",
          required: ["revision", "data"],
          properties: { revision: { type: "integer", minimum: 0 }, data: { type: "object" } },
        },
      },
    },
    async (request) => store.putSave(request.userId, request.params.slot, request.body.data, request.body.revision),
  );

  // ---- game servers (called by the headless Godot servers, never by players)
  app.post<{ Body: { id: string; url: string; activityPath: string; capacity: number; matches: number } }>(
    "/internal/servers/heartbeat",
    {
      onRequest: requireGameServer,
      schema: {
        body: {
          type: "object",
          required: ["id", "url", "activityPath", "capacity", "matches"],
          properties: {
            id: { type: "string", maxLength: 64 },
            url: { type: "string", maxLength: 256 },
            activityPath: { type: "string", maxLength: 128 },
            capacity: { type: "integer", minimum: 0 },
            matches: { type: "integer", minimum: 0 },
          },
        },
      },
    },
    async (request, reply) => {
      registry.heartbeat(request.body);
      return reply.code(204).send();
    },
  );

  return app;
}
