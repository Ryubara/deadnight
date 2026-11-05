// The calling card and the emblem a player chose travel in their ticket (Deadnight #1070): read from the stored
// profile's `equipped` (never from the client on that call), with the challenges the player finished, which the game
// server holds the two choices to. An id that is not a plain name is not signed, and a player who chose nothing
// carries neither.
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildApp } from "../src/app.ts";
import { loadConfig } from "../src/config.ts";
import { OffDiscord } from "../src/discord.ts";
import { PROFILE_SLOT, TICKET_DONE, freshProfile } from "../src/progression.ts";
import { GameServerRegistry } from "../src/servers.ts";
import { MemoryStore } from "../src/store.ts";
import { verifyToken } from "../src/tokens.ts";

const config = loadConfig({
  SESSION_SECRET: "s".repeat(32),
  TICKET_SECRET: "t".repeat(32),
  GAME_SERVER_SECRET: "g".repeat(32),
  DISCORD_MODE: "off",
  GUEST_SIGN_IN: "1",
  NODE_ENV: "production",
});

async function platform() {
  const clock = { now: 5_000_000 };
  const registry = new GameServerRegistry(60 * 60_000, () => clock.now);
  const store = new MemoryStore();
  const app = buildApp({ config, store, discord: new OffDiscord(), registry, now: () => clock.now });
  await app.inject({
    method: "POST",
    url: "/internal/servers/heartbeat",
    headers: { authorization: `Bearer ${config.gameServerSecret}` },
    payload: { id: "gs", url: "wss://gs.example", activityPath: "/gs", capacity: 4, matchIds: [], players: {} },
  });
  const call = (method: "GET" | "POST", url: string, headers: object, payload?: object) => app.inject({ method, url, headers, payload });
  /** A guest account whose stored profile is `profile`. */
  const player = async (name: string, profile: Record<string, unknown>) => {
    const response = await app.inject({ method: "POST", url: "/auth/guest", payload: { name } });
    const id = (response.json().user as { id: string }).id;
    await store.putSave(id, PROFILE_SLOT, { schemaVersion: 1, data: { ...freshProfile(), ...profile } }, 0);
    return { id, headers: { authorization: `Bearer ${response.json().token}` } };
  };
  /** The claims of the ticket the player gets for a started lobby of their own. */
  const claims = async (who: { headers: object }) => {
    const lobby = (await call("POST", "/lobbies", who.headers, {})).json();
    assert.equal((await call("POST", `/lobbies/${lobby.id}/start`, who.headers, {})).statusCode, 200);
    const answer = await call("POST", `/lobbies/${lobby.id}/ticket`, who.headers, {});
    assert.equal(answer.statusCode, 200, answer.body);
    return verifyToken(config.ticketSecret, "ticket", answer.json().ticket) as Record<string, unknown>;
  };
  return { app, player, claims };
}

test("a ticket carries the chosen card, emblem and frame and the challenges finished", async () => {
  const { app, player, claims } = await platform();
  const ana = await player("ana", {
    equipped: { card: "dead_eye", emblem: "walk_in", frame: "filmstrip" },
    done: ["f_dead_eye", "f_walk_in", "f_filmstrip"],
  });
  const ticket = await claims(ana);
  assert.equal(ticket.card, "dead_eye");
  assert.equal(ticket.emblem, "walk_in");
  assert.equal(ticket.frame, "filmstrip");
  assert.deepEqual(ticket.done, ["f_dead_eye", "f_walk_in", "f_filmstrip"]);
  await app.close();
});

test("a player who chose nothing carries neither, and no list of what they finished", async () => {
  const { app, player, claims } = await platform();
  const ben = await player("ben", { done: ["f_walk_in"] });
  const ticket = await claims(ben);
  assert.equal("card" in ticket, false);
  assert.equal("emblem" in ticket, false);
  assert.equal("frame" in ticket, false);
  assert.equal("done" in ticket, false);
  assert.equal(ticket.level, 1, "the level claim is still there");
  await app.close();
});

test("an id that is not a plain name is not signed", async () => {
  const { app, player, claims } = await platform();
  const eve = await player("eve", { equipped: { card: "Dead Eye; DROP", emblem: 7, frame: "../x" }, done: [] });
  const ticket = await claims(eve);
  assert.equal("card" in ticket, false);
  assert.equal("emblem" in ticket, false);
  assert.equal("frame" in ticket, false);
  const long = await player("long", { equipped: { card: "a".repeat(41), emblem: "ok_name" }, done: [] });
  const second = await claims(long);
  assert.equal("card" in second, false);
  assert.equal(second.emblem, "ok_name");
  await app.close();
});

test("the lobby's member list shows each member's chosen card, emblem and frame beside the level", async () => {
  const { app, player } = await platform();
  const ana = await player("ana", { equipped: { card: "cartoon", emblem: "admit_one", frame: "chrome" } });
  const bo = await player("bo", {});
  const lobby = (await app.inject({ method: "POST", url: "/lobbies", headers: ana.headers, payload: {} })).json();
  // The profile is read once, when the member joins or asks for a ticket (the list is built without waiting).
  const joined = await app.inject({ method: "POST", url: "/lobbies/join-by-code", headers: bo.headers, payload: { code: lobby.code } });
  assert.equal(joined.statusCode, 200, joined.body);
  await app.inject({ method: "POST", url: `/lobbies/${lobby.id}/start`, headers: ana.headers, payload: {} });
  await app.inject({ method: "POST", url: `/lobbies/${lobby.id}/ticket`, headers: ana.headers, payload: {} });
  const view = (await app.inject({ method: "GET", url: `/lobbies/${lobby.id}`, headers: ana.headers })).json();
  const members = view.members as { userId: string; card?: string; emblem?: string; frame?: string }[];
  assert.deepEqual([members[0]!.card, members[0]!.emblem, members[0]!.frame], ["cartoon", "admit_one", "chrome"]);
  assert.equal("card" in members[1]!, false, "a member who chose nothing has no card key");
  await app.close();
});

test("only the last finished challenges are signed, so a ticket stays small", async () => {
  const { app, player, claims } = await platform();
  const done = Array.from({ length: TICKET_DONE + 40 }, (_, i) => `c_${i}`);
  const dee = await player("dee", { equipped: { card: "dead_eye" }, done });
  const ticket = await claims(dee);
  assert.equal((ticket.done as string[]).length, TICKET_DONE);
  assert.equal((ticket.done as string[]).at(-1), `c_${TICKET_DONE + 39}`);
  await app.close();
});
