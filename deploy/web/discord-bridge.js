// Runs only inside a Discord Activity (the page's head loads it when the address has `frame_id`, which Discord adds).
// Starts the Embedded App SDK, tells Discord the Activity is ready, and asks for the player's sign-in code
// (`authorize`, scope `identify`). The game reads `window.deadnightDiscord` (net/together_api.gd): the code goes to the
// backend's /auth/discord, which swaps it for the player's name with the client secret that never leaves the server.
//
// The SDK is bundled into this file when the web image is built (deploy/web/Dockerfile), never committed.
import { DiscordSDK } from "@discord/embedded-app-sdk";

const CLIENT_ID = "1566609915219419286"; // public: the Discord application's id

const state = { ready: false, code: "", error: "", instanceId: "", canShare: false };
window.deadnightDiscord = state;

try {
  const sdk = new DiscordSDK(CLIENT_ID);
  state.instanceId = sdk.instanceId;
  await sdk.ready();
  state.ready = true;
  // Discord's own "share a link to this Activity" window (no OAuth scope): the way to send a room's code to friends
  // when the frame may not use the clipboard (game/core/web_clipboard.gd). `custom_id` rides along in the link.
  state.share = async (message, customId) => {
    try {
      const answer = await sdk.commands.shareLink({ message, custom_id: customId });
      return Boolean(answer.success);
    } catch (error) {
      console.warn("Discord share failed:", String(error));
      return false;
    }
  };
  state.canShare = true;
  const { code } = await sdk.commands.authorize({
    client_id: CLIENT_ID,
    response_type: "code",
    state: "",
    prompt: "none",
    scope: ["identify"],
  });
  state.code = code;
} catch (error) {
  state.error = String(error);
  console.warn("Discord sign-in failed:", state.error);
}
