class_name ActivityRoom
extends Node
## The night of a Discord Activity's voice channel, made ready while the player is on the main
## menu: sign in (with Discord, else as a guest) and make or find the lobby of the Activity's
## instance, so Play together shows the room code at once and one press of Play goes in. The game
## opens on the main menu like on every other platform (#495); this node is added to the root when
## the page address has `instance_id` and asks for nothing the player has to answer.
##
## It is one node for the whole run: `current`. A night entered from it makes it stale (the lobby
## of the next night may be another), and the screen prepares it again on the next visit.

## Something about the room changed: `state` is the new state.
signal changed

enum State { PREPARING, READY, FAILED, STALE }

## The room of this run, or null outside a Discord Activity.
static var current: ActivityRoom
## For a test: a Callable that answers `TogetherApi.create`'s `{"ok", "lobby"}` (or a failure)
## instead of calling the backend.
static var preparer := Callable()

var state := State.STALE
## The lobby of the instance once `state` is READY (`TogetherApi.create`'s).
var lobby := {}
## What a player reads when `state` is FAILED.
var failure := ""
var instance_id := ""
var api: TogetherApi


func _init(p_instance_id: String = "", backend: String = TogetherApi.DEFAULT_BACKEND) -> void:
	name = "ActivityRoom"
	instance_id = p_instance_id
	api = TogetherApi.new(self, backend)
	api.instance_id = p_instance_id


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Signs in and makes or finds the instance's lobby. Safe to call again after a failure or a night.
func prepare() -> void:
	if state == State.PREPARING:
		return
	_become(State.PREPARING)
	var made := {}
	if preparer.is_valid():
		made = await preparer.call()
	else:
		var signed := await api.sign_in()
		made = signed if not signed["ok"] else await api.create()
	if not is_inside_tree():
		return
	if made.get("ok", false):
		lobby = made["lobby"]
		failure = ""
		_become(State.READY)
	else:
		lobby = {}
		failure = str(made.get("text", "Something went wrong."))
		_become(State.FAILED)


## A night was entered from this room: the next visit makes a fresh one ready.
func mark_used() -> void:
	lobby = {}
	_become(State.STALE)


## Waits until the room is no longer preparing; true when it is ready.
func until_ready() -> bool:
	while state == State.PREPARING:
		await changed
	return state == State.READY


func _become(next: State) -> void:
	state = next
	changed.emit()
