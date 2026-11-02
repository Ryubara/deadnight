import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { test } from "node:test";
import { buildApp, stripApiPrefix } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { LiveDiscord, StubDiscord } from "../src/discord.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore } from "../src/store.ts";
import { signToken, verifyToken } from "../src/tokens.ts";

const secret = "k".repeat(32);
const base = { SESSION_SECRET: secret, TICKET_SECRET: "t".repeat(32), GAME_SERVER_SECRET: "g".repeat(32) };
const stubEnv = { ...base, DISCORD_MODE: "stub", ALLOW_STUB_SIGN_IN: "1" };
const liveEnv = { ...base, DISCORD_MODE: "live", DISCORD_CLIENT_ID: "1", DISCORD_CLIENT_SECRET: "2" };

test("tokens verify, and expire, and cannot be forged or used as another kind", () => {
  const token = signToken(secret, "session", "u1", 60, { name: "a" }, 1000);
  assert.equal(verifyToken(secret, "session", token, 1030)?.sub, "u1");
  assert.equal(verifyToken(secret, "session", token, 1060), null); // expired
  assert.equal(verifyToken(secret, "ticket", token, 1030), null); // wrong kind
  assert.equal(verifyToken("z".repeat(32), "session", token, 1030), null); // wrong key
  const [head, , sig] = token.split(".");
  const tampered = `${head}.${Buffer.from('{"sub":"admin","kind":"session","iat":1,"exp":9999999999}').toString("base64url")}.${sig}`;
  assert.equal(verifyToken(secret, "session", tampered, 1030), null);
  assert.equal(verifyToken(secret, "session", "garbage", 1030), null);
});

/** A token with exactly these claims, correctly signed: what a bug or a compromised issuer could produce. */
function signedWith(claims: unknown, key = secret): string {
  const b64 = (value: string) => Buffer.from(value).toString("base64url");
  const input = `${b64(JSON.stringify({ alg: "HS256", typ: "JWT" }))}.${b64(JSON.stringify(claims))}`;
  return `${input}.${createHmac("sha256", key).update(input).digest("base64url")}`;
}

test("a correctly signed token still needs numeric exp and iat", () => {
  const good = { sub: "u1", kind: "ticket", iat: 1000, exp: 2000 };
  assert.equal(verifyToken(secret, "ticket", signedWith(good), 1500)?.sub, "u1"); // the helper itself is sound
  const { exp: _exp, ...noExp } = good;
  const { iat: _iat, ...noIat } = good;
  assert.equal(verifyToken(secret, "ticket", signedWith(noExp), 1500), null); // never expires
  assert.equal(verifyToken(secret, "ticket", signedWith(noIat), 1500), null);
  assert.equal(verifyToken(secret, "ticket", signedWith({ ...good, exp: "9999999999" }), 1500), null); // a string
  assert.equal(verifyToken(secret, "ticket", signedWith({ ...good, iat: null }), 1500), null);
  assert.equal(verifyToken(secret, "ticket", signedWith({ ...good, exp: 1e999 }), 1500), null); // Infinity, as JSON null
  assert.equal(verifyToken(secret, "ticket", signedWith(null), 1500), null);
  assert.equal(verifyToken(secret, "ticket", signedWith(good), 2000), null); // expired exactly now
});

test("configuration comes from the environment and fails closed", () => {
  assert.throws(() => loadConfig({ DISCORD_MODE: "stub", ALLOW_STUB_SIGN_IN: "1" }), /SESSION_SECRET/);
  assert.throws(() => loadConfig({ ...stubEnv, SESSION_SECRET: "short" }), /SESSION_SECRET/);
  assert.throws(() => loadConfig({ ...base, DISCORD_MODE: "live" }), /DISCORD_CLIENT_ID/);
  assert.equal(loadConfig(liveEnv).discordMode, "live");
  assert.equal(loadConfig(stubEnv).discordMode, "stub");
});

