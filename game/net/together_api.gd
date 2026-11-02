class_name TogetherApi
extends RefCounted
## What the game says to the platform backend to play with other people: sign in as a guest (a
## visitor with no Discord), make a night and its invite code, join by code, Quick join, and trade
## a lobby for the game server's address and a ticket (docs/research/platform-backend.md).
##
## Every call is awaited and answers `{"ok": true, ...}` or `{"ok": false, "error": <the backend's
## reason, or "network">, "text": <what to show a player>}`; none throws. The session is kept for
## the run (a static), so a second screen does not sign in again.

## The backend the project runs on Railway (guests only until Discord is set up there too).
const DEFAULT_BACKEND := "https://backend-production-bd67a.up.railway.app"
## What the bridge has: the code, '!' when it failed or there is none, '' while it is still asking.
const DISCORD_STATE_JS := (
	"window.deadnightDiscord ? (window.deadnightDiscord.code"
	+ " || (window.deadnightDiscord.error ? '!' : '')) : '!'"
)
## Seconds to wait for Discord's answer to the Activity's sign-in.
const DISCORD_WAIT_SECONDS := 30.0
## What a player reads for each reason the backend gives.
const TEXTS := {
	"not_found": "There is no night with that code. Check it and try again.",
	"full": "That night is full (4 of 4).",
	"no_server": "All the servers are busy. Try again in a minute.",
	"already_in_lobby": "You are in another night already.",
	"bad_settings": "Those rules are not ones the game takes. Change them and try again.",
	"not_member": "You were away for too long, so the room moved on. Make a night or join again.",
	"not_host": "Only the host can start the night.",
	"already_started": "The night has started already.",
	"too_many_guests": "Too many people signed in from here. Try again later.",
	"unauthorized": "Your sign-in ran out. Try again.",
	"network": "Could not reach the game's servers. Check your connection.",
}

static var _token := ""
static var _user := {}
## The Discord code this run traded in already: Discord takes a code once (a second try is a 400).
static var _spent_code := ""

## The backend's base address; a test or `?backend=` changes it.
var base_url := DEFAULT_BACKEND
## The Discord Activity instance this player is in (empty on the web): everyone with the same one
## lands in the same night.
var instance_id := ""
## Keeps this API's own session instead of the run's: a test with several players in one process
## gives each its own (the game itself has one player per run).
var isolated := false

var _parent: Node
var _own_token := ""
var _own_user := {}


func _init(parent: Node, backend: String = DEFAULT_BACKEND) -> void:
	_parent = parent
	base_url = backend.trim_suffix("/")


## The backend's id of this API's player (empty before sign-in): how a lobby screen knows which
## seat is its own and whether it is the host.
func my_id() -> String:
	return str((_own_user if isolated else _user).get("id", ""))


## Forgets the session (tests, and a player who signs out).
static func forget() -> void:
	_token = ""
	_user = {}
	_spent_code = ""


static func signed_in() -> bool:
	return _token != ""


static func user_name() -> String:
	return _user.get("name", "")


## Signs in unless this run already has a session: with Discord when the page is an Activity (its
## bridge, `deploy/web/discord-bridge.js`, has the OAuth code; the name is the player's nickname in
## the server, else their Discord display name), else, or when that does not work, as a guest
## called `display_name` (the backend cleans it; empty is `Guest NNNN`).
func sign_in(display_name: String = "") -> Dictionary:
	if _has_session():
		return {"ok": true}
	if instance_id != "" and OS.has_feature("web"):
		var code := await _discord_code()
		if code != "" and code != _spent_code:
			_spent_code = code
			var body := {"code": code}
			var guild := _discord_guild()
			if guild != "":
				body["guildId"] = guild
			var with_discord := await _call("POST", "/auth/discord", body, false)
			if with_discord["ok"]:
				_keep(with_discord["token"], with_discord["user"])
				return with_discord
	var answer := await _call("POST", "/auth/guest", {"name": display_name}, false)
	if answer["ok"]:
		_keep(answer["token"], answer["user"])
	return answer


