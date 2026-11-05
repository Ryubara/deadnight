// Tests the page's last word (game/net/page_closing.gd, Deadnight #1188) against a stand-in window, for the part a headless
// browser cannot be made to do: a page the browser keeps to show again (`pagehide` with `persisted` true, a phone that
// switched app and the back-forward cache) sends nothing, a page that is going for good sends once, and a refused beacon falls
// back to `fetch` with `keepalive`. The real browsers close a real tab in tools/web_smoke/page_closing_transport.py and
// tools/web_smoke/page_closing.py.
//
//   node --test tools/web_smoke/test_page_closing.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../../game/net/page_closing.gd", import.meta.url), "utf8");
const INSTALL_JS = /const INSTALL_JS := """([\s\S]*?)"""/.exec(source)?.[1];

/** A page that ran the installer: what it sent, and the listener the browser would call on `pagehide`. */
function page({ beacon = () => true } = {}) {
  const sent = [];
  const fetched = [];
  const listeners = {};
  const window = { addEventListener: (name, fn) => (listeners[name] = fn) };
  const context = {
    window,
    navigator: { sendBeacon: (url, body) => (sent.push([url, body]), beacon()) },
    fetch: (url, options) => fetched.push([url, options]),
  };
  const state = vm.runInNewContext(INSTALL_JS, context);
  assert.equal(window.deadnightClosing, state, "the state is on the window");
  return {
    state,
    sent,
    fetched,
    arm: (url, body) => Object.assign(state, { url, body }),
    pagehide: (persisted) => listeners.pagehide({ persisted }),
    install: () => vm.runInNewContext(INSTALL_JS, context),
  };
}

test("the installer was found in the script", () => {
  assert.ok(INSTALL_JS && INSTALL_JS.includes("pagehide"));
});

test("a page kept to be shown again sends nothing, and still has its word when it comes back", () => {
  const p = page();
  p.arm("https://b.example/lobbies/L/page-closed", '{"token":"T"}');
  p.pagehide(true);
  assert.deepEqual(p.sent, []);
  assert.equal(p.state.url, "https://b.example/lobbies/L/page-closed", "kept for the page that comes back");
  p.pagehide(false);
  assert.equal(p.sent.length, 1);
});

test("a page that is going sends its word once, as a string body to the armed address", () => {
  const p = page();
  p.arm("https://b.example/lobbies/L/page-closed", '{"token":"T"}');
  p.pagehide(false);
  p.pagehide(false);
  assert.deepEqual(p.sent, [["https://b.example/lobbies/L/page-closed", '{"token":"T"}']]);
  assert.equal(typeof p.sent[0][1], "string", "a string: Firefox does not send a Blob beacon when the tab closes");
  assert.equal(p.state.how, "beacon");
  assert.equal(p.state.sent, 1);
});

test("a page with nothing armed sends nothing", () => {
  const p = page();
  p.pagehide(false);
  assert.deepEqual(p.sent, []);
  p.arm("https://b.example/x", "{}");
  p.arm("", "");
  p.pagehide(false);
  assert.deepEqual(p.sent, []);
});

test("a beacon the browser refuses falls back to a keepalive fetch of the same simple request", () => {
  const p = page({ beacon: () => false });
  p.arm("https://b.example/lobbies/L/page-closed", '{"token":"T"}');
  p.pagehide(false);
  assert.equal(p.fetched.length, 1);
  const [url, options] = p.fetched[0];
  assert.equal(url, "https://b.example/lobbies/L/page-closed");
  assert.equal(options.keepalive, true);
  assert.equal(options.method, "POST");
  assert.deepEqual(Object.keys(options.headers), ["Content-Type"], "no Authorization: that would need a preflight");
  assert.match(options.headers["Content-Type"], /^text\/plain/);
  assert.equal(p.state.how, "fetch");
});

test("installing again keeps the one listener and the word that was armed", () => {
  const p = page();
  p.arm("https://b.example/x", "{}");
  p.install();
  p.pagehide(false);
  assert.equal(p.sent.length, 1);
});
