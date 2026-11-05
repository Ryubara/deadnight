// The HTTP API. Everything is wired through `Deps`, so tests build the same app with stubs and in-memory parts.
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest, LogController } from "fastify";
import { randomUUID, timingSafeEqual } from "node:crypto";
import type { Config } from "./config.ts";
import { type DiscordClient, DiscordUnavailable } from "./discord.ts";
import { RateLimit } from "./limits.ts";
import { type Lobby, LobbyFailure, type LobbyLimits, LobbyService, MAX_PLAYERS } from "./lobbies.ts";
import { LIST_PER_WINDOW, LIST_WINDOW_MS, listNights } from "./lobby_list.ts";
import { chooseName, firstUsable } from "./names.ts";
import { DEFAULT_MAP, SETTINGS_KEYS } from "./settings.ts";
import { GameServerRegistry } from "./servers.ts";
import { checkSave, MAX_SAVE_BYTES, SaveRejected } from "./saves.ts";
import { RevisionConflict, type Store, type User } from "./store.ts";
import { signToken, verifyToken } from "./tokens.ts";
import { NIGHT_CAP, PROFILE_SLOT, ProgressService } from "./progression.ts";

/** What a game server's report may weigh: a seat may carry its board (held to `MAX_SAVE_BYTES` each), so more than a save. */
export const REPORT_BODY_LIMIT = 1024 * 1024;

export const SESSION_TTL_SECONDS = 60 * 60;
export const TICKET_TTL_SECONDS = 60;
/** Guest sign-ins one address may make in an hour, and all addresses together. */
export const GUESTS_PER_ADDRESS_PER_HOUR = 30;
export const GUESTS_IN_ALL_PER_HOUR = 2000;
/**
 * How long a Guest account lasts without a sign-in: the guest credential is good for this long, and an account not signed
 * in to for this long is deleted with its saves. Every sign-in restarts it. A Discord account never expires.
 */
export const GUEST_TTL_SECONDS = 7 * 24 * 60 * 60;
/** How often idle Guest accounts are deleted (a returning guest past the 7 days is deleted at its sign-in anyway). */
export const GUEST_SWEEP_MS = 60 * 60_000;
/** A guest's `discord_id` column: its own namespace, never a number like a Discord snowflake. */
export const GUEST_ID_PREFIX = "guest:";

/** The name a guest chose, cleaned (letters, digits, spaces, a few marks, no rude words), or `Guest 1234` when there is none. */
export function guestName(given: string | undefined): string {
  return chooseName([given]);
}