## A night of your own: made, started on a game server, and its invite code. `{"ok", "lobby"}`.
## `settings` are the rules its host chose (`MatchSettingsPanel`); the backend keeps them on the
## lobby and signs them into every ticket, and the game server's room starts with them. Null is
## the usual rules. A night of this Activity that is already started keeps the rules it began with.
func create(settings: MatchSettings = null) -> Dictionary:
	var made := await _call("POST", "/lobbies", {"maxPlayers": 4, "instanceId": instance_id})
	if not made["ok"]:
		return made
	if made["state"] != "started":
		var started := await _call(
			"POST",
			"/lobbies/%s/start" % made["id"],
			{"settings": settings.clamped().to_dict()} if settings != null else null
		)
		if not started["ok"]:
			return started
		made = started
	return {"ok": true, "lobby": made}


## A lobby of your own, still waiting: the player is its host and seat 1, and nobody has a night
## until `start`. In a Discord Activity the lobby of the voice channel is found or made.
## `{"ok", "lobby"}`.
func create_lobby() -> Dictionary:
	var made := await _call("POST", "/lobbies", {"maxPlayers": 4, "instanceId": instance_id})
	return {"ok": true, "lobby": made} if made["ok"] else made


## The lobby as it is now (a member's poll, which is also the proof the member is still there).
## A player the backend dropped for being away, or a lobby that ended, answers `not_member` or
## `not_found`. `{"ok", "lobby"}`.
func refresh(lobby: Dictionary) -> Dictionary:
	var now := await _call("GET", "/lobbies/%s" % lobby["id"])
	return {"ok": true, "lobby": now} if now["ok"] else now


## The host starts the night: a game server is given to the lobby. `settings` are the rules as the
## host's panel shows them at that moment (they win over the ones sent while waiting); null keeps
## the ones the lobby holds. `{"ok", "lobby"}`.
func start(lobby: Dictionary, settings: MatchSettings = null) -> Dictionary:
	var started := await _call(
		"POST",
		"/lobbies/%s/start" % lobby["id"],
		{"settings": settings.clamped().to_dict()} if settings != null else null
	)
	return {"ok": true, "lobby": started} if started["ok"] else started


## The host sets the night's rules while the lobby waits; every member reads them on their next
## poll (`lobby["settings"]`, null for the usual rules). Refused after the start. `{"ok", "lobby"}`.
func set_settings(lobby: Dictionary, settings: MatchSettings) -> Dictionary:
	var answer := await _call(
		"PUT", "/lobbies/%s/settings" % lobby["id"], settings.clamped().to_dict()
	)
	return {"ok": true, "lobby": answer} if answer["ok"] else answer


## Leaves the lobby (the host role passes to the next seat). `{"ok"}`.
func leave(lobby: Dictionary) -> Dictionary:
	return await _call("POST", "/lobbies/%s/leave" % lobby["id"])


## What a code says before its holder joins: `{"ok", "preview": {code, state, round, players,
## maxPlayers, full, hostName, names}}`. Joins nobody.
func preview(code: String) -> Dictionary:
	var clean := code.strip_edges().to_upper()
	if clean.is_empty():
		return _failed("not_found")
	var seen := await _call("POST", "/lobbies/preview", {"code": clean})
	return {"ok": true, "preview": seen} if seen["ok"] else seen


## What the Discord Activity's voice channel has: `{"ok", "preview"}` of its lobby (waiting, or a
## night in progress), or `not_found` when nobody has opened one yet. Joins nobody.
func preview_instance() -> Dictionary:
	if instance_id == "":
		return _failed("not_found")
	var seen := await _call("POST", "/lobbies/preview", {"instanceId": instance_id})
	return {"ok": true, "preview": seen} if seen["ok"] else seen


## The node the requests of this API are made under (they stop when it stops processing).
func owner_node() -> Node:
	return _parent


