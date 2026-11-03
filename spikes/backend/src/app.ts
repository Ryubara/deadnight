// The HTTP API. Everything is wired through `Deps`, so tests build the same app with stubs and in-memory parts.
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest, LogController } from "fastify";
import { randomUUID, timingSafeEqual } from "node:crypto";
import type { Config } from "./config.ts";
import { type DiscordClient, DiscordUnavailable } from "./discord.ts";
import { RateLimit } from "./limits.ts";
import { type Lobby, LobbyFailure, type LobbyLimits, LobbyService, MAX_PLAYERS } from "./lobbies.ts";
import { chooseName } from "./names.ts";
import { DEFAULT_MAP } from "./settings.ts";
import { GameServerRegistry } from "./servers.ts";
import { checkSave, SaveRejected } from "./saves.ts";
import { RevisionConflict, type Store } from "./store.ts";
import { signToken, verifyToken } from "./tokens.ts";

export const SESSION_TTL_SECONDS = 60 * 60;
export const TICKET_TTL_SECONDS = 60;
export const MAX_SAVE_BYTES = 64 * 1024;
/** Guest sign-ins one address may make in an hour, and all addresses together. */
export const GUESTS_PER_ADDRESS_PER_HOUR = 30;
export const GUESTS_IN_ALL_PER_HOUR = 2000;
/** A guest's `discord_id` column: its own namespace, never a number like a Discord snowflake. */
export const GUEST_ID_PREFIX = "guest:";

/** The name a guest chose, cleaned (letters, digits, spaces, a few marks, no rude words), or `Guest 1234` when there is none. */
export function guestName(given: string | undefined): string {
  return chooseName([given]);
}
/** How often expired lobbies are dropped. */
export const LOBBY_SWEEP_MS = 30_000;

export interface Deps {
  config: Pick<Config, "sessionSecret" | "ticketSecret" | "gameServerSecret"> & Partial<Pick<Config, "guestSignIn" | "corsOrigins">>;
  store: Store;
  discord: DiscordClient;
  registry: GameServerRegistry;
  /** Lobby clock and expiry times; tests inject their own. */
  now?: () => number;
  lobbyLimits?: Partial<LobbyLimits>;
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
  bad_settings: 400,
};

