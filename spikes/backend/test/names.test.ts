// The names players see: cleaning, the basic filter, and where a Discord player's name comes from.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp, guestName } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { LiveDiscord, StubDiscord } from "../src/discord.ts";
import { chooseName, isClean, MAX_NAME, tidy } from "../src/names.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore } from "../src/store.ts";

const base = { SESSION_SECRET: "s".repeat(32), TICKET_SECRET: "t".repeat(32), GAME_SERVER_SECRET: "g".repeat(32) };
const stubEnv = { ...base, DISCORD_MODE: "stub", ALLOW_STUB_SIGN_IN: "1", GUEST_SIGN_IN: "1" };

test("a name keeps letters, digits, spaces and a few marks, squeezes spaces and stops at 24 characters", () => {
  assert.equal(tidy("  Ann   Lee  "), "Ann Lee");
  assert.equal(tidy("<b>Zoë-3</b> & co"), "bZoë-3b co");
  assert.equal(tidy("x".repeat(80)).length, MAX_NAME);
  assert.equal(tidy("😀😀"), "");
  assert.equal(tidy(null), "");
  assert.equal(tidy(undefined), "");
});

test("the basic filter refuses rude words, however they are spaced or spelled, and keeps honest names", () => {
  for (const rude of ["fuck", "F u c k", "f.u.c.k", "Sh1t", "xX_fuck_Xx", "n1gg3r", "BITCH", "d i c k", "cunt", "nazi", "FÜCK"]) {
    assert.equal(isClean(rude), false, rude);
  }
  for (const fine of ["Ann", "Dickinson", "Cockburn", "Scunthorpe", "Sasha", "Peacock", "Classic", "Hancock", "Zoë", "名前", "Assistant", "Cumberland"]) {
    assert.equal(isClean(fine), true, fine);
  }
});

test("a name that is empty or not clean becomes Guest NNNN, and a clean one stays", () => {
  assert.match(guestName(""), /^Guest [0-9]{4}$/);
  assert.match(guestName(undefined), /^Guest [0-9]{4}$/);
  assert.match(guestName("😀"), /^Guest [0-9]{4}$/);
  assert.match(guestName("f u c k"), /^Guest [0-9]{4}$/);
  assert.equal(guestName("Ann"), "Ann");
});

test("the first candidate that is left and clean wins: nickname, then display name, then username", () => {
  assert.equal(chooseName(["Nick", "Global", "user_1"], "Player"), "Nick");
  assert.equal(chooseName([null, "Global", "user_1"], "Player"), "Global");
  assert.equal(chooseName(["", "  ", "user_1"], "Player"), "user_1");
  // A rude nickname does not hide the display name behind it, and a rude everything is Player NNNN.
  assert.equal(chooseName(["fuck", "Global", "user_1"], "Player"), "Global");
  assert.match(chooseName(["fuck", null, "shit"], "Player"), /^Player [0-9]{4}$/);
});

/** A Discord that answers like the real one: the token (with the granted scope), the user, and the member in a server. */
function discordWith(options: { scope?: string; member?: unknown; memberStatus?: number }) {
  const calls: string[] = [];
  const fetchFn = (async (url: string, init?: RequestInit) => {
    calls.push(`${init?.method ?? "GET"} ${url.replace("https://discord.com/api", "")}`);
    if (url.endsWith("/oauth2/token")) return new Response(JSON.stringify({ access_token: "tok", scope: options.scope ?? "identify" }));
    if (url.endsWith("/users/@me")) return new Response(JSON.stringify({ id: "42", username: "name_123", global_name: "Zed", avatar: null }));
    return new Response(JSON.stringify(options.member ?? {}), { status: options.memberStatus ?? 200 });
  }) as unknown as typeof fetch;
  return { discord: new LiveDiscord("cid", "csecret", fetchFn), calls };
}

test("Discord: the server nickname is asked for only with the scope and a server, and wins over the display name", async () => {
  const granted = discordWith({ scope: "identify guilds.members.read", member: { nick: "Captain Zed" } });
  const withNick = await granted.discord.exchangeCode("c", "777");
  assert.equal(withNick.user.nick, "Captain Zed");
  assert.equal(withNick.user.globalName, "Zed");
  assert.equal(withNick.user.username, "name_123");
  assert.deepEqual(granted.calls, ["POST /oauth2/token", "GET /users/@me", "GET /users/@me/guilds/777/member"]);

  // No server (a call from a DM or the web), or no scope granted: no member call, the display name is next.
  const noGuild = discordWith({ scope: "identify guilds.members.read", member: { nick: "x" } });
  assert.equal((await noGuild.discord.exchangeCode("c")).user.nick, null);
  assert.equal(noGuild.calls.length, 2);
  const noScope = discordWith({ member: { nick: "x" } });
  assert.equal((await noScope.discord.exchangeCode("c", "777")).user.nick, null);
  assert.equal(noScope.calls.length, 2);
});

test("Discord: a member lookup that fails or has no nickname never fails the sign-in", async () => {
  for (const options of [
    { scope: "identify guilds.members.read", member: { nick: null } },
    { scope: "identify guilds.members.read", member: {}, memberStatus: 403 },
    { scope: "identify guilds.members.read", member: {}, memberStatus: 500 },
    { scope: "identify guilds.members.read", member: { nick: 5 } },
  ]) {
    const { discord } = discordWith(options);
    const result = await discord.exchangeCode("c", "777");
    assert.equal(result.user.nick, null);
    assert.equal(result.user.globalName, "Zed");
  }
});

async function signInWith(code: string, guildId?: string) {
  const app = buildApp({ config: loadConfig(stubEnv), store: new MemoryStore(), discord: new StubDiscord(), registry: new GameServerRegistry() });
  const response = await app.inject({ method: "POST", url: "/auth/discord", payload: guildId ? { code, guildId } : { code } });
  await app.close();
  return response;
}

test("a Discord player is named by nickname, display name or username, in that order, and a rude name is skipped", async () => {
  assert.equal((await signInWith("stub:1:name_123:Zed:Captain Zed", "777")).json().user.name, "Captain Zed");
  assert.equal((await signInWith("stub:2:name_123:Zed:Captain Zed")).json().user.name, "Zed"); // no server: no nickname
  assert.equal((await signInWith("stub:3:name_123:Zed")).json().user.name, "Zed");
  assert.equal((await signInWith("stub:4:name_123")).json().user.name, "name_123");
  assert.equal((await signInWith("stub:5:name_123:Zed:fuck", "777")).json().user.name, "Zed");
  assert.equal((await signInWith("stub:6:name_123", "not-a-number")).statusCode, 400);
});

test("a guest's chosen name is cleaned by the backend and shown back, and no name is Guest NNNN", async () => {
  const app = buildApp({ config: loadConfig(stubEnv), store: new MemoryStore(), discord: new StubDiscord(), registry: new GameServerRegistry() });
  const named = async (name?: string) =>
    (await app.inject({ method: "POST", url: "/auth/guest", payload: name === undefined ? {} : { name }, remoteAddress: `10.0.0.${Math.floor(Math.random() * 200)}` })).json().user.name;
  assert.equal(await named("  Ann  Lee "), "Ann Lee");
  assert.match(await named(), /^Guest [0-9]{4}$/);
  assert.match(await named("sh1t"), /^Guest [0-9]{4}$/);
  assert.equal((await named("y".repeat(60))).length, MAX_NAME);
  await app.close();
});
