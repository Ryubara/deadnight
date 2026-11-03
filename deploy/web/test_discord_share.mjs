// Tests the Discord bridge's share half (discord-share.js) against a stand-in for the SDK that behaves as the real
// client was seen to (Deadnight #627): every command is refused with RPC error 4006, "Not authenticated or invalid
// scope", until `authenticate` has been given the access token of the player's sign-in.
//
//   node --test deploy/web/test_discord_share.mjs
//
// No packages: the real SDK against a fake client runs in the browser probe (tools/web_smoke/activity.py --real-bridge).
import assert from "node:assert/strict";
import { mock, test } from "node:test";
import { AUTH_WAIT_MS, makeShare } from "./discord-share.js";

const TOKEN = "player-access-token";
const quiet = { info() {}, warn() {}, error() {} };
const tick = () => new Promise((resolve) => setImmediate(resolve));

/** An SDK whose client wants authenticate first. `authenticateAnswer` gives the answer to authenticate. */
function fakeSdk({ authenticateAnswer = () => Promise.resolve({ scopes: ["identify", "guilds.members.read"] }) } = {}) {
  const calls = [];
  let authenticated = false;
  const refuse = () => Promise.reject({ code: 4006, message: "Not authenticated or invalid scope" });
  return {
    calls,
    commands: {
      authenticate: (args) => {
        calls.push("authenticate");
        return Promise.resolve(authenticateAnswer(args)).then((answer) => {
          authenticated = args.access_token === TOKEN;
          return answer;
        });
      },
      shareLink: (args) => {
        calls.push("shareLink");
        return authenticated ? Promise.resolve({ success: true, didCopyLink: false, didSendMessage: true, args }) : refuse();
      },
      openInviteDialog: () => {
        calls.push("openInviteDialog");
        return authenticated ? Promise.resolve() : refuse();
      },
    },
  };
}

function make(sdk) {
  const state = {};
  let now = 0;
  makeShare(sdk, state, () => now, quiet, null);
  return { state, advance: (ms) => (now += ms), read: () => JSON.parse(state.shareJson()) };
}

test("an Activity that never authenticated is refused with 4006, and says its sign-in is none", async () => {
  const sdk = fakeSdk();
  const { state, read } = make(sdk);
  state.share("Join my night", "ABC234");
  await tick();
  await tick();
  const seen = read();
  assert.equal(seen.verdict, "refused");
  assert.equal(seen.code, "4006");
  assert.equal(seen.detail, "Not authenticated or invalid scope");
  assert.equal(seen.auth, "none");
  // The invite window is refused for the same reason (the maintainer's line said so).
  assert.equal(seen.invite, "failed");
  assert.match(seen.inviteDetail, /4006/);
});

test("authenticate runs first, then the share window is asked for and goes through", async () => {
  const sdk = fakeSdk();
  const { state, read } = make(sdk);
  assert.equal(state.authenticate(TOKEN), true);
  assert.equal(JSON.parse(state.authJson()).status, "pending");
  state.share("Join my night", "ABC234");
  for (let i = 0; i < 5; i++) await tick();
  assert.deepEqual(sdk.calls, ["authenticate", "shareLink"]);
  const seen = read();
  assert.equal(seen.verdict, "shared");
  assert.equal(seen.auth, "ok");
  assert.deepEqual(JSON.parse(state.authJson()).scopes, ["identify", "guilds.members.read"]);
});

test("a share pressed while authenticate is still being answered waits for it", async () => {
  let release;
  const sdk = fakeSdk({ authenticateAnswer: () => new Promise((resolve) => (release = () => resolve({ scopes: [] }))) });
  const { state, read } = make(sdk);
  state.authenticate(TOKEN);
  state.share("Join my night", "ABC234");
  for (let i = 0; i < 3; i++) await tick();
  assert.deepEqual(sdk.calls, ["authenticate"], "the share window is not asked for while authenticate is pending");
  assert.equal(read().verdict, "asking", "the lobby is not told a window is open while the command is still unsent");
  release();
  for (let i = 0; i < 5; i++) await tick();
  assert.deepEqual(sdk.calls, ["authenticate", "shareLink"]);
  assert.equal(read().verdict, "shared");
});

test("a token Discord refuses leaves the sign-in failed with Discord's words, and the share is refused", async () => {
  const sdk = fakeSdk({ authenticateAnswer: () => Promise.reject({ code: 4009, message: "Invalid token" }) });
  const { state, read } = make(sdk);
  state.authenticate("a token that is not the player's");
  state.share("Join my night", "ABC234");
  for (let i = 0; i < 5; i++) await tick();
  const seen = read();
  assert.equal(seen.verdict, "refused");
  assert.equal(seen.code, "4006");
  assert.equal(seen.auth, "failed");
  assert.match(seen.authDetail, /4009 Invalid token/);
});

test("an authenticate answer the SDK cannot read still lets the share go: the client is authenticated", async () => {
  const sdk = fakeSdk({ authenticateAnswer: () => Promise.reject(Object.assign(new Error("bad"), { issues: [{ path: ["expires"], message: "Required" }] })) });
  const { state, read } = make(sdk);
  state.authenticate(TOKEN);
  state.share("Join my night", "ABC234");
  for (let i = 0; i < 5; i++) await tick();
  assert.deepEqual(sdk.calls.slice(0, 2), ["authenticate", "shareLink"]);
  assert.equal(JSON.parse(state.authJson()).status, "unread");
  assert.equal(read().auth, "unread");
});

test("an authenticate that never answers does not hold the share for ever", async () => {
  mock.timers.enable({ apis: ["setTimeout"] });
  try {
    const sdk = fakeSdk({ authenticateAnswer: () => new Promise(() => {}) });
    const { state, read } = make(sdk);
    state.authenticate(TOKEN);
    state.share("Join my night", "ABC234");
    await tick();
    assert.deepEqual(sdk.calls, ["authenticate"]);
    mock.timers.tick(AUTH_WAIT_MS);
    for (let i = 0; i < 5; i++) await tick();
    assert.deepEqual(sdk.calls.slice(0, 2), ["authenticate", "shareLink"]);
    assert.equal(read().auth, "pending");
  } finally {
    mock.timers.reset();
  }
});

test("no token means nothing is sent and the sign-in stays none", () => {
  const sdk = fakeSdk();
  const { state } = make(sdk);
  assert.equal(state.authenticate(""), false);
  assert.equal(state.authenticate(undefined), false);
  assert.deepEqual(sdk.calls, []);
  assert.equal(JSON.parse(state.authJson()).status, "none");
});