function sameSecret(given: string, expected: string): boolean {
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

/**
 * A Discord Activity reaches this API through the URL mapping `/api` of the Developer Portal. Discord's docs do not say
 * whether the proxy strips the prefix before it forwards, so both are served: `/api/auth/guest` is `/auth/guest`.
 * No route of ours starts with `/api`.
 */
export function stripApiPrefix(url: string): string {
  const match = /^\/api(?=[/?]|$)/.exec(url);
  if (match === null) return url;
  const rest = url.slice(match[0].length);
  return rest.startsWith("/") ? rest : `/${rest}`;
}

export function buildApp(deps: Deps): FastifyInstance {
  const { config, store, discord, registry } = deps;
  const app = Fastify({
    logger: deps.logger ?? false,
    // Behind Railway's edge: the client's address is the first of X-Forwarded-For (for the guest sign-in limit).
    trustProxy: true,
    bodyLimit: MAX_SAVE_BYTES + 1024,
    rewriteUrl: (request) => stripApiPrefix(request.url ?? "/"),
    // Heartbeats and health checks arrive every few seconds and would drown the log. (The top-level
    // `disableRequestLogging` option is deprecated and goes in Fastify 6; the log controller replaces it.)
    logController: new LogController({
      disableRequestLogging: (request) => request.url === "/health" || request.url.startsWith("/internal/"),
    }),
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

  // The web build is another origin than this API: the pages named in CORS_ORIGINS may call it from a browser (the
  // answer to a preflight, and the allow header on every answer). Nobody else gets the header, so a page on another
  // site cannot read what a signed-in player's browser asks for. The Authorization header is the only credential.
  const corsOrigins = new Set(config.corsOrigins ?? []);
  app.addHook("onRequest", async (request, reply) => {
    const origin = request.headers.origin;
    if (origin === undefined || !corsOrigins.has(origin)) return;
    reply.header("Access-Control-Allow-Origin", origin);
    reply.header("Vary", "Origin");
    if (request.method === "OPTIONS") {
      reply.header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS");
      reply.header("Access-Control-Allow-Headers", "Authorization, Content-Type");
      reply.header("Access-Control-Max-Age", "600");
      return reply.code(204).send();
    }
  });

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
  // `guildId` is the server the Activity runs in (the SDK's `guildId`): with it the backend asks for the player's
  // nickname there. The name shown is the nickname, else Discord's display name, else the account's username.
  app.post<{ Body: { code: string; guildId?: string } }>(
    "/auth/discord",
    {
      schema: {
        body: {
          type: "object",
          required: ["code"],
          properties: { code: { type: "string", maxLength: 512 }, guildId: { type: "string", pattern: "^[0-9]{1,20}$" } },
        },
      },
    },
    async (request, reply) => {
      let signIn;
      try {
        signIn = await discord.exchangeCode(request.body.code, request.body.guildId);
      } catch (error) {
        request.log.warn({ err: (error as Error).message }, "discord sign-in failed");
        if (error instanceof DiscordUnavailable) return reply.code(502).send({ error: "discord_unavailable" });
        return reply.code(401).send({ error: "invalid_code" });
      }
      const { nick, globalName, username } = signIn.user;
      const user = await store.upsertUser(signIn.user.id, chooseName([nick, globalName, username], "Player"));
      const token = signToken(config.sessionSecret, "session", user.id, SESSION_TTL_SECONDS, { name: user.name });
      // access_token goes back because the Embedded App SDK needs it for authenticate().
      return { token, expiresIn: SESSION_TTL_SECONDS, access_token: signIn.accessToken, user: { id: user.id, name: user.name } };
    },
  );

  // Guests: a visitor with no Discord (the web build) gets a user of their own. The id is random and lives in its own
  // `guest:` namespace, so a guest can never be, or be mistaken for, a Discord user. Anyone can call this, so it is
  // limited per address and in all.
  const guestsPerAddress = new RateLimit(GUESTS_PER_ADDRESS_PER_HOUR, 60 * 60_000, deps.now);
  const guestsInAll = new RateLimit(GUESTS_IN_ALL_PER_HOUR, 60 * 60_000, deps.now);
  app.post<{ Body: { name?: string } }>(
    "/auth/guest",
    { schema: { body: { type: "object", properties: { name: { type: "string", maxLength: 64 } } } } },
    async (request, reply) => {
      if (!config.guestSignIn) return reply.code(404).send({ error: "not_found" });
      if (!guestsPerAddress.allow(request.ip) || !guestsInAll.allow("all")) {
        return reply.code(429).send({ error: "too_many_guests" });
      }
      const name = guestName(request.body?.name);
      const user = await store.upsertUser(`${GUEST_ID_PREFIX}${randomUUID()}`, name);
      const token = signToken(config.sessionSecret, "session", user.id, SESSION_TTL_SECONDS, { name: user.name });
      return reply.code(201).send({ token, expiresIn: SESSION_TTL_SECONDS, user: { id: user.id, name: user.name, guest: true } });
    },
  );

  // ---- lobbies
  const lobbyView = (lobby: Lobby) => ({
    id: lobby.id,
    code: lobby.code,
    instanceId: lobby.instanceId,
    hostId: lobby.hostId,
    maxPlayers: lobby.maxPlayers,
    visibility: lobby.visibility,
    players: lobby.players,
    // Seats in the order people came (they close up when someone leaves); `away` is a member whose screen has not
    // polled for a few seconds.
    members: lobby.members.map((m, i) => ({
      userId: m.userId,
      name: m.name,
      seat: i + 1,
      host: m.userId === lobby.hostId,
      away: lobbies.isQuiet(lobby, m.userId),
    })),
    state: lobby.state,
    settings: lobby.settings,
    // The map the night is on, for a screen that does not read the settings (`settings` is null for the usual rules).
    map: lobby.settings?.map ?? DEFAULT_MAP,
    round: lobby.round,
    matchId: lobby.match?.id ?? null,
  });

  // What a code says before its holder presses Join: no ids and nothing to join with, so anyone signed in may look.
  const lobbyPreview = (lobby: Lobby) => ({
    code: lobby.code,
    state: lobby.state,
    round: lobby.round,
    map: lobby.settings?.map ?? DEFAULT_MAP,
    players: lobby.players ?? lobby.members.length,
    maxPlayers: lobby.maxPlayers,
    full: lobbies.isFull(lobby),
    hostName: lobby.members.find((m) => m.userId === lobby.hostId)?.name ?? "",
    names: lobby.members.map((m) => m.name),
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
          properties: { maxPlayers: { type: "integer", minimum: 1, maximum: MAX_PLAYERS }, instanceId: { type: "string", maxLength: 128 } },
        },
      },
    },
    async (request, reply) => {
      const { maxPlayers = MAX_PLAYERS, instanceId = null } = request.body ?? {};
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

  // Looking at a night by its code, or by the Discord Activity instance it belongs to (a body, not the URL, so a code
  // stays out of the request log): is it waiting for its host, or in round N, and is there room? It joins nobody.
  app.post<{ Body: { code?: string; instanceId?: string } }>(
    "/lobbies/preview",
    {
      onRequest: requireUser,
      schema: {
        body: {
          type: "object",
          properties: { code: { type: "string", maxLength: 16 }, instanceId: { type: "string", maxLength: 128 } },
          anyOf: [{ required: ["code"] }, { required: ["instanceId"] }],
        },
      },
    },
    async (request) => {
      const { code, instanceId } = request.body;
      const found = code !== undefined ? lobbies.findByCode(code) : lobbies.findByInstance(instanceId!);
      if (!found) throw new LobbyFailure("not_found");
      return lobbyPreview(found);
    },
  );

  app.get<{ Params: { id: string } }>("/lobbies/:id", { onRequest: requireUser }, async (request) => {
    return lobbyView(lobbies.view(request.params.id, request.userId));
  });

  // Quick join: into a public night with room, or a new public one that starts at once.
  app.post("/lobbies/quick", { onRequest: requireUser }, async (request, reply) => {
    return reply.code(200).send(lobbyView(lobbies.quick(await member(request.userId))));
  });

  app.post<{ Params: { id: string } }>("/lobbies/:id/leave", { onRequest: requireUser }, async (request, reply) => {
    lobbies.leave(request.params.id, request.userId);
    return reply.code(204).send();
  });

  // The host sets the night's rules while the lobby waits; the other members read them on their next poll. The body is
  // the settings themselves: `{count_multiplier, max_alive, break_seconds}`.
  app.put<{ Params: { id: string }; Body: unknown }>(
    "/lobbies/:id/settings",
    { onRequest: requireUser },
    async (request) => lobbyView(lobbies.setSettings(request.params.id, request.userId, request.body)),
  );

  // The host may send the night's rules (`settings`, the game's `MatchSettings`: count_multiplier, max_alive,
  // break_seconds); they are checked here, kept on the lobby and signed into every ticket of the match.
  app.post<{ Params: { id: string }; Body: { settings?: unknown } | undefined }>(
    "/lobbies/:id/start",
    { onRequest: requireUser },
    async (request) => lobbyView(lobbies.start(request.params.id, request.userId, request.body?.settings)),
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
      // Every ticket of a match carries the same rules; the game server applies them when the first one opens the room.
      ...(lobby.settings ? { settings: lobby.settings } : {}),
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
  app.post<{
    Body: {
      id: string;
      url: string;
      activityPath: string;
      capacity: number;
      matchIds?: string[];
      players?: Record<string, number>;
      rounds?: Record<string, number>;
    };
  }>(
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
            // How many players each match has now (match id to count), for the lobby's room left.
            players: { type: "object", maxProperties: 1024, additionalProperties: { type: "integer", minimum: 0, maximum: 64 } },
            // The round each match is in now (match id to round number), for a late joiner's "night in progress, round N".
            rounds: { type: "object", maxProperties: 1024, additionalProperties: { type: "integer", minimum: 0, maximum: 10000 } },
          },
        },
      },
    },
    async (request, reply) => {
      registry.heartbeat({ ...request.body, matchIds: request.body.matchIds ?? [] });
      for (const [matchId, players] of Object.entries(request.body.players ?? {})) lobbies.setPlayers(matchId, players);
      for (const [matchId, round] of Object.entries(request.body.rounds ?? {})) lobbies.setRound(matchId, round);
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