/** Deletes the Guest accounts last signed in to 7 days ago or more, with their saves; how many. Discord accounts stay. */
export function sweepIdleGuests(store: Store, nowMs: number): Promise<number> {
  return store.deleteIdleUsers(GUEST_ID_PREFIX, nowMs - GUEST_TTL_SECONDS * 1000);
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
    /** When the session was issued (seconds since the epoch): where the XP clamp counts from for a first write. */
    sessionIat: number;
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
  bad_settings: 400,
  bad_visibility: 400,
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
  const progress = new ProgressService(store, deps.now);
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
  const now = deps.now ?? Date.now;
  const guestSweeper = setInterval(() => {
    sweepIdleGuests(store, now()).then(
      (count) => count > 0 && app.log.info({ count }, "deleted idle guest accounts"),
      (error: unknown) => app.log.error({ err: error }, "guest sweep failed"),
    );
  }, GUEST_SWEEP_MS);
  guestSweeper.unref();
  app.addHook("onClose", async () => clearInterval(guestSweeper));

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
    request.sessionIat = claims.iat;
  };

  const requireGameServer = async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
    const token = bearer(request);
    if (!token || !sameSecret(token, config.gameServerSecret)) return reply.code(401).send({ error: "unauthorized" });
  };

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof LobbyFailure) {
      // A refusal that names the setting is logged too, so a host whose choice is refused is found in the log.
      if (error.detail !== undefined) request.log.warn({ reason: error.reason, detail: error.detail }, "lobby request refused");
      return reply
        .code(LOBBY_STATUS[error.reason] ?? 400)
        .send(error.detail === undefined ? { error: error.reason } : { error: error.reason, detail: error.detail });
    }
    if (error instanceof SaveRejected) return reply.code(422).send({ error: error.reason, ...error.detail });
    if (error instanceof RevisionConflict) return reply.code(409).send({ error: "revision_conflict", revision: error.currentRevision });
    const status = (error as { statusCode?: number }).statusCode ?? 500;
    if (status >= 500) app.log.error({ err: error }, "unhandled error");
    return reply.code(status).send({ error: status >= 500 ? "internal" : "bad_request" });
  });

  // ---- operations
  // `settingsKeys` are the match settings this build takes: the deploy checks them against the game's, so a backend
  // that is behind the client is found before a host's choices are lost to it (Deadnight #944).
  app.get("/health", async () => ({ status: "ok", settingsKeys: SETTINGS_KEYS }));
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

  // Guests: a visitor with no Discord (the web build and the desktop) gets a user of their own. The id is random and
  // lives in its own `guest:` namespace, so a guest can never be, or be mistaken for, a Discord user.
  //
  // The account lasts: the answer carries `guestToken`, a signed credential good for 7 days that the client keeps in its
  // own storage and sends back, and a sign-in with it is the same account, with its saves. A credential that is forged,
  // expired, of an account already deleted or not a guest's is no credential: the visitor gets a new guest, never
  // somebody else's. Each sign-in restarts the 7 days (a new credential, a new `lastSeen`); an account not signed in to
  // for 7 days is deleted with its saves (the hourly sweep, or its own sign-in, whichever comes first).
  //
  // Anyone can call this, so it is limited per address (every call) and in all (every new account).
  const guestsPerAddress = new RateLimit(GUESTS_PER_ADDRESS_PER_HOUR, 60 * 60_000, deps.now);
  const guestsInAll = new RateLimit(GUESTS_IN_ALL_PER_HOUR, 60 * 60_000, deps.now);

  /**
   * The guest this credential names, if it is one of ours, in date, and its account is still there and in date. Its
   * expiry is read here and not by `verifyToken` so that a good signature on a credential that ran out still deletes
   * its account when that is 7 days idle: the account is gone the moment anyone looks, not when the sweep comes.
   */
  const guestOf = async (credential: string | undefined, nowMs: number): Promise<User | null> => {
    if (!credential) return null;
    const claims = verifyToken(config.sessionSecret, "guest", credential, 0);
    if (!claims) return null;
    const user = await store.getUser(claims.sub);
    if (!user || !user.discordId.startsWith(GUEST_ID_PREFIX)) return null;
    if (nowMs - user.lastSeen >= GUEST_TTL_SECONDS * 1000) {
      await store.deleteUser(user.id);
      return null;
    }
    return claims.exp > Math.floor(nowMs / 1000) ? user : null;
  };

  app.post<{ Body: { name?: string; guestToken?: string } }>(
    "/auth/guest",
    {
      schema: {
        body: { type: "object", properties: { name: { type: "string", maxLength: 64 }, guestToken: { type: "string", maxLength: 1024 } } },
      },
    },
    async (request, reply) => {
      if (!config.guestSignIn) return reply.code(404).send({ error: "not_found" });
      if (!guestsPerAddress.allow(request.ip)) return reply.code(429).send({ error: "too_many_guests" });
      const nowMs = now();
      const returning = await guestOf(request.body?.guestToken, nowMs);
      if (!returning && !guestsInAll.allow("all")) return reply.code(429).send({ error: "too_many_guests" });
      // The chosen name updates on every sign-in; a returning guest who gave none keeps the one it has.
      const chosen = firstUsable([request.body?.name]);
      const user = returning
        ? await store.upsertUser(returning.discordId, chosen ?? returning.name, nowMs)
        : await store.upsertUser(`${GUEST_ID_PREFIX}${randomUUID()}`, chosen ?? guestName(undefined), nowMs);
      const token = signToken(config.sessionSecret, "session", user.id, SESSION_TTL_SECONDS, { name: user.name });
      const guestToken = signToken(config.sessionSecret, "guest", user.id, GUEST_TTL_SECONDS, {}, Math.floor(nowMs / 1000));
      return reply.code(returning ? 200 : 201).send({
        token,
        expiresIn: SESSION_TTL_SECONDS,
        guestToken,
        guestExpiresIn: GUEST_TTL_SECONDS,
        returning: returning !== null,
        user: { id: user.id, name: user.name, guest: true },
      });
    },
  );

  // ---- lobbies
  const lobbyView = (lobby: Lobby) => ({
    id: lobby.id,
    code: lobby.code,
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
      // The level and icon beside the name in the lobby list (the same the ticket will carry); absent until the backend has read the profile.
      ...(progress.knownLevel(m.userId) ?? {}),
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
    await progress.claimsFor(user.id); // reads the profile once, so the member list can show the level
    return { userId: user.id, name: user.name };
  };

  // A new night is public (listed in the Server Browser) unless its host says `visibility: "private"` here or later
  // (`PUT /lobbies/:id/visibility`). `maxPlayers` counts people: bots hold no seat.
  app.post<{ Body: { maxPlayers?: number; visibility?: "public" | "private" } }>(
    "/lobbies",
    {
      onRequest: requireUser,
      schema: {
        body: {
          type: "object",
          properties: {
            maxPlayers: { type: "integer", minimum: 1, maximum: MAX_PLAYERS },
            visibility: { type: "string", enum: ["public", "private"] },
          },
        },
      },
    },
    async (request, reply) => {
      // Always a new lobby, on the website and in a Discord Activity alike: players reach each other by code, link or
      // the Server Browser, never by the Activity instance they share (#1178).
      const { maxPlayers = MAX_PLAYERS, visibility = "public" } = request.body ?? {};
      return reply.code(201).send(lobbyView(lobbies.create(await member(request.userId), maxPlayers, visibility)));
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

  // Looking at a night by its code (a body, not the URL, so a code stays out of the request log): is it waiting for its
  // host, or in round N, and is there room? It joins nobody.
  app.post<{ Body: { code: string } }>(
    "/lobbies/preview",
    {
      onRequest: requireUser,
      schema: {
        body: {
          type: "object",
          required: ["code"],
          properties: { code: { type: "string", maxLength: 16 } },
        },
      },
    },
    async (request) => {
      const found = lobbies.findByCode(request.body.code);
      if (!found) throw new LobbyFailure("not_found");
      return lobbyPreview(found);
    },
  );

  // The Server Browser: the public nights to join, waiting or in progress, with their people (bots not counted) out of the
  // cap. Anyone signed in may look; it joins nobody (join by the row's `code`). Polled, so it is limited per account.
  const listLimit = new RateLimit(LIST_PER_WINDOW, LIST_WINDOW_MS, deps.now);
  app.get("/lobbies", { onRequest: requireUser }, async (request, reply) => {
    if (!listLimit.allow(request.userId)) return reply.code(429).header("Retry-After", String(LIST_WINDOW_MS / 1000)).send({ error: "too_many_requests" });
    return { maxPlayers: MAX_PLAYERS, ...listNights(lobbies) };
  });

  app.get<{ Params: { id: string } }>("/lobbies/:id", { onRequest: requireUser }, async (request) => {
    return lobbyView(lobbies.view(request.params.id, request.userId));
  });

  app.post<{ Params: { id: string } }>("/lobbies/:id/leave", { onRequest: requireUser }, async (request, reply) => {
    lobbies.leave(request.params.id, request.userId);
    return reply.code(204).send();
  });

  // The host makes the night private (not listed, not handed to a stranger; its code still joins) or public again.
  app.put<{ Params: { id: string }; Body: { visibility?: unknown } | undefined }>(
    "/lobbies/:id/visibility",
    { onRequest: requireUser },
    async (request) => lobbyView(lobbies.setVisibility(request.params.id, request.userId, request.body?.visibility)),
  );

  // The host sets the night's rules while the lobby waits; the other members read them on their next poll. The body is
  // the settings themselves: `{count_multiplier, max_alive, break_seconds}`.
  app.put<{ Params: { id: string }; Body: unknown }>(
    "/lobbies/:id/settings",
    { onRequest: requireUser },
    async (request) => lobbyView(lobbies.setSettings(request.params.id, request.userId, await progress.levelFor(request.userId), request.body)),
  );

  // The host may send the night's rules (`settings`, the game's `MatchSettings`: count_multiplier, max_alive,
  // break_seconds); they are checked here, kept on the lobby and signed into every ticket of the match.
  app.post<{ Params: { id: string }; Body: { settings?: unknown } | undefined }>(
    "/lobbies/:id/start",
    { onRequest: requireUser },
    async (request) => lobbyView(lobbies.start(request.params.id, request.userId, await progress.levelFor(request.userId), request.body?.settings)),
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
      // What the seat's level is seen by in the night: from the stored profile, never the client's word.
      ...(await progress.claimsFor(seat.userId)),
      // Every ticket of a match carries the same host level, the lobby host's when the match started (a guest's ticket
      // too: the host's level decides the map, not the holder's), and the same rules; the game server applies them when the first one opens the room.
      hostLevel: lobby.match.hostLevel,
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
      // The profile is the one slot the backend reads: it must read, take nothing away and not rise faster than a
      // person can play (docs/research/platform-backend.md#progression).
      if (request.params.slot === PROFILE_SLOT) return progress.soloWrite(request.userId, request.body, request.sessionIat);
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
            // How many PEOPLE each match has now (match id to count, bots not counted: they hold no seat), for the
            // lobby's room left and the Server Browser's row.
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

  // A seat's challenge board, read by the game server when the seat sits down (its tracker follows it from there). Only
  // this one slot: the profile's XP already rides the ticket, and a game server has no business with the rest.
  app.get<{ Params: { userId: string } }>(
    "/internal/users/:userId/saves/challenges",
    {
      onRequest: requireGameServer,
      schema: { params: { type: "object", properties: { userId: { type: "string", minLength: 1, maxLength: 64 } } } },
    },
    async (request, reply) => {
      const board = await progress.boardOf(request.params.userId);
      return board ?? reply.code(404).send({ error: "not_found" });
    },
  );

  // A game server's report of one round (or of the night's end): each seat's XP, which the backend adds to the seat's
  // profile once. The key is (match, kind, round, user), so a retry pays nothing; the answer says per seat what was
  // paid, so a server that lost the answer can post the same report again. Never called per kill.
  app.post<{
    Params: { matchId: string };
    Body: {
      kind: "round" | "night";
      round: number;
      seats: {
        userId: string;
        xp: number;
        openingNight?: boolean;
        bonusDay?: number;
        done?: string[];
        board?: { schemaVersion: number; data: Record<string, unknown> };
        lines?: Record<string, number>;
      }[];
    };
  }>(
    "/internal/matches/:matchId/report",
    {
      onRequest: requireGameServer,
      bodyLimit: REPORT_BODY_LIMIT,
      schema: {
        params: { type: "object", properties: { matchId: { type: "string", minLength: 1, maxLength: 64 } } },
        body: {
          type: "object",
          required: ["kind", "round", "seats"],
          properties: {
            kind: { type: "string", enum: ["round", "night"] },
            round: { type: "integer", minimum: 0, maximum: 10000 },
            seats: {
              type: "array",
              maxItems: 64,
              items: {
                type: "object",
                required: ["userId", "xp"],
                properties: {
                  userId: { type: "string", minLength: 1, maxLength: 64 },
                  xp: { type: "integer", minimum: 0, maximum: NIGHT_CAP },
                  openingNight: { type: "boolean" },
                  bonusDay: { type: "integer", minimum: 0, maximum: 1_000_000 },
                  done: { type: "array", maxItems: 100, items: { type: "string", minLength: 1, maxLength: 64 } },
                  board: {
                    type: "object",
                    required: ["schemaVersion", "data"],
                    properties: { schemaVersion: { type: "integer", minimum: 1 }, data: { type: "object" } },
                  },
                  lines: {
                    type: "object",
                    maxProperties: 32,
                    propertyNames: { pattern: "^[a-z0-9_:-]{1,32}$" },
                    additionalProperties: { type: "integer", minimum: 0, maximum: 1_000_000_000 },
                  },
                },
              },
            },
          },
        },
      },
    },
    async (request) => {
      const { kind, round, seats } = request.body;
      const results = await progress.applyReport(request.params.matchId, kind, round, seats);
      request.log.info(
        { matchId: request.params.matchId, kind, round, paid: results.filter((r) => r.status === "paid").length, seats: seats.length },
        "round report",
      );
      return { matchId: request.params.matchId, kind, round, seats: results };
    },
  );

  // The game server says a person's seat in a match is empty (Leave, a closed tab, a dropped connection not taken back):
  // they are out of its lobby at once, so nothing of the night holds them, and a night with nobody left is over.
  app.post<{ Params: { matchId: string }; Body: { userId: string } }>(
    "/internal/matches/:matchId/left",
    {
      onRequest: requireGameServer,
      schema: {
        params: { type: "object", properties: { matchId: { type: "string", minLength: 1, maxLength: 64 } } },
        body: { type: "object", required: ["userId"], properties: { userId: { type: "string", minLength: 1, maxLength: 64 } } },
      },
    },
    async (request, reply) => {
      lobbies.memberLeft(request.params.matchId, request.body.userId);
      return reply.code(204).send();
    },
  );

  // The game server says a match is over: its slot is free and its lobby goes. A night that ran its end-of-night
  // intermission out says `finished` with the users still there, and its lobby opens again for them. Idempotent.
  app.post<{ Params: { matchId: string }; Body: { finished?: boolean; present?: string[] } | null }>(
    "/internal/matches/:matchId/end",
    {
      onRequest: requireGameServer,
      schema: {
        params: { type: "object", properties: { matchId: { type: "string", minLength: 1, maxLength: 64 } } },
        body: {
          type: ["object", "null"],
          properties: {
            finished: { type: "boolean" },
            present: { type: "array", maxItems: 64, items: { type: "string", minLength: 1, maxLength: 64 } },
          },
        },
      },
    },
    async (request, reply) => {
      const body = request.body;
      lobbies.matchEnded(request.params.matchId, body?.finished ? { present: body.present ?? [] } : undefined);
      return reply.code(204).send();
    },
  );

  return app;
}
