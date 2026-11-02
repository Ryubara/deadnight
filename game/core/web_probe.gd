class_name WebProbe
extends Node
## On the web, publishes what the game is doing as `window.deadnight`, so a browser test (the CI
## smoke run, `tools/web_smoke/`) can wait for the main menu and a running night instead of
## guessing from pixels. Does nothing elsewhere. It only reads; no game code depends on it.

## How often the object is refreshed, in seconds (a JS property write per field is not free).
const PERIOD := 0.25

var _object: JavaScriptObject
var _since := 0.0


## Writes `label` into `window.deadnight_marks` with the page's clock, so a browser run can line the
## frames and the GL programs it recorded up with what the game was doing (the loading steps).
## Does nothing outside a browser.
static func mark(label: String) -> void:
	if not OS.has_feature("web"):
		return
	var push := "(window.deadnight_marks = window.deadnight_marks || []).push([%s, performance.now()])"
	JavaScriptBridge.eval(push % JSON.stringify(label))


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	_object = JavaScriptBridge.create_object("Object")
	JavaScriptBridge.get_interface("window").deadnight = _object
	add_child(JudderProbe.new())
	add_child(FlashWebProbe.new())
	add_child(ViewWebProbe.new())


func _process(delta: float) -> void:
	_since += delta
	if _since < PERIOD:
		return
	_since = 0.0
	var data := snapshot(UIRouter.top())
	for key in data:
		_object[key] = data[key]


## What the top screen shows: its scene name, and for a night the round, the zombies still to
## kill, the zombies alive on the lot, the players in the frame, the player's own id and (online)
## the round trip, whether the menu is open, the mouse mode, the camera's yaw (radians) and whether
## the player's body is drawn between physics ticks. Plain values only, so a page can read them.
static func snapshot(top: Control) -> Dictionary:
	var data := {
		"screen": "none",
		"night": false,
		"running": false,
		"paused": false,
		"mouse_mode": 0,
		"over": false,
		"round": 0,
		"remaining": 0,
		"alive": 0,
		"players": 0,
		"player_id": 0,
		"rtt_ms": -1.0,
		"yaw": 0.0,
		"interpolated": false,
		"room_code": "",
		"room_status": "",
		"naming": false,
		"touch": false,
		"reticle": false,
		"tab": "",
		"stage": "",
		"gamepad": "",
		"activity_room": "",
		"activity_code": "",
		"controller_hint": false
	}
	if top == null:
		return data
	data["screen"] = top.scene_file_path.get_file().get_basename()
	data["gamepad"] = GamepadProbe.note(GamepadProbe.read())
	var room := ActivityRoom.current
	if room != null:
		data["activity_room"] = ActivityRoom.State.keys()[room.state].to_lower()
		data["activity_code"] = str(room.lobby.get("code", ""))
	var tree := top.get_tree()
	var hint: ControllerHint = (
		tree.root.find_child("ControllerHint", true, false) as ControllerHint
		if tree != null
		else null
	)
	data["controller_hint"] = hint != null and hint.label.is_visible_in_tree()
	var menu := top as MainMenu
	if menu != null and menu.shell != null:
		data["tab"] = MenuTab.label(menu.shell.tab)
		data["stage"] = ["live", "half", "still"][menu.shell.view.level]
	var together := top as TogetherScreen
	if together != null:
		# The invite of the night just made and what the screen says (a browser test reads both).
		data["room_code"] = (
			together.invite_code.text if together.invite_code.is_visible_in_tree() else ""
		)
		data["room_status"] = together.status.text
		# The name prompt is up (a browser test types a name into it).
		data["naming"] = together.name_field.is_visible_in_tree()
	var night_screen := top as NightScreen
	if night_screen == null or night_screen.night == null or night_screen.night.state == null:
		return data
	var state := night_screen.night.state
	data["night"] = true
	data["running"] = night_screen.night.running
	# The menu is open, and what the engine says the mouse is (2 is captured: a browser's pointer
	# lock), so a browser test sees the first Esc open the menu.
	data["paused"] = night_screen.night.is_paused()
	data["mouse_mode"] = Input.mouse_mode
	var player: Player = night_screen.night.player() if night_screen.night.server != null else null
	if player != null:
		data["yaw"] = player.camera_rig.yaw  # so a browser test can see the mouse turn the view
		# So a browser test can see the body is drawn between ticks (a screen can switch that off).
		data["interpolated"] = player.is_physics_interpolated_and_enabled()
	data["over"] = state.over
	data["touch"] = night_screen.touch_active()
	data["reticle"] = night_screen.reticle_shown()
	if state.has_frame():
		data["round"] = state.round_number()
		data["remaining"] = state.frame.get("remaining", 0)
		data["alive"] = state.zombies.size()
		data["players"] = (state.frame.get("players", {}) as Dictionary).size()
	data["player_id"] = state.player_id
	var link := night_screen.night.link as WebSocketLink
	if link != null:
		data["rtt_ms"] = link.rtt_ms
	return data
