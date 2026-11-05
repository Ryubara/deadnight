class_name LobbyPrivateSwitch
extends RefCounted
## The Private night row of the lobby (Deadnight #1186, docs/design/lobby.md): the host's switch is
## sent to the backend as it is pressed, a guest's shows what the host chose (read only). Off is a
## public night (`TogetherApi.PUBLIC_BY_DEFAULT`). The screen owns the lobby and the API; this owns
## the row, the press and the request: `LobbyScreen` calls `show_lobby` with each lobby it holds and
## `send` when `pressed` says so.

## A press of the host's switch: the screen sends it (`send`).
signal pressed
## A sentence for the lobby's note: what happened, or why the backend refused.
signal said(text: String)

## The two hints (a line each, short enough for the row's column, which trims what does not fit).
const HINT_ON := "Only the code gets in."
const HINT_OFF := "In the Server Browser."
## What the host reads after a change.
const SAID_ON := "The night is private. Friends join with the code."
const SAID_OFF := "The night is public. It is in the Server Browser."

var row: UIRow
var toggle: UIToggle
## Whether this player can move the switch now.
var editable := false

var _tree: SceneTree
var _shown := false
var _waiting: Variant = null
var _sending := false


## Builds the row, `width` units wide at least, a finger high (`MenuLook.TAP_TARGET`).
func build(scene_tree: SceneTree, width: float) -> UIRow:
	_tree = scene_tree
	row = UIRow.new()
	row.name = "PrivateRow"
	row.title = "Private night"
	row.custom_minimum_size = Vector2(width, MenuLook.TAP_TARGET)
	toggle = UIToggle.new()
	toggle.name = "Private"
	# A finger needs the row's height, and the pill keeps its proportions.
	toggle.custom_minimum_size = Vector2(
		MenuLook.TAP_TARGET * UIToggle.WIDTH_RATIO, MenuLook.TAP_TARGET
	)
	toggle.toggled.connect(_on_toggled)
	row.set_control(toggle)
	row.visible = false
	return row


## Whether the night is private as the switch shows it.
func is_private() -> bool:
	return toggle.button_pressed


## The switch for `held`: shown when the backend says `visibility` at all (an older one does not)
## and `shown`; the host's own while they use it (it takes the lobby's value once, when the role
## comes to them), a guest's follows the lobby. Unlike the rules it stays the host's after the
## start.
func show_lobby(held: Dictionary, shown: bool, is_host: bool) -> void:
	var supported := shown and held.has("visibility")
	row.visible = supported
	if not supported:
		editable = false
		_shown = false
		return
	if not is_host or not editable:
		toggle.set_pressed_no_signal(held.get("visibility") == "private")
	if is_host != editable or not _shown:
		toggle.focus_mode = Control.FOCUS_ALL if is_host else Control.FOCUS_NONE
		toggle.mouse_filter = Control.MOUSE_FILTER_STOP if is_host else Control.MOUSE_FILTER_IGNORE
	editable = is_host
	_shown = true
	_show_hint(is_private())


## Whether a press is still on its way to the backend.
func sending() -> bool:
	return _sending


## The row is gone (the lobby ended).
func hide_row() -> void:
	row.visible = false
	editable = false


## Sends the host's latest press (the screen calls this on `pressed`; a test calls it to step by
## hand). One request at a time: a press made while one is on its way follows it, and the last one
## wins. A refusal puts the switch back to what `lobby` holds and says why. `lobby` takes the
## backend's word for the visibility.
func send(api: TogetherApi, lobby: Dictionary, is_host: bool) -> void:
	if _waiting == null or _sending or api == null or not is_host:
		return
	_sending = true
	var wanted: bool = _waiting
	_waiting = null
	var answer := await api.set_visibility(lobby, not wanted)
	_sending = false
	if answer["ok"]:
		lobby["visibility"] = str(answer["lobby"].get("visibility", "public"))
		if _waiting == null:
			said.emit(SAID_ON if wanted else SAID_OFF)
	else:
		said.emit(str(answer.get("text", "")))
		if _waiting == null:
			toggle.set_pressed_no_signal(lobby.get("visibility") == "private")
			_show_hint(is_private())
	if _waiting != null:
		await send(api, lobby, is_host)


## Waits until the last press has reached the backend (Start goes after it).
func flush(api: TogetherApi, lobby: Dictionary, is_host: bool) -> void:
	send(api, lobby, is_host)
	while _sending:
		await _tree.process_frame


func _on_toggled(on: bool) -> void:
	_show_hint(on)
	if not editable:
		return
	_waiting = on
	pressed.emit()


func _show_hint(private_night: bool) -> void:
	row.hint = HINT_ON if private_night else HINT_OFF
