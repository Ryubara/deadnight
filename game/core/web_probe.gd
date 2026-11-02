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


func _process(delta: float) -> void:
	_since += delta
	if _since < PERIOD:
		return
	_since = 0.0
	var data := snapshot(UIRouter.top())
	for key in data:
		_object[key] = data[key]


## What the top screen shows: its scene name, and for a night the round, the zombies still to
## kill, the zombies alive on the lot and the camera's yaw (radians). Plain values only, so a page
## can read them.
static func snapshot(top: Control) -> Dictionary:
	var data := {
		"screen": "none",
		"night": false,
		"running": false,
		"over": false,
		"round": 0,
		"remaining": 0,
		"alive": 0,
		"yaw": 0.0,
		"touch": false
	}
	if top == null:
		return data
	data["screen"] = top.scene_file_path.get_file().get_basename()
	var night_screen := top as NightScreen
	if night_screen == null or night_screen.night == null or night_screen.night.state == null:
		return data
	var state := night_screen.night.state
	data["night"] = true
	data["running"] = night_screen.night.running
	var player: Player = night_screen.night.player() if night_screen.night.server != null else null
	if player != null:
		data["yaw"] = player.camera_rig.yaw  # so a browser test can see the mouse turn the view
	data["over"] = state.over
	data["touch"] = night_screen.touch_active()
	if state.has_frame():
		data["round"] = state.round_number()
		data["remaining"] = state.frame.get("remaining", 0)
		data["alive"] = state.zombies.size()
	return data
