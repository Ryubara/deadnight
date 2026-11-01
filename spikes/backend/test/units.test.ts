import assert from "node:assert/strict";
import { test } from "node:test";
import { loadConfig } from "../src/config.ts";
import { LiveDiscord } from "../src/discord.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { signToken, verifyToken } from "../src/tokens.ts";

const secret = "k".repeat(32);

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

test("configuration comes from the environment and fails closed", () => {
  const base = { SESSION_SECRET: secret, TICKET_SECRET: secret, GAME_SERVER_SECRET: secret };
  assert.throws(() => loadConfig({}), /SESSION_SECRET/);
  assert.throws(() => loadConfig({ ...base, SESSION_SECRET: "short" }), /SESSION_SECRET/);
  assert.throws(() => loadConfig({ ...base, NODE_ENV: "production" }), /stub is refused/);
  assert.throws(() => loadConfig({ ...base, DISCORD_MODE: "live" }), /DISCORD_CLIENT_ID/);
  assert.equal(loadConfig({ ...base, DISCORD_MODE: "live", DISCORD_CLIENT_ID: "1", DISCORD_CLIENT_SECRET: "2" }).discordMode, "live");
});

test("the registry allocates the least loaded live server and forgets silent ones", () => {
  let now = 0;
  const registry = new GameServerRegistry(1000, () => now);
  registry.heartbeat({ id: "a", url: "ws://a", activityPath: "/a", capacity: 4, matches: 3 });
  registry.heartbeat({ id: "b", url: "ws://b", activityPath: "/b", capacity: 4, matches: 1 });
  assert.equal(registry.allocate()?.id, "b");
  now = 1500;
  registry.heartbeat({ id: "a", url: "ws://a", activityPath: "/a", capacity: 4, matches: 3 });
  assert.deepEqual(registry.alive().map((s) => s.id), ["a"]); // b went silent
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
