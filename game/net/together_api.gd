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
## What a player reads for each reason the backend gives.
const TEXTS := {
	"not_found": "There is no night with that code. Check it and try again.",
	"full": "That night is full.",
	"no_server": "All the servers are busy. Try again in a minute.",
	"already_in_lobby": "You are in another night already.",
	"too_many_guests": "Too many people signed in from here. Try again later.",
	"unauthorized": "Your sign-in ran out. Try again.",
	"network": "Could not reach the game's servers. Check your connection.",
}

static var _token := ""
static var _user := {}

## The backend's base address; a test or `?backend=` changes it.
var base_url := DEFAULT_BACKEND
## The Discord Activity instance this player is in (empty on the web): everyone with the same one
## lands in the same night.
var instance_id := ""

var _parent: Node


func _init(parent: Node, backend: String = DEFAULT_BACKEND) -> void:
	_parent = parent
	base_url = backend.trim_suffix("/")


## Forgets the session (tests, and a player who signs out).
static func forget() -> void:
	_token = ""
	_user = {}


static func signed_in() -> bool:
	return _token != ""


static func user_name() -> String:
	return _user.get("name", "")


## Signs in as a guest unless this run already has a session.
func sign_in(display_name: String = "") -> Dictionary:
	if _token != "":
		return {"ok": true}
	var answer := await _call("POST", "/auth/guest", {"name": display_name}, false)
	if answer["ok"]:
		_token = answer["token"]
		_user = answer["user"]
	return answer


## A night of your own: made, started on a game server, and its invite code. `{"ok", "lobby"}`.
func create() -> Dictionary:
	var made := await _call("POST", "/lobbies", {"maxPlayers": 4, "instanceId": instance_id})
	if not made["ok"]:
		return made
	if made["state"] != "started":
		var started := await _call("POST", "/lobbies/%s/start" % made["id"])
		if not started["ok"]:
			return started
		made = started
	return {"ok": true, "lobby": made}


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
	if authorised and _token != "":
		headers["Authorization"] = "Bearer " + _token
	var answer := await HttpJson.send(_parent, method, base_url + path, headers, body)
	var status: int = answer["status"]
	var json: Variant = answer["json"]
	if status == 401:
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


static func _failed(reason: String) -> Dictionary:
	return {
		"ok": false,
		"error": reason,
		"text": TEXTS.get(reason, "Something went wrong (%s). Try again." % reason),
	}
