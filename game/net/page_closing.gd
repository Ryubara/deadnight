class_name PageClosing
extends RefCounted
## The page's last word to the backend when its tab closes (Deadnight #1188): a player alone on the
## waiting room who closes the tab says nothing, so the lobby stayed listed for the 10 minutes
## of its idle backstop. While the lobby screen is up, the web page holds one request ready, and
## sends it from the browser's `pagehide` event, which the browser gives a page that is going for
## good.
##
## What the signal means (docs/design/lobby.md#what-the-list-shows-and-the-pages-last-word-1188):
## - It is a Leave, and final. It is sent only for a page that is *unloading* (`pagehide` with
##   `persisted` false: a closed tab, a reload, a navigation away). A page that is only hidden or
##   frozen, or kept to be shown again (a phone that switches app, a tab in the background, the
##   browser's back-forward cache: `visibilitychange`, or `pagehide` with `persisted` true) sends
##   nothing, so someone who comes back finds the lobby as they left it.
## - A page that is thrown away by the system without a word (a phone short of memory) sends
##   nothing; the lobby is then left out of the Server Browser within seconds (nobody is polling
##   it) and goes with its idle backstop, as before.
##
## How it is sent (measured in Chromium, Firefox and WebKit,
## tools/web_smoke/page_closing_transport.py):
## `navigator.sendBeacon(url, text)` with a *string*, so the request is `text/plain` (a simple
## request: no CORS preflight, which a closing page may not wait for) and carries the session token
## in its body, because a beacon cannot set an `Authorization` header. A `Blob` body is not sent by
## Firefox when the tab closes, and an `application/json` one needs a preflight and is sent by no
## browser. If `sendBeacon` refuses (its queue is full), `fetch` with `keepalive` and the same
## simple request is the fallback.
##
## The listener is plain JavaScript, installed once and fed the request to send: it does not call
## back into the game, whose main loop may not run while the page unloads.

const INSTALL_JS := """(function () {
  var s = window.deadnightClosing;
  if (!s) {
    s = window.deadnightClosing = { url: '', body: '', sent: 0, how: '' };
    window.addEventListener('pagehide', function (event) {
      if (event.persisted || !s.url) return;
      var url = s.url, body = s.body;
      s.url = '';
      s.sent += 1;
      try {
        if (navigator.sendBeacon(url, body)) { s.how = 'beacon'; return; }
      } catch (error) {}
      try {
        fetch(url, {
          method: 'POST', keepalive: true, body: body,
          headers: { 'Content-Type': 'text/plain;charset=UTF-8' }
        });
        s.how = 'fetch';
      } catch (error) { s.how = 'failed'; }
    });
  }
  return s;
})()"""

## For a test: called with the JS to run on the page instead of `JavaScriptBridge.eval`.
static var eval_js := Callable()
## The request held ready now (`{"url", "body"}`, empty when none) and the lobby it is for: what a
## test reads, and what `disarm` compares so a screen that is going does not clear the next one's.
static var armed := {}
static var armed_for := ""


## Holds `request` (`TogetherApi.page_closing_request`) ready for the lobby with `lobby_id`.
static func arm(lobby_id: String, request: Dictionary) -> void:
	armed = request
	armed_for = lobby_id
	_hold(request.get("url", ""), request.get("body", ""))


## Takes the request back, when it is still the one for `lobby_id` (a screen that is going must not
## clear the one that replaced it).
static func disarm(lobby_id: String) -> void:
	if armed.is_empty() or lobby_id != armed_for:
		return
	armed = {}
	armed_for = ""
	_hold("", "")


## What the page has done, as `{"sent": <times>, "how": "beacon" | "fetch" | "failed" | ""}`;
## empty off
## the web. A browser test reads it in a page that is still alive (a closed one cannot be asked).
static func read() -> Dictionary:
	if not _can_eval():
		return {}
	var parsed: Variant = JSON.parse_string(str(_eval("JSON.stringify(%s)" % INSTALL_JS)))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _hold(url: String, body: String) -> void:
	if not _can_eval():
		return
	_eval(
		(
			"(function (s) { s.url = %s; s.body = %s; })(%s)"
			% [JSON.stringify(url), JSON.stringify(body), INSTALL_JS]
		)
	)


static func _can_eval() -> bool:
	return eval_js.is_valid() or OS.has_feature("web")


static func _eval(js: String) -> Variant:
	return eval_js.call(js) if eval_js.is_valid() else JavaScriptBridge.eval(js)