## An API of the same backend and session that lives under `parent`: a screen takes one of its own
## (its requests must not wait on a screen the router has paused), and a screen that is leaving
## says `leave` through one under the root, which outlasts it.
func detached(parent: Node) -> TogetherApi:
	var other := TogetherApi.new(parent, base_url)
	other.instance_id = instance_id
	other.isolated = isolated
	other._own_token = _own_token
	other._own_user = _own_user
	return other


## The night an invite code names.
func join_code(code: String) -> Dictionary:
	var clean := code.strip_edges().to_upper()
	if clean.is_empty():
		return _failed("not_found")
	var joined := await _call("POST", "/lobbies/join-by-code", {"code": clean})
	return {"ok": true, "lobby": joined} if joined["ok"] else joined


## A public night with room, or a new one.
func quick() -> Dictionary:
	var joined := await _call("POST", "/lobbies/quick")
	return {"ok": true, "lobby": joined} if joined["ok"] else joined


## What it takes to connect to a lobby's night: `{"ok", "url", "ticket", "match"}`.
func ticket(lobby: Dictionary) -> Dictionary:
	var answer := await _call("POST", "/lobbies/%s/ticket" % lobby["id"])
	if not answer["ok"]:
		return answer
	var address: Dictionary = answer["address"]
	return {
		"ok": true,
		"url": address["url"],
		"activity_path": address["activityPath"],
		"ticket": answer["ticket"],
		"match": answer["matchId"],
	}


## The server (guild) the Activity runs in, as the bridge read it, for the backend to look up the
## player's nickname there; empty in a DM or a call, or when it is not a number.
func _discord_guild() -> String:
	var raw := str(
		JavaScriptBridge.eval("window.deadnightDiscord ? window.deadnightDiscord.guildId : ''")
	)
	return raw if raw.is_valid_int() and raw.length() <= 20 else ""


## The OAuth code the Discord bridge got from the Activity's `authorize()`: waits for it (the
## player may be asked to agree), and is empty when there is no bridge, it failed or took long.
func _discord_code() -> String:
	var waited := 0.0
	while waited < DISCORD_WAIT_SECONDS:
		var state := str(JavaScriptBridge.eval(DISCORD_STATE_JS))
		if state == "!":
			return ""
		if state != "":
			return state
		await _parent.get_tree().create_timer(0.25).timeout
		waited += 0.25
	return ""


## The invite link of a night: this page with `?room=CODE` (the web build), or just the code.
static func invite_link(code: String, page_url: String) -> String:
	if page_url == "":
		return code
	var bare := page_url.split("?")[0].split("#")[0]
	return "%s?room=%s" % [bare, code]


func _call(
	method: String, path: String, body: Variant = null, authorised: bool = true
) -> Dictionary:
	var headers := {}
	var token := _own_token if isolated else _token
	if authorised and token != "":
		headers["Authorization"] = "Bearer " + token
	var answer := await HttpJson.send(_parent, method, base_url + path, headers, body)
	var status: int = answer["status"]
	var json: Variant = answer["json"]
	if status == 401:
		if isolated:
			_own_token = ""
			_own_user = {}
		else:
			forget()
	if status >= 200 and status < 300:
		var out: Dictionary = json if typeof(json) == TYPE_DICTIONARY else {}
		out["ok"] = true
		return out
	var reason := "network"
	if status != 0:
		reason = (
			str((json as Dictionary).get("error", "bad_request"))
			if typeof(json) == TYPE_DICTIONARY
			else "bad_request"
		)
	return _failed(reason)


func _has_session() -> bool:
	return (_own_token if isolated else _token) != ""


func _keep(token: String, user: Dictionary) -> void:
	if isolated:
		_own_token = token
		_own_user = user
	else:
		_token = token
		_user = user


static func _failed(reason: String) -> Dictionary:
	return {
		"ok": false,
		"error": reason,
		"text": TEXTS.get(reason, "Something went wrong (%s). Try again." % reason),
	}
