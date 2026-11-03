// The Share in Discord button's side of the bridge (discord-bridge.js imports it; the Activity harness,
// tools/web_smoke/activity.py, imports the same file with a stand-in for the SDK, so what the harness runs is this code).
//
// The SDK's `shareLink` answers when Discord's window is closed, not when it opens: a promise that is still pending is
// the only sign that a window may be up. It rejects with a plain `{code, message}` object (not an Error: `String(error)`
// says "[object Object]"), and a reply the SDK cannot parse (a client that leaves out `didCopyLink`, `didSendMessage`)
// is a ZodError. So this module keeps what Discord really answered, and reduces it to one `verdict` the game reads:
//
//   asking      the command was sent less than GRACE_MS ago and Discord has not refused it
//   open        still no answer after GRACE_MS: Discord has not refused, a window may be up (the only "opened" there is)
//   shared      the window answered success (a message was sent or the link copied)
//   closed      the window answered success=false after REFUSED_MS: it was open, and the player closed it
//   refused     an error, or success=false at once (under REFUSED_MS): Discord opened nothing
//   unreadable  Discord answered, but the SDK could not parse the answer, so its promise never settles (the SDK logs
//               "Failed to parse" and returns): a window may have been up; the raw answer is kept in `raw`
//
// The SDK hides the raw answer when it cannot parse it, so a listener on the page's `message` events keeps the last
// `SHARE_LINK` frame Discord sent (`raw`, display only).
//
// When Discord refuses, `openInviteDialog` (Discord's channel invite window, no scope) is tried once as the other way to
// reach friends; its answer is kept in `invite`.
//
// Discord's client refuses nearly every command, `shareLink` and `openInviteDialog` among them, with RPC error 4006
// ("Not authenticated or invalid scope") until the Activity has run `authenticate` with an access token (Deadnight #627:
// the first fix only reported the refusal; the cause was that the bridge never authenticated). `authorize` alone, which
// gives the sign-in code, does not do it. The backend swaps the code for the token (`POST /auth/discord` returns it) and
// the game hands it to `state.authenticate(token)`; `state.auth` keeps how that went (`none`, `pending`, `ok`, `unread`,
// `failed`), and a share pressed while it is pending waits for it (AUTH_WAIT_MS).

export const GRACE_MS = 1000;
export const REFUSED_MS = 400;
export const AUTH_WAIT_MS = 5000;

/** What an SDK failure is, as text: `{kind, code, detail}`. */
export function describeError(error) {
  if (error && typeof error === "object" && Array.isArray(error.issues)) {
    const first = error.issues[0] || {};
    const where = Array.isArray(first.path) ? first.path.join(".") : "";
    return { kind: "schema", code: "", detail: `${where} ${first.message || "bad answer"}`.trim() };
  }
  if (error instanceof Error) {
    return { kind: "error", code: "", detail: `${error.name}: ${error.message}` };
  }
  if (error && typeof error === "object") {
    // The SDK rejects with the client's own `{code, message}`.
    return { kind: "rpc", code: String(error.code ?? ""), detail: String(error.message ?? JSON.stringify(error)) };
  }
  return { kind: "error", code: "", detail: String(error) };
}

/**
 * Puts `share(message, customId)` and `shareJson()` on `state`. `share` returns at once (the game does not wait for a
 * window); `shareJson` is what the game reads every frame. `clock`, `log` and `target` (where `message` events arrive) are
 * for tests.
 */