test("the stub sign-in is never the default: mode unset, no opt-in and production all fail", () => {
  assert.throws(() => loadConfig(base), /DISCORD_MODE is required/); // a deploy that forgot the variable
  assert.throws(() => loadConfig({ ...base, DISCORD_MODE: "Stub" }), /DISCORD_MODE is required/);
  assert.throws(() => loadConfig({ ...base, DISCORD_MODE: "stub" }), /ALLOW_STUB_SIGN_IN/);
  assert.throws(() => loadConfig({ ...base, DISCORD_MODE: "stub", ALLOW_STUB_SIGN_IN: "true" }), /ALLOW_STUB_SIGN_IN/);
  assert.throws(() => loadConfig({ ...stubEnv, NODE_ENV: "production" }), /refused when NODE_ENV=production/);
  assert.equal(loadConfig({ ...liveEnv, NODE_ENV: "production" }).production, true);
});

test("PORT must be an integer in range and the three secrets must differ", () => {
  assert.equal(loadConfig(stubEnv).port, 3000);
  assert.equal(loadConfig({ ...stubEnv, PORT: "8080" }).port, 8080);
  for (const bad of ["abc", "", "0", "65536", "-1", "80.5", "8080abc", "1e3"]) {
    assert.throws(() => loadConfig({ ...stubEnv, PORT: bad }), /PORT/, `PORT=${JSON.stringify(bad)}`);
  }
  assert.throws(() => loadConfig({ ...stubEnv, TICKET_SECRET: base.SESSION_SECRET }), /must all differ/);
  assert.throws(() => loadConfig({ ...stubEnv, GAME_SERVER_SECRET: base.SESSION_SECRET }), /must all differ/);
  assert.throws(() => loadConfig({ ...stubEnv, GAME_SERVER_SECRET: base.TICKET_SECRET }), /must all differ/);
});

test("stub users get a stub: prefix in discord_id, so they cannot collide with real ones", async () => {
  const store = new MemoryStore();
  const app = buildApp({
    config: loadConfig(stubEnv),
    store,
    discord: new StubDiscord(),
    registry: new GameServerRegistry(),
  });
  const response = await app.inject({ method: "POST", url: "/auth/discord", payload: { code: "stub:42:zed" } });
  assert.equal(response.statusCode, 200);
  const user = await store.getUser(response.json().user.id);
  assert.equal(user?.discordId, "stub:42");
  // A real Discord user whose snowflake is also 42 is a different user.
  assert.notEqual((await store.upsertUser("42", "real")).id, user?.id);
  await app.close();
});

test("the registry allocates the least loaded live server and forgets silent ones", () => {
  let now = 0;
  const registry = new GameServerRegistry(1000, () => now);
  const beat = (id: string, matchIds: string[]) =>
    registry.heartbeat({ id, url: `ws://${id}`, activityPath: `/${id}`, capacity: 4, matchIds });
  beat("a", ["m1", "m2", "m3"]);
  beat("b", ["m4"]);
  assert.equal(registry.allocate("m5")?.id, "b");
  assert.equal(registry.allocate("m6")?.id, "b"); // b now has 3, a has 3: the tie goes to the first
  now = 1500;
  beat("a", ["m1", "m2", "m3"]);
  assert.deepEqual(registry.alive().map((s) => s.id), ["a"]); // b went silent
});

test("the registry counts what it assigned, not what a server reports, and release frees the slot", () => {
  const registry = new GameServerRegistry(1000, () => 0);
  registry.heartbeat({ id: "a", url: "ws://a", activityPath: "/a", capacity: 1, matchIds: [] });
  assert.equal(registry.allocate("m1")?.id, "a");
  assert.equal(registry.allocate("m2"), null); // the only slot is taken although "a" lists nothing yet
  assert.equal(registry.release("m1"), true);
  assert.equal(registry.release("m1"), false); // already free
  assert.equal(registry.allocate("m2")?.id, "a");
});

