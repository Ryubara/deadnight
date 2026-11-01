// The HTTP API. Everything is wired through `Deps`, so tests build the same app with stubs and in-memory parts.
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import { randomUUID, timingSafeEqual } from "node:crypto";
import type { Config } from "./config.ts";
import { type DiscordClient, DiscordUnavailable } from "./discord.ts";
import { type Lobby, LobbyFailure, type LobbyLimits, LobbyService } from "./lobbies.ts";
import { GameServerRegistry } from "./servers.ts";
import { checkSave, SaveRejected } from "./saves.ts";
import { RevisionConflict, type Store } from "./store.ts";
import { signToken, verifyToken } from "./tokens.ts";

export const SESSION_TTL_SECONDS = 60 * 60;
export const TICKET_TTL_SECONDS = 60;
export const MAX_SAVE_BYTES = 64 * 1024;
/** How often expired lobbies are dropped. */
export const LOBBY_SWEEP_MS = 30_000;

export interface Deps {
  config: Pick<Config, "sessionSecret" | "ticketSecret" | "gameServerSecret">;
  store: Store;
  discord: DiscordClient;
  registry: GameServerRegistry;
  /** Lobby clock and expiry times; tests inject their own. */
  now?: () => number;
  lobbyLimits?: LobbyLimits;
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
  already_in_lobby: 409,
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
  const lobbies = new LobbyService({
    allocate: (matchId) => registry.allocate(matchId),
    release: (matchId) => void registry.release(matchId),
    now: deps.now,
    limits: deps.lobbyLimits,
  });
  // A match its server stopped listing is over: its lobby goes with it.
  registry.onMatchEnded((matchId) => lobbies.matchEnded(matchId));
  const sweeper = setInterval(() => lobbies.sweep(), LOBBY_SWEEP_MS);
  sweeper.unref();
  app.addHook("onClose", async () => clearInterval(sweeper));

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
    if (error instanceof SaveRejected) return reply.code(422).send({ error: error.reason, ...error.detail });
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
        request.log.warn({ err: (error as Error).message }, "discord sign-in failed");
        if (error instanceof DiscordUnavailable) return reply.code(502).send({ error: "discord_unavailable" });
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
    return lobbyView(lobbies.view(request.params.id, request.userId));
  });

  app.post<{ Params: { id: string } }>("/lobbies/:id/leave", { onRequest: requireUser }, async (request, reply) => {
    lobbies.leave(request.params.id, request.userId);
    return reply.code(204).send();
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
    const { server } = lobby.match;
    // Bound to one server (it rejects another server's ticket) and single use (`jti`).
    const ticket = signToken(config.ticketSecret, "ticket", seat.userId, TICKET_TTL_SECONDS, {
      matchId: lobby.match.id,
      serverId: server.id,
      jti: randomUUID(),
      name: seat.name,
    });
    return { matchId: lobby.match.id, address: { url: server.url, activityPath: server.activityPath }, ticket };
  });

  // ---- saves
  // A save is `{revision, schemaVersion, data}`. `revision` is for concurrency, `schemaVersion` says how to read
  // `data` (the game migrates; the backend only refuses versions it does not know), `data` is opaque to the backend.
  const slotParams = { type: "object", properties: { slot: { type: "string", pattern: "^[a-z0-9_-]{1,32}$" } } };

  app.get<{ Params: { slot: string } }>(
    "/saves/:slot",
    { onRequest: requireUser, schema: { params: slotParams } },
    async (request, reply) => {
      const save = await store.getSave(request.userId, request.params.slot);
      return save ?? reply.code(404).send({ error: "not_found" });
    },
  );

  app.put<{ Params: { slot: string }; Body: { revision: number; schemaVersion: number; data: Record<string, unknown> } }>(
    "/saves/:slot",
    {
      onRequest: requireUser,
      schema: {
        params: slotParams,
        body: {
          type: "object",
          required: ["revision", "schemaVersion", "data"],
          properties: {
            revision: { type: "integer", minimum: 0 },
            schemaVersion: { type: "integer", minimum: 1 },
            data: { type: "object" },
          },
        },
      },
    },
    async (request) => {
      const { revision, schemaVersion, data } = request.body;
      checkSave(schemaVersion, data);
      return store.putSave(request.userId, request.params.slot, { schemaVersion, data }, revision);
    },
  );

  // ---- game servers (called by the headless Godot servers, never by players)
  app.post<{ Body: { id: string; url: string; activityPath: string; capacity: number; matchIds?: string[] } }>(
    "/internal/servers/heartbeat",
    {
      onRequest: requireGameServer,
      schema: {
        body: {
          type: "object",
          required: ["id", "url", "activityPath", "capacity"],
          properties: {
            id: { type: "string", maxLength: 64 },
            url: { type: "string", maxLength: 256, pattern: "^wss?://\\S+$" },
            activityPath: { type: "string", maxLength: 128, pattern: "^/\\S*$" },
            capacity: { type: "integer", minimum: 0 },
            // The matches the server is running now; one it stops listing (after a grace) counts as ended.
            matchIds: { type: "array", maxItems: 1024, items: { type: "string", minLength: 1, maxLength: 64 } },
          },
        },
      },
    },
    async (request, reply) => {
      registry.heartbeat({ ...request.body, matchIds: request.body.matchIds ?? [] });
      return reply.code(204).send();
    },
  );

  // The game server says a match is over: its slot is free and its lobby goes. Idempotent.
  app.post<{ Params: { matchId: string } }>(
    "/internal/matches/:matchId/end",
    {
      onRequest: requireGameServer,
      schema: { params: { type: "object", properties: { matchId: { type: "string", minLength: 1, maxLength: 64 } } } },
    },
    async (request, reply) => {
      lobbies.matchEnded(request.params.matchId);
      return reply.code(204).send();
    },
  );

  return app;
}
