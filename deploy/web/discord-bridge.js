// Runs only inside a Discord Activity (the page's head loads it when the address has `frame_id`, which Discord adds).
// Starts the Embedded App SDK, tells Discord the Activity is ready, and asks for the player's sign-in code
// (`authorize`, scopes `identify` and `guilds.members.read`: the second lets the backend read the player's nickname in
// the server the Activity runs in; if the player refuses it, `identify` alone is asked for). The game reads `window.deadnightDiscord` (net/together_api.gd): the code goes to the
// backend's /auth/discord, which swaps it for the player's name with the client secret that never leaves the server.
// The backend also answers with the player's own access token, and the game hands it back through
// `window.deadnightDiscord.authenticate(token)` (discord-share.js): Discord's client refuses `shareLink` and every
// other command with RPC error 4006 until the Activity has authenticated (Deadnight #627).
//
// The SDK is bundled into this file when the web image is built (deploy/web/Dockerfile), never committed.
import { DiscordSDK } from "@discord/embedded-app-sdk";
import { makeShare } from "./discord-share.js";

const CLIENT_ID = "1566609915219419286"; // public: the Discord application's id

const state = { ready: false, code: "", error: "", instanceId: "", guildId: "", canShare: false };
window.deadnightDiscord = state;

try {
  const sdk = new DiscordSDK(CLIENT_ID);
  state.instanceId = sdk.instanceId;
  state.guildId = sdk.guildId || "";
  await sdk.ready();
  state.ready = true;
  // Discord's own "share a link to this Activity" window (no OAuth scope, but an authenticated Activity: see
  // discord-share.js): the way to send a room's code to friends when the frame may not use the clipboard
  // (game/core/web_clipboard.gd). `custom_id` rides along in the link. discord-share.js keeps Discord's real answer for
  // the lobby's probe line, and `state.authenticate` for the sign-in that makes the window possible.
  makeShare(sdk, state);
  state.canShare = true;
  const authorize = (scope) =>
    sdk.commands.authorize({ client_id: CLIENT_ID, response_type: "code", state: "", prompt: "none", scope });
  let granted;
  try {
    granted = await authorize(["identify", "guilds.members.read"]);
  } catch (error) {
    console.warn("Discord nickname scope not granted, asking for identify only:", String(error));
    granted = await authorize(["identify"]);
  }
  state.code = granted.code;
} catch (error) {
  state.error = String(error);
  console.warn("Discord sign-in failed:", state.error);
}
