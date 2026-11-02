// All configuration comes from environment variables. Nothing here has a secret default.

export type DiscordMode = "stub" | "live" | "off";

export interface Config {
  host: string;
  port: number;
  logLevel: string;
  sessionSecret: string;
  ticketSecret: string;
  gameServerSecret: string;
  discordMode: DiscordMode;
  discordClientId: string;
  discordClientSecret: string;
  databaseUrl: string | null;
  production: boolean;
  /** `POST /auth/guest` signs in a visitor who has no Discord (the web build). */
  guestSignIn: boolean;
}

function required(env: NodeJS.ProcessEnv, name: string, minLength = 1): string {
  const value = env[name];
  if (value === undefined || value.length < minLength) {
    throw new Error(`environment variable ${name} is required (at least ${minLength} characters)`);
  }
  return value;
}

function parsePort(value: string | undefined): number {
  if (value === undefined) return 3000;
  const port = /^[0-9]{1,5}$/.test(value) ? Number(value) : NaN;
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`environment variable PORT must be an integer from 1 to 65535 (got '${value}')`);
  }
  return port;
}

/**
 * Fails closed: nothing here guesses. `DISCORD_MODE` has no default, and the stub sign-in (which signs anyone in as
 * any user id) needs an explicit opt-in and is refused in production, so a deploy that forgets a variable refuses
 * to start instead of accepting forged identities.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const production = env.NODE_ENV === "production";
  const mode = env.DISCORD_MODE;
  if (mode !== "stub" && mode !== "live" && mode !== "off") {
    throw new Error("DISCORD_MODE is required and must be 'live', 'stub' or 'off'");
  }
  const discordMode: DiscordMode = mode;
  if (discordMode === "stub") {
    if (production) throw new Error("DISCORD_MODE=stub is refused when NODE_ENV=production");
    if (env.ALLOW_STUB_SIGN_IN !== "1") {
      throw new Error("DISCORD_MODE=stub needs ALLOW_STUB_SIGN_IN=1 (it signs anyone in as any user)");
    }
  }
  const live = discordMode === "live";
  const guestSignIn = env.GUEST_SIGN_IN === "1";
  // `off` is a backend with no Discord yet: only guests can sign in, so it needs them on.
  if (discordMode === "off" && !guestSignIn) throw new Error("DISCORD_MODE=off needs GUEST_SIGN_IN=1 (nobody could sign in)");
  const sessionSecret = required(env, "SESSION_SECRET", 32);
  const ticketSecret = required(env, "TICKET_SECRET", 32);
  const gameServerSecret = required(env, "GAME_SERVER_SECRET", 32);
  // One leaked secret must not unlock the others (a leaked ticket secret would otherwise sign sessions).
  if (new Set([sessionSecret, ticketSecret, gameServerSecret]).size !== 3) {
    throw new Error("SESSION_SECRET, TICKET_SECRET and GAME_SERVER_SECRET must all differ");
  }
  return {
    host: env.HOST ?? "0.0.0.0",
    port: parsePort(env.PORT),
    logLevel: env.LOG_LEVEL ?? "info",
    sessionSecret,
    ticketSecret,
    gameServerSecret,
    discordMode,
    discordClientId: live ? required(env, "DISCORD_CLIENT_ID") : (env.DISCORD_CLIENT_ID ?? ""),
    discordClientSecret: live ? required(env, "DISCORD_CLIENT_SECRET") : "",
    databaseUrl: env.DATABASE_URL ?? null,
    production,
    guestSignIn,
  };
}