test("the live Discord client exchanges the code and reads the user (fetch stubbed)", async () => {
  const calls: string[] = [];
  const fetchStub = (async (url: string, init?: RequestInit) => {
    calls.push(`${init?.method ?? "GET"} ${url}`);
    const body = url.endsWith("/oauth2/token") ? { access_token: "tok" } : { id: "42", username: "zed", avatar: null };
    return new Response(JSON.stringify(body));
  }) as unknown as typeof fetch;
  const result = await new LiveDiscord("cid", "csecret", fetchStub).exchangeCode("the-code");
  assert.deepEqual(result, { accessToken: "tok", user: { id: "42", username: "zed", avatar: null } });
  assert.deepEqual(calls, ["POST https://discord.com/api/oauth2/token", "GET https://discord.com/api/users/@me"]);
});

/** A fetch that never answers on its own and rejects when its signal fires, like the real one. */
const hangingFetch = ((_url: string, init?: RequestInit) =>
  new Promise((_resolve, reject) => {
    init?.signal?.addEventListener("abort", () => reject(init.signal?.reason));
  })) as unknown as typeof fetch;

async function signInVia(fetchFn: typeof fetch, timeoutMs?: number): Promise<number> {
  const app = buildApp({
    config: loadConfig(liveEnv),
    store: new MemoryStore(),
    discord: new LiveDiscord("1", "2", fetchFn, timeoutMs),
    registry: new GameServerRegistry(),
  });
  const response = await app.inject({ method: "POST", url: "/auth/discord", payload: { code: "any" } });
  await app.close();
  return response.statusCode;
}

test("a stalled Discord fails the sign-in promptly with 502 instead of holding the request open", async () => {
  const started = Date.now();
  assert.equal(await signInVia(hangingFetch, 50), 502);
  assert.ok(Date.now() - started < 2000, "the call must give up near its timeout");
});

test("Discord saying the code is bad is a 401; Discord failing is a 502", async () => {
  const answering = (status: number) => (async () => new Response("{}", { status })) as unknown as typeof fetch;
  assert.equal(await signInVia(answering(400)), 401);
  assert.equal(await signInVia(answering(500)), 502);
  assert.equal(await signInVia(answering(429)), 502);
});

test("the Discord proxy's /api prefix is dropped, whether or not the proxy strips it itself", async () => {
  assert.equal(stripApiPrefix("/auth/guest"), "/auth/guest");
  assert.equal(stripApiPrefix("/api/auth/guest"), "/auth/guest");
  assert.equal(stripApiPrefix("/api/lobbies/quick?x=1"), "/lobbies/quick?x=1");
  assert.equal(stripApiPrefix("/api"), "/");
  assert.equal(stripApiPrefix("/api?x=1"), "/?x=1");
  assert.equal(stripApiPrefix("/apiary/x"), "/apiary/x");
  const app = buildApp({
    config: loadConfig(stubEnv),
    store: new MemoryStore(),
    discord: new StubDiscord(),
    registry: new GameServerRegistry(),
  });
  const code = { code: "stub:42:zed" };
  const plain = await app.inject({ method: "POST", url: "/auth/discord", payload: code });
  const proxied = await app.inject({ method: "POST", url: "/api/auth/discord", payload: code });
  assert.equal(plain.statusCode, 200);
  assert.equal(proxied.statusCode, 200);
  assert.equal(proxied.json().user.name, plain.json().user.name);
  await app.close();
});

test("a rejected code is logged with the error name Discord gave, and never its message", async () => {
  const rejecting = (body: string) => (async () => new Response(body, { status: 400 })) as unknown as typeof fetch;
  const why = async (body: string) =>
    new LiveDiscord("1", "2", rejecting(body)).exchangeCode("c").then(
      () => "",
      (error: Error) => error.message,
    );
  assert.equal(await why('{"error":"invalid_grant","error_description":"Invalid \\"code\\""}'), "discord token exchange rejected: 400 (invalid_grant)");
  assert.equal(await why("<html>"), "discord token exchange rejected: 400");
  assert.equal(await why('{"error":"Bad Thing! secret"}'), "discord token exchange rejected: 400");
});
