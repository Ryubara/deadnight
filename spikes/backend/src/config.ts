// All configuration comes from environment variables. Nothing here has a secret default.

export type DiscordMode = "stub" | "live";

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
}

function required(env: NodeJS.ProcessEnv, name: string, minLength = 1): string {
  const value = env[name];
  if (value === undefined || value.length < minLength) {
    throw new Error(`environment variable ${name} is required (at least ${minLength} characters)`);
  }
  return value;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const production = env.NODE_ENV === "production";
  const discordMode = (env.DISCORD_MODE ?? "stub") as DiscordMode;
  if (discordMode !== "stub" && discordMode !== "live") {
    throw new Error("DISCORD_MODE must be 'stub' or 'live'");
  }
  if (production && discordMode === "stub") {
    throw new Error("DISCORD_MODE=stub is refused when NODE_ENV=production");
  }
  const live = discordMode === "live";
  return {
    host: env.HOST ?? "0.0.0.0",
    port: Number(env.PORT ?? 3000),
    logLevel: env.LOG_LEVEL ?? "info",
    sessionSecret: required(env, "SESSION_SECRET", 32),
    ticketSecret: required(env, "TICKET_SECRET", 32),
    gameServerSecret: required(env, "GAME_SERVER_SECRET", 32),
    discordMode,
    discordClientId: live ? required(env, "DISCORD_CLIENT_ID") : (env.DISCORD_CLIENT_ID ?? ""),
    discordClientSecret: live ? required(env, "DISCORD_CLIENT_SECRET") : "",
    databaseUrl: env.DATABASE_URL ?? null,
    production,
  };
}
