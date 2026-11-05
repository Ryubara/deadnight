// A waiting lobby whose only player closed the tab (Deadnight #1188). Two parts, each a test over the real app:
// the list does not show a lobby nobody has been heard from in (hidden, not ended: a host pasting the invite in another
// tab keeps it), and the page's own word on `pagehide` (`POST /lobbies/:id/page-closed`, a beacon with the token in its
// body) ends it at once.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { OffDiscord } from "../src/discord.ts";
import { DEFAULT_LOBBY_LIMITS } from "../src/lobbies.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore } from "../src/store.ts";

const env = {
  SESSION_SECRET: "s".repeat(32),
  TICKET_SECRET: "t".repeat(32),
  GAME_SERVER_SECRET: "g".repeat(32),
  DISCORD_MODE: "off",
  GUEST_SIGN_IN: "1",
  NODE_ENV: "production",
  CORS_ORIGINS: "https://web.example",
};

type Who = { token: string; headers: { authorization: string }; user: { id: string; name: string } };
const SECOND = 1000;

async function platform() {
  const clock = { now: 5_000_000 };
  const registry = new GameServerRegistry(60 * 60_000, () => clock.now);
  const config = loadConfig(env);
  const app = buildApp({ config, store: new MemoryStore(), discord: new OffDiscord(), registry, now: () => clock.now });
  await app.inject({
    method: "POST",
    url: "/internal/servers/heartbeat",
    headers: { authorization: `Bearer ${config.gameServerSecret}` },
    payload: { id: "gs", url: "wss://gs.example", activityPath: "/gs", capacity: 40, matchIds: [] },
  });
  let guests = 0;
  const guest = async (name: string): Promise<Who> => {
    const n = ++guests;
    const response = await app.inject({ method: "POST", url: "/auth/guest", payload: { name }, remoteAddress: `10.${n >> 8}.0.${n & 255}` });
    const token = response.json().token as string;
    return { token, headers: { authorization: `Bearer ${token}` }, user: response.json().user };
  };
  const call = (method: "GET" | "POST" | "PUT", url: string, who: { headers: object }, payload?: object) =>
    app.inject({ method, url, headers: who.headers, payload });
  const codes = async (who: Who) => ((await call("GET", "/lobbies", who)).json().nights as { code: string }[]).map((n) => n.code);
  /** What a browser's `sendBeacon` sends on `pagehide`: no Authorization header, a `text/plain` body with the token in it. */
  const beacon = (id: string, who: Who) =>
    app.inject({ method: "POST", url: `/lobbies/${id}/page-closed`, headers: { "content-type": "text/plain;charset=UTF-8", origin: "https://web.example" }, payload: JSON.stringify({ token: who.token }) });
  return { app, clock, guest, call, codes, beacon };
}

test("a lobby nobody has been heard from in is left out of the list within seconds, and comes back with the next poll", async () => {
  const { app, clock, guest, call, codes } = await platform();
  const [ann, looker] = [await guest("Ann"), await guest("Looker")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  assert.deepEqual(await codes(looker), [made.code]);

  // Ann's tab goes quiet (closed, or in the background): still listed while a poll could be on its way, gone from the
  // list once the member shows as away.
  clock.now += DEFAULT_LOBBY_LIMITS.memberQuietMs - SECOND;
  assert.deepEqual(await codes(looker), [made.code]);
  clock.now += 2 * SECOND;
  assert.deepEqual(await codes(looker), []);

  // Hidden, not ended: the lobby is still hers and polling it again lists it again.
  const back = await call("GET", `/lobbies/${made.id}`, ann);
  assert.equal(back.statusCode, 200);
  assert.deepEqual(await codes(looker), [made.code]);
  await app.close();
});

test("a host who pastes the invite in another tab keeps the lobby: the code still joins it, and the lobby is listed again", async () => {
  const { app, clock, guest, call, codes } = await platform();
  const [ann, bo, looker] = [await guest("Ann"), await guest("Bo"), await guest("Looker")];
  const made = (await call("POST", "/lobbies", ann, {})).json();

  // Five minutes alone in a chat: well past the list's quiet time, well inside the lobby's own idle time.
  clock.now += 5 * 60_000;
  assert.deepEqual(await codes(looker), []);
  assert.equal((await call("GET", `/lobbies/${made.id}`, ann)).statusCode, 200, "her lobby is still hers");
  assert.deepEqual(await codes(looker), [made.code], "and listed again");

  // Another trip, shorter than the minute after which a quiet member is dropped when someone else is there: the friend
  // comes in by the code while the lobby is hidden, and the host finds both of them when she is back.
  clock.now += 40 * SECOND;
  assert.deepEqual(await codes(looker), []);
  const joined = await call("POST", "/lobbies/join-by-code", bo, { code: made.code });
  assert.equal(joined.statusCode, 200, "the code works while the lobby is hidden");
  assert.deepEqual(await codes(looker), [made.code], "the friend's arrival is a voice: it is listed again");
  const seen = (await call("GET", `/lobbies/${made.id}`, ann)).json();
  assert.equal(seen.hostId, ann.user.id);
  assert.deepEqual(seen.members.map((m: { name: string }) => m.name), ["Ann", "Bo"]);
  await app.close();
});

test("one member's poll is enough to list a lobby, and a lobby of all quiet members is not Quick-joined", async () => {
  const { app, clock, guest, call, codes } = await platform();
  const [ann, bo, cy] = [await guest("Ann"), await guest("Bo"), await guest("Cy")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });
  clock.now += 30 * SECOND;
  await call("GET", `/lobbies/${made.id}`, bo); // Bo polls; Ann has gone quiet
  assert.deepEqual(await codes(cy), [made.code]);

  // Everyone quiet: a stranger's Quick join does not walk into a lobby nobody is in.
  clock.now += 20 * SECOND;
  const quick = (await call("POST", "/lobbies/quick", cy)).json();
  assert.notEqual(quick.id, made.id, "Quick join made a night of its own");
  await app.close();
});

