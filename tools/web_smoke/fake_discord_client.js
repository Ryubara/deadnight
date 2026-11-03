// A stand-in for Discord's client, to run in the page around an Activity's frame (tools/web_smoke/activity.py
// `--real-bridge`). It speaks the Embedded App SDK's frame protocol over `postMessage`, so the Activity runs the SDK
// and `deploy/web/discord-bridge.js` as they ship, and the page answers as the real client was seen to:
//
//   - HANDSHAKE gets the READY event, which lets `sdk.ready()` return;
//   - AUTHORIZE gives a sign-in code that the local backend (DISCORD_MODE=stub) swaps for the player and an access token
//     (`stub-access-<id>`);
//     (`refuse-authorize`: refuses it, so the Activity has no token and the game plays as a guest);
//   - AUTHENTICATE takes that token and marks the session authenticated (`reject-token`: refuses it, RPC error 4009);
//   - every other command, SHARE_LINK and OPEN_INVITE_DIALOG included, is refused at once with RPC error 4006
//     "Not authenticated or invalid scope" until the session is authenticated: the answer the maintainer's press got
//     from the real client in Deadnight #627, from a bridge that never called `authenticate`. Once authenticated,
//     SHARE_LINK opens a window that answers success after `windowMs`, and OPEN_INVITE_DIALOG answers at once.
//
// What is observed and what is modelled: the 4006 frame and its 17 ms are the real client's (the maintainer's
// diagnostics line); that authenticate lifts it is Discord's documented flow (docs.discord.com, building an Activity:
// authorize, then authenticate with the access_token) and the SDK's own contract; the rest is this page's guess,
// so a green run proves the bridge follows the documented flow, and only a press in Discord proves Discord agrees.
//
// `window.discordHost` is what the run reads: every command in order (`commands`), `authenticated`, `shared`.
(() => {
  const options = window.discordHostOptions || {};
  const windowMs = options.windowMs ?? 1500;
  const USER = { id: "777", username: "tester", global: "Tester", nick: "Tester Nick" };
  const TOKEN = `stub-access-${USER.id}`;
  const host = (window.discordHost = {
    commands: [],
    authenticated: false,
    authorizedScopes: [],
    shared: null,
    invited: 0,
    refusals: 0,
  });
  const frame = () => document.querySelector("iframe");
  const answer = (cmd, nonce, data, evt = null) => {
    const target = frame();
    if (target && target.contentWindow) {
      target.contentWindow.postMessage([1, { cmd, evt, data, nonce }], "*");
    }
  };
  const refuse = (cmd, nonce, code, message) => {
    host.refusals += 1;
    answer(cmd, nonce, { code, message }, "ERROR");
  };

  window.addEventListener("message", (event) => {
    const target = frame();
    if (!target || event.source !== target.contentWindow || !Array.isArray(event.data)) return;
    const [opcode, payload] = event.data;
    if (opcode === 0) {
      // HANDSHAKE: the SDK waits for READY.
      target.contentWindow.postMessage(
        [
          1,
          {
            cmd: "DISPATCH",
            evt: "READY",
            nonce: null,
            data: { v: 1, config: { cdn_host: "cdn.discordapp.com", api_endpoint: "//discord.com/api", environment: "production" } },
          },
        ],
        "*",
      );
      return;
    }
    if (opcode !== 1 || !payload || !payload.cmd) return;
    const { cmd, nonce, args } = payload;
    if (cmd !== "CAPTURE_LOG") host.commands.push({ cmd, args: cmd === "AUTHENTICATE" ? "(token)" : args });
    switch (cmd) {
      case "CAPTURE_LOG":
        return answer(cmd, nonce, null);
      case "SUBSCRIBE":
      case "UNSUBSCRIBE":
        return answer(cmd, nonce, { evt: payload.evt });
      case "AUTHORIZE":
        // `refuse-authorize`: the player turns the sign-in down, so the game plays as a guest and never authenticates.
        if (options.mode === "refuse-authorize") return refuse(cmd, nonce, 5000, "OAuth2 authorization was refused");
        host.authorizedScopes = (args && args.scope) || [];
        return answer(cmd, nonce, { code: `stub:${USER.id}:${USER.username}:${USER.global}:${USER.nick}` });
      case "AUTHENTICATE": {
        if (options.mode === "reject-token" || !args || args.access_token !== TOKEN) {
          return refuse(cmd, nonce, 4009, "Invalid token");
        }
        host.authenticated = true;
        return answer(cmd, nonce, {
          access_token: TOKEN,
          user: { username: USER.username, discriminator: "0", id: USER.id, avatar: null, public_flags: 0, global_name: USER.global },
          scopes: host.authorizedScopes,
          expires: "2099-01-01T00:00:00.000000+00:00",
          application: { description: "", icon: null, id: "1566609915219419286", name: "Deadnight" },
        });
      }
      default:
        break;
    }
    if (!host.authenticated) {
      // The real client's own words (the maintainer's diagnostics), after about 17 ms.
      return setTimeout(() => refuse(cmd, nonce, 4006, "Not authenticated or invalid scope"), 15);
    }
    if (cmd === "SHARE_LINK") {
      host.shared = { message: args && args.message, customId: args && args.custom_id };
      return setTimeout(() => answer(cmd, nonce, { success: true, didCopyLink: false, didSendMessage: true }), windowMs);
    }
    if (cmd === "OPEN_INVITE_DIALOG") {
      host.invited += 1;
      return answer(cmd, nonce, null);
    }
    return refuse(cmd, nonce, 4002, `Invalid command: ${cmd}`);
  });
})();
