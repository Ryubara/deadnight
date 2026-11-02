// Discord sign-in: the Activity sends the OAuth `code` from the Embedded App SDK's authorize(); the backend swaps it
// for an access token (the client secret never leaves the server) and reads the user.

export interface DiscordUser {
  id: string;
  /** The account handle (`name_123`), not what people see. */
  username: string;
  /** The display name the player chose on Discord, if any. */
  globalName: string | null;
  /** The player's nickname in the server the Activity runs in, if they have one (needs the `guilds.members.read` scope). */
  nick: string | null;
  avatar: string | null;
}

export interface DiscordSignIn {
  accessToken: string;
  user: DiscordUser;
}

/** Discord did not answer in time, failed, or answered nonsense: the code may be fine, so this is not a 401. */
export class DiscordUnavailable extends Error {}

export interface DiscordClient {
  /** Throws when the code is not valid, and `DiscordUnavailable` when Discord could not be asked. `guildId`: the server of the Activity. */
  exchangeCode(code: string, guildId?: string): Promise<DiscordSignIn>;
}

/** Stub users live in their own `discord_id` namespace, so one can never collide with a real Discord id. */
export const STUB_ID_PREFIX = "stub:";

/**
 * Test double: the code is `stub:<id>:<username>[:<global name>[:<nick>]]`; an empty part is none. The nickname is
 * given only when the call names a server, as Discord does. Never allowed in production (see config).
 */
export class StubDiscord implements DiscordClient {
  async exchangeCode(code: string, guildId?: string): Promise<DiscordSignIn> {
    const match = /^stub:([0-9]{1,20}):([\w-]{1,32})(?::([\w -]{0,32}))?(?::([\w -]{0,32}))?$/.exec(code);
    if (!match) throw new Error("invalid stub code");
    return {
      accessToken: `stub-access-${match[1]}`,
      user: {
        id: `${STUB_ID_PREFIX}${match[1]}`,
        username: match[2]!,
        globalName: match[3] || null,
        nick: guildId ? match[4] || null : null,
        avatar: null,
      },
    };
  }
}

const API = "https://discord.com/api";
export const DISCORD_TIMEOUT_MS = 5000;

/** The OAuth `error` Discord named in a rejection (`invalid_grant`: a code used twice or expired), for the log. Never the message. */
async function errorName(response: Response): Promise<string> {
  try {
    const { error } = (await response.json()) as { error?: unknown };
    return typeof error === "string" && /^[a-z_]{1,40}$/.test(error) ? ` (${error})` : "";
  } catch {
    return "";
  }
}

export class LiveDiscord implements DiscordClient {
  private readonly clientId: string;
  private readonly clientSecret: string;
  private readonly fetchFn: typeof fetch;
  private readonly timeoutMs: number;

  constructor(clientId: string, clientSecret: string, fetchFn: typeof fetch = fetch, timeoutMs = DISCORD_TIMEOUT_MS) {
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.fetchFn = fetchFn;
    this.timeoutMs = timeoutMs;
  }

  /** One Discord call with a deadline: a stalled Discord must not hold our requests open. */
  private async call(what: string, url: string, init: RequestInit): Promise<unknown> {
    let response: Response;
    try {
      response = await this.fetchFn(url, { ...init, signal: AbortSignal.timeout(this.timeoutMs) });
    } catch (error) {
      throw new DiscordUnavailable(`discord ${what} unreachable: ${(error as Error).name}`);
    }
    // 4xx is Discord saying the code or token is bad; 429 and 5xx are Discord's trouble, not the player's.
    if (response.status === 429 || response.status >= 500) {
      throw new DiscordUnavailable(`discord ${what} failed: ${response.status}`);
    }
    if (!response.ok) throw new Error(`discord ${what} rejected: ${response.status}${await errorName(response)}`);
    try {
      return await response.json();
    } catch {
      throw new DiscordUnavailable(`discord ${what} answered with invalid JSON`);
    }
  }

  /** The player's nickname in `guildId`, or null: no nickname, the scope was not granted, or Discord did not answer (the name then falls back, the sign-in does not fail). */
  private async nickIn(guildId: string, accessToken: string): Promise<string | null> {
    try {
      const member = (await this.call("member lookup", `${API}/users/@me/guilds/${guildId}/member`, {
        headers: { Authorization: `Bearer ${accessToken}` },
      })) as { nick?: unknown };
      return typeof member.nick === "string" ? member.nick : null;
    } catch {
      return null;
    }
  }

  async exchangeCode(code: string, guildId?: string): Promise<DiscordSignIn> {
    const token = (await this.call("token exchange", `${API}/oauth2/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: this.clientId,
        client_secret: this.clientSecret,
        grant_type: "authorization_code",
        code,
      }),
    })) as { access_token?: unknown; scope?: unknown };
    if (typeof token.access_token !== "string") {
      throw new DiscordUnavailable("discord token exchange gave no access_token");
    }
    const accessToken = token.access_token;

    const user = (await this.call("user lookup", `${API}/users/@me`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    })) as Partial<DiscordUser> & { global_name?: unknown };
    if (typeof user.id !== "string" || typeof user.username !== "string") {
      throw new DiscordUnavailable("discord user lookup gave no user");
    }
    // The nickname is a server's, so it takes the member scope and the server's id; without either the name falls back.
    const scopes = typeof token.scope === "string" ? token.scope.split(" ") : [];
    const nick = guildId && scopes.includes("guilds.members.read") ? await this.nickIn(guildId, accessToken) : null;
    return {
      accessToken,
      user: {
        id: user.id,
        username: user.username,
        globalName: typeof user.global_name === "string" ? user.global_name : null,
        nick,
        avatar: user.avatar ?? null,
      },
    };
  }
}

/** Discord is not configured: every code is refused as unavailable (guests are the only way in). */
export class OffDiscord implements DiscordClient {
  async exchangeCode(): Promise<DiscordSignIn> {
    throw new DiscordUnavailable("discord sign-in is not configured on this backend");
  }
}
