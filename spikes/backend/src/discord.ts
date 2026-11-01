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

export interface DiscordClient {
  /** Throws when the code is not valid. */
  exchangeCode(code: string): Promise<DiscordSignIn>;
}

/** Test double: the code is `stub:<id>:<name>`. Never allowed in production (see config). */
export class StubDiscord implements DiscordClient {
  async exchangeCode(code: string): Promise<DiscordSignIn> {
    const match = /^stub:([0-9]{1,20}):([\w-]{1,32})$/.exec(code);
    if (!match) throw new Error("invalid stub code");
    return { accessToken: `stub-access-${match[1]}`, user: { id: match[1]!, username: match[2]!, avatar: null } };
  }
}

const API = "https://discord.com/api";

export class LiveDiscord implements DiscordClient {
  private readonly clientId: string;
  private readonly clientSecret: string;
  private readonly fetchFn: typeof fetch;

  constructor(clientId: string, clientSecret: string, fetchFn: typeof fetch = fetch) {
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.fetchFn = fetchFn;
  }

  async exchangeCode(code: string): Promise<DiscordSignIn> {
    const tokenResponse = await this.fetchFn(`${API}/oauth2/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: this.clientId,
        client_secret: this.clientSecret,
        grant_type: "authorization_code",
        code,
      }),
    });
    if (!tokenResponse.ok) throw new Error(`discord token exchange failed: ${tokenResponse.status}`);
    const { access_token: accessToken } = (await tokenResponse.json()) as { access_token: string };

    const userResponse = await this.fetchFn(`${API}/users/@me`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!userResponse.ok) throw new Error(`discord user lookup failed: ${userResponse.status}`);
    const user = (await userResponse.json()) as DiscordUser;
    return { accessToken, user: { id: user.id, username: user.username, avatar: user.avatar ?? null } };
  }
}
