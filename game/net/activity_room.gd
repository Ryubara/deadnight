class_name ActivityRoom
extends Node
## The Discord Activity's voice channel, made ready while the player is on the main menu: signed in
## (with Discord, else as a guest) and told what the channel's lobby is (nothing yet, a waiting room
## or a night in progress), so Play together goes to it at once. The game opens on the main menu
## like on every other platform (#495); this node is added to the root when the page address has
## `instance_id` and asks for nothing the player has to answer.
##
## It joins nothing: a seat in a lobby is taken when the player opens the lobby screen, so someone
## who only opened the Activity is not a member (and not missed by the host's Start).
##
## It is one node for the whole run: `current`. The screen prepares it again on a visit after a
## failure.

## Something about the room changed: `state` is the new state.
signal changed

enum State { PREPARING, READY, FAILED, IDLE }

## The room of this run, or null outside a Discord Activity.
static var current: ActivityRoom
## For a test: a Callable that answers `TogetherApi.preview_instance`'s `{"ok", "preview"}` (or a
## failure) instead of calling the backend.
static var preparer := Callable()

var state := State.IDLE
## What the channel's lobby looked like when the room got ready (`TogetherApi.preview_instance`'s
## preview), or empty when nobody had opened one.
var preview := {}
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


## Signs in and reads the channel's lobby. Safe to call again after a failure.
func prepare() -> void:
	if state == State.PREPARING:
		return
	_become(State.PREPARING)
	var seen := {}
	if preparer.is_valid():
		seen = await preparer.call()
	else:
		var signed := await api.sign_in()
		seen = signed if not signed["ok"] else await api.preview_instance()
	if not is_inside_tree():
		return
	if seen.get("ok", false):
		preview = seen["preview"]
		failure = ""
		_become(State.READY)
	elif seen.get("error", "") == "not_found":
		# Nobody has opened the channel's lobby: the room is ready, with nothing to show yet.
		preview = {}
		failure = ""
		_become(State.READY)
	else:
		preview = {}
		failure = str(seen.get("text", "Something went wrong."))
		_become(State.FAILED)


## Waits until the room is no longer preparing; true when it is ready.
func until_ready() -> bool:
	while state == State.PREPARING:
		await changed
	return state == State.READY


func _become(next: State) -> void:
	state = next
	changed.emit()
