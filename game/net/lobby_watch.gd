class_name LobbyWatch
extends Node
## Keeps a lobby screen up to date: asks the backend for the lobby every `every` seconds
## (`TogetherApi.refresh`) and says what changed since the last answer. Polling, not a pushed
## channel: it is the same plain HTTPS call that already works through Discord's proxy, and the
## poll is also how the backend knows the member is still there (docs/design/lobby.md#poll-or-push).
##
## `changed` says the lobby moved (members, host, state, round); `happened` lists what a player is
## told, one dictionary each (`diff`); `ended` says the lobby is no longer the player's (they were
## dropped for being away, or it ended) with the words to show; `trouble` says the backend cannot
## be reached for a while, and `recovered` that it can again.

signal changed(lobby: Dictionary)
signal happened(events: Array)
signal ended(text: String)
signal trouble
signal recovered

## Seconds between polls: a join shows within this long.
const EVERY := 2.0
## Failed polls in a row before the screen says the backend cannot be reached.
const TROUBLE_AFTER := 3

var lobby := {}
var every := EVERY
var running := false

var _api: TogetherApi
var _timer: Timer
var _asking := false
var _failures := 0
var _me := ""


## The events between two answers about one lobby, for the player whose id is `me`: a seat taken
## (`joined`), a seat left (`left`), the host role moving (`host`, with `you` when it came to this
## player), the night starting (`started`) and the round moving on (`round`). Names are what the
## backend has. A lobby that was empty (`{}`) has nothing to compare with and says nothing.
static func diff(before: Dictionary, after: Dictionary, me: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if before.is_empty() or after.is_empty():
		return out
	var was := _by_id(before)
	var now := _by_id(after)
	for id: String in now:
		if not was.has(id):
			out.append({"kind": &"joined", "name": now[id]["name"], "you": id == me})
	for id: String in was:
		if not now.has(id):
			out.append({"kind": &"left", "name": was[id]["name"], "you": id == me})
	if before.get("hostId") != after.get("hostId") and now.has(after.get("hostId", "")):
		var host: Dictionary = now[after["hostId"]]
		out.append({"kind": &"host", "name": host["name"], "you": after["hostId"] == me})
	if before.get("state") != "started" and after.get("state") == "started":
		var starter := _name_of(before, str(before.get("hostId", "")))
		out.append({"kind": &"started", "name": starter})
	if after.get("round") != null and before.get("round") != after.get("round"):
		out.append({"kind": &"round", "round": int(after["round"])})
	return out


## Starts asking about `first` through `api`, with `me` as this player's backend id.
func watch(api: TogetherApi, first: Dictionary, me: String) -> void:
	_api = api
	lobby = first
	_me = me
	_failures = 0
	running = true
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = false
		_timer.timeout.connect(poll)
		add_child(_timer)
	_timer.start(every)


func stop() -> void:
	running = false
	if _timer != null:
		_timer.stop()


## One poll, now (the timer calls this; a test calls it to step by hand).
func poll() -> void:
	if not running or _asking or lobby.is_empty():
		return
	_asking = true
	var answer := await _api.refresh(lobby)
	_asking = false
	if not running:
		return
	if not answer["ok"]:
		_failed(answer)
		return
	if _failures >= TROUBLE_AFTER:
		recovered.emit()
	_failures = 0
	var next: Dictionary = answer["lobby"]
	var events := diff(lobby, next, _me)
	var moved := _fingerprint(next) != _fingerprint(lobby)
	lobby = next
	if moved:
		changed.emit(lobby)
	if not events.is_empty():
		happened.emit(events)


func _failed(answer: Dictionary) -> void:
	var reason := str(answer.get("error", ""))
	if reason == "not_member" or reason == "not_found":
		stop()
		ended.emit(str(answer.get("text", "")))
		return
	_failures += 1
	if _failures == TROUBLE_AFTER:
		trouble.emit()


## What a screen shows of a lobby: when it is the same, nothing needs drawing again. `away` is part
## of it (a member's mark changes with no one joining).
static func _fingerprint(from: Dictionary) -> String:
	return JSON.stringify(
		[
			from.get("state"),
			from.get("hostId"),
			from.get("round"),
			from.get("players"),
			from.get("members")
		]
	)


static func _by_id(from: Dictionary) -> Dictionary:
	var out := {}
	for member: Dictionary in from.get("members", []):
		out[str(member["userId"])] = member
	return out


static func _name_of(from: Dictionary, id: String) -> String:
	var member: Dictionary = _by_id(from).get(id, {})
	return str(member.get("name", "The host"))