export function makeShare(sdk, state, clock = () => performance.now(), log = console, target = globalThis) {
  let seq = 0;
  // How `authenticate` went: `none` (no token was ever given: a guest, or the backend could not swap the code), `pending`,
  // `ok`, `unread` (Discord answered but the SDK could not read the answer: the client is authenticated all the same) and
  // `failed` (Discord refused the token).
  let auth = { status: "none", detail: "", scopes: [] };
  let authPending = null;
  let askedAt = 0;
  let sentAt = 0; // when the command went to Discord (0: still waiting for authenticate)
  let s = blank();

  function blank() {
    return {
      verdict: "idle",
      ms: 0,
      success: null,
      didCopyLink: null,
      didSendMessage: null,
      kind: "",
      code: "",
      detail: "",
      raw: "",
      invite: "",
      inviteDetail: "",
      auth: auth.status,
      authDetail: auth.detail,
    };
  }

  state.authenticate = (accessToken) => {
    if (!accessToken) return false;
    auth = { status: "pending", detail: "", scopes: [] };
    let pending;
    try {
      pending = Promise.resolve(sdk.commands.authenticate({ access_token: accessToken }));
    } catch (error) {
      pending = Promise.reject(error);
    }
    const mine = (authPending = pending.then(
      (answer) => {
        auth = { status: "ok", detail: "", scopes: Array.isArray(answer && answer.scopes) ? answer.scopes.map(String) : [] };
        log.info("Discord authenticate: ok, scopes", auth.scopes.join(" "));
      },
      (error) => {
        const why = describeError(error);
        // A schema failure is Discord's answer arriving in a shape the SDK cannot read: the client did authenticate.
        auth = { status: why.kind === "schema" ? "unread" : "failed", detail: `${why.code} ${why.detail}`.trim(), scopes: [] };
        log.warn("Discord authenticate:", auth.status, auth.detail);
      },
    ));
    mine.then(() => {
      if (authPending === mine) authPending = null;
    });
    return true;
  };

  state.authJson = () => JSON.stringify(auth);

  // Discord's own frame for our command, whatever the SDK made of it. The SDK handles the event first (it listened
  // first); a promise still pending a moment later means the SDK could not read the frame.
  if (target && typeof target.addEventListener === "function") {
    target.addEventListener("message", (event) => {
      const frame = Array.isArray(event.data) && event.data[0] === 1 ? event.data[1] : null;
      if (!frame || frame.cmd !== "SHARE_LINK" || s.verdict === "idle") return;
      const token = seq;
      s.raw = JSON.stringify({ evt: frame.evt, data: frame.data }).slice(0, 300);
      log.info("Discord share: Discord's frame", s.raw);
      setTimeout(() => {
        if (token === seq && (s.verdict === "asking" || s.verdict === "open")) {
          settle(token, "unreadable", { kind: "schema", detail: "the SDK could not read Discord's answer" });
        }
      }, 50);
    });
  }

  function settle(token, verdict, patch) {
    if (token !== seq) return false; // a later press owns the state now
    s = { ...s, ...patch, verdict, ms: Math.round(clock() - askedAt) };
    return true;
  }

  function inviteInstead(token) {
    s.invite = "asking";
    let pending;
    try {
      pending = Promise.resolve(sdk.commands.openInviteDialog());
    } catch (error) {
      pending = Promise.reject(error);
    }
    pending.then(
      () => {
        if (token !== seq) return;
        s.invite = "opened";
        log.info("Discord share: the invite window was asked for and answered");
      },
      (error) => {
        if (token !== seq) return;
        const why = describeError(error);
        s.invite = "failed";
        s.inviteDetail = `${why.code} ${why.detail}`.trim();
        log.warn("Discord share: the invite window failed:", s.inviteDetail);
      },
    );
  }

  state.share = (message, customId) => {
    const token = ++seq;
    askedAt = clock();
    sentAt = 0;
    s = { ...blank(), verdict: "asking" };
    log.info("Discord share: asking, message length", String(message).length, "custom_id", customId);
    // Discord refuses every command (4006) from an Activity that has not authenticated: a press while that is still
    // being answered waits for it (never longer than AUTH_WAIT_MS), so the refusal is never ours to cause.
    if (authPending) {
      const waited = authPending;
      let timer;
      const timeout = new Promise((resolve) => {
        timer = setTimeout(resolve, AUTH_WAIT_MS);
      });
      Promise.race([waited, timeout]).then(() => {
        clearTimeout(timer);
        if (token === seq) send(token, message, customId);
      });
    } else {
      send(token, message, customId);
    }
    return true;
  };

  function send(token, message, customId) {
    sentAt = clock();
    s.auth = auth.status;
    s.authDetail = auth.detail;
    let pending;
    try {
      pending = Promise.resolve(sdk.commands.shareLink({ message, custom_id: customId }));
    } catch (error) {
      pending = Promise.reject(error);
    }
    pending.then(
      (answer) => {
        const elapsed = clock() - sentAt;
        const success = Boolean(answer && answer.success);
        const verdict = success ? "shared" : elapsed < REFUSED_MS ? "refused" : "closed";
        const detail = !success && verdict === "refused" ? "answered success=false at once" : "";
        const patch = {
          success,
          didCopyLink: Boolean(answer && answer.didCopyLink),
          didSendMessage: Boolean(answer && answer.didSendMessage),
          detail,
        };
        if (settle(token, verdict, patch)) {
          log.info("Discord share: answer", JSON.stringify(answer), "after", s.ms, "ms:", verdict);
          if (verdict === "refused") inviteInstead(token);
        }
      },
      (error) => {
        const why = describeError(error);
        if (settle(token, "refused", why)) {
          log.warn("Discord share: error", why.kind, why.code, why.detail, "after", s.ms, "ms: refused");
          inviteInstead(token);
        }
      },
    );
  }

  state.shareJson = () => {
    const now = Math.round(clock() - askedAt);
    if (s.verdict === "asking" || s.verdict === "open") {
      s.ms = now;
      s.verdict = sentAt && clock() - sentAt >= GRACE_MS ? "open" : "asking";
    }
    return JSON.stringify(s);
  };
}