test("the page's word ends a lone player's lobby at once: gone from the list, its code and its lookups", async () => {
  const { app, guest, call, codes, beacon } = await platform();
  const [ann, bo] = [await guest("Ann"), await guest("Bo")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  assert.deepEqual(await codes(bo), [made.code]);

  const sent = await beacon(made.id, ann);
  assert.equal(sent.statusCode, 200);
  assert.deepEqual(sent.json(), { left: true });
  assert.deepEqual(await codes(bo), []);
  assert.equal((await call("GET", `/lobbies/${made.id}`, ann)).statusCode, 404);
  assert.equal((await call("POST", "/lobbies/join-by-code", bo, { code: made.code })).statusCode, 404);
  // Said twice (a beacon and the fetch behind it): the second changes nothing.
  assert.deepEqual((await beacon(made.id, ann)).json(), { left: false });
  await app.close();
});

test("the word is accepted as the browsers send it: a beacon body, a JSON body, or a header; a bad token changes nothing", async () => {
  const { app, guest, call, codes, beacon } = await platform();
  const [ann, bo] = [await guest("Ann"), await guest("Bo")];
  const url = (id: string) => `/lobbies/${id}/page-closed`;

  const a = (await call("POST", "/lobbies", ann, {})).json();
  const refused = [
    await app.inject({ method: "POST", url: url(a.id) }), // no token at all
    await app.inject({ method: "POST", url: url(a.id), headers: { "content-type": "text/plain" }, payload: "not json" }),
    await app.inject({ method: "POST", url: url(a.id), headers: { "content-type": "text/plain" }, payload: JSON.stringify({ token: "forged.token.here" }) }),
    await app.inject({ method: "POST", url: url(a.id), headers: { authorization: "Bearer forged.token.here" } }),
  ];
  assert.deepEqual(refused.map((r) => r.statusCode), [401, 401, 401, 401]);
  assert.deepEqual(await codes(bo), [a.code], "nobody could end it without the token");

  // Somebody else's token (not a member) and an unknown lobby: nothing happens.
  assert.deepEqual((await beacon(a.id, bo)).json(), { left: false });
  assert.deepEqual((await beacon("00000000-0000-4000-8000-000000000000", ann)).json(), { left: false });
  assert.deepEqual(await codes(bo), [a.code]);

  // A JSON body, and the header, both end it.
  const json = await app.inject({ method: "POST", url: url(a.id), headers: { "content-type": "application/json" }, payload: { token: ann.token } });
  assert.deepEqual(json.json(), { left: true });
  const b = (await call("POST", "/lobbies", ann, {})).json();
  assert.deepEqual((await call("POST", url(b.id), ann)).json(), { left: true });
  assert.deepEqual(await codes(bo), []);
  await app.close();
});

test("with others in the lobby the page's word is a Leave: the host role passes on and the rest carry on", async () => {
  const { app, guest, call, codes, beacon } = await platform();
  const [ann, bo, cy] = [await guest("Ann"), await guest("Bo"), await guest("Cy")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  await call("POST", "/lobbies/join-by-code", bo, { code: made.code });
  await call("POST", "/lobbies/join-by-code", cy, { code: made.code });

  assert.deepEqual((await beacon(made.id, ann)).json(), { left: true });
  const after = (await call("GET", `/lobbies/${made.id}`, bo)).json();
  assert.deepEqual(after.members.map((m: { name: string }) => m.name), ["Bo", "Cy"]);
  assert.equal(after.hostId, bo.user.id);
  assert.deepEqual(await codes(cy), [made.code]);
  // The one who left is told the plain truth by their next poll (a page that came back after all).
  assert.equal((await call("GET", `/lobbies/${made.id}`, ann)).json().error, "not_member");
  await app.close();
});

test("a night in progress ignores the page's word: its people are on the game server, whose socket close frees the seat", async () => {
  const { app, guest, call, codes, beacon } = await platform();
  const [ann, looker] = [await guest("Ann"), await guest("Looker")];
  const made = (await call("POST", "/lobbies", ann, {})).json();
  await call("POST", `/lobbies/${made.id}/start`, ann);
  assert.deepEqual((await beacon(made.id, ann)).json(), { left: false });
  assert.equal((await call("GET", `/lobbies/${made.id}`, ann)).statusCode, 200);
  assert.deepEqual(await codes(looker), [made.code]);
  await app.close();
});

test("a press on a row whose lobby has just gone says it is gone and leaves the player where they were", async () => {
  const { app, guest, call, codes, beacon } = await platform();
  const [ann, bo, cy] = [await guest("Ann"), await guest("Bo"), await guest("Cy")];
  const mine = (await call("POST", "/lobbies", bo, {})).json();
  const theirs = (await call("POST", "/lobbies", ann, {})).json();
  const rows = await codes(cy);
  assert.ok(rows.includes(theirs.code));

  // Ann's tab closes just before Bo presses her row (the list he holds is a few seconds old).
  await beacon(theirs.id, ann);
  const pressed = await call("POST", "/lobbies/join-by-code", bo, { code: theirs.code });
  assert.equal(pressed.statusCode, 404);
  assert.equal(pressed.json().error, "not_found");
  const still = await call("GET", `/lobbies/${mine.id}`, bo);
  assert.equal(still.statusCode, 200, "Bo is still in the lobby he was in");
  assert.deepEqual(still.json().members.map((m: { name: string }) => m.name), ["Bo"]);
  await app.close();
});
