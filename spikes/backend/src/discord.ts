// Discord sign-in: the Activity sends the OAuth `code` from the Embedded App SDK's authorize(); the backend swaps it
// for an access token (the client secret never leaves the server) and reads the user.

export interface DiscordUser {
  id: string;
  username: string;
  avatar: string | null;
}

export interface DiscordSignIn {
  accessToken: string;
  user: DiscordUser;
}

/** Discord did not answer in time, failed, or answered nonsense: the code may be fine, so this is not a 401. */
export class DiscordUnavailable extends Error {}

export interface DiscordClient {
  /** Throws when the code is not valid, and `DiscordUnavailable` when Discord could not be asked. */
  exchangeCode(code: string): Promise<DiscordSignIn>;
}

/** Stub users live in their own `discord_id` namespace, so one can never collide with a real Discord id. */
export const STUB_ID_PREFIX = "stub:";

/** Test double: the code is `stub:<id>:<name>`. Never allowed in production (see config). */
export class StubDiscord implements DiscordClient {
  async exchangeCode(code: string): Promise<DiscordSignIn> {
    const match = /^stub:([0-9]{1,20}):([\w-]{1,32})$/.exec(code);
    if (!match) throw new Error("invalid stub code");
    return {
      accessToken: `stub-access-${match[1]}`,
      user: { id: `${STUB_ID_PREFIX}${match[1]}`, username: match[2]!, avatar: null },
    };
  }
}

const API = "https://discord.com/api";
export const DISCORD_TIMEOUT_MS = 5000;

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
    if (!response.ok) throw new Error(`discord ${what} rejected: ${response.status}`);
    try {
      return await response.json();
    } catch {
      throw new DiscordUnavailable(`discord ${what} answered with invalid JSON`);
    }
  }

  async exchangeCode(code: string): Promise<DiscordSignIn> {
    const token = (await this.call("token exchange", `${API}/oauth2/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: this.clientId,
        client_secret: this.clientSecret,
        grant_type: "authorization_code",
        code,
      }),
    })) as { access_token?: unknown };
    if (typeof token.access_token !== "string") {
      throw new DiscordUnavailable("discord token exchange gave no access_token");
    }
    const accessToken = token.access_token;

    const user = (await this.call("user lookup", `${API}/users/@me`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    })) as Partial<DiscordUser>;
    if (typeof user.id !== "string" || typeof user.username !== "string") {
      throw new DiscordUnavailable("discord user lookup gave no user");
    }
    return { accessToken, user: { id: user.id, username: user.username, avatar: user.avatar ?? null } };
  }
}
