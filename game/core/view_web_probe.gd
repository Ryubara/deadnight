class_name ViewWebProbe
extends Node
## On the web, while a page asks for it (`window.deadnight.viewRecord = true`), writes one row
## per drawn frame into `window.deadnight.viewRows` (a flat array): the clock, the camera's field
## of view and the aim weight of the view, and whether the body holds the aim pose. A browser test
## (`tools/web_smoke/hip_fire.py`) reads them to see that firing from the hip leaves the view
## alone and that letting go of the aim lets the zoom go (#464). It only reads; no game code
## depends on it, and nothing is recorded unless the page asks.

## Numbers per frame, in this order: milliseconds since start, field of view in degrees, the view's
## aim weight (0 to 1), 1 while the body holds the aim pose (button or a recent shot from the hip),
## the lens's distance from the head in metres, 1 on the ticks the server lets a shot leave
## (`shot_ready`: 1 when any tick since the last drawn frame let a shot leave, because a tap's
## one tick falls between two frames of a slow browser), and how far the body is from facing the
## view in radians (#477).
const ROW := 7

var _object: JavaScriptObject
var _rows: JavaScriptObject
var _shot_ready_since_frame := false


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		set_physics_process(false)
		return
	# After the camera rig (priority 0): the camera is where this frame draws it.
	process_priority = 1000
	_object = JavaScriptBridge.get_interface("window").deadnight
	_rows = JavaScriptBridge.create_object("Array")
	_object.viewRows = _rows
	_object.viewRecord = false
	_object.viewRow = ROW


func _physics_process(_delta: float) -> void:
	# After the night's tick (priority 1000): this tick's answer is in the state.
	if not _object.viewRecord:
		_shot_ready_since_frame = false
		return
	var screen := UIRouter.top() as NightScreen
	if screen == null or screen.night == null or screen.night.server == null:
		return
	var player := screen.night.player()
	if player != null and player.state.shot_ready:
		_shot_ready_since_frame = true


func _process(_delta: float) -> void:
	if not _object.viewRecord:
		return
	var screen := UIRouter.top() as NightScreen
	if screen == null or screen.night == null or screen.night.server == null:
		return
	var player := screen.night.player()
	if player == null:
		return
	var rig := player.camera_rig
	_rows.push(
		Time.get_ticks_usec() / 1000.0,
		rig.camera().fov,
		rig.aim_amount(),
		1.0 if player.state.holds_aim(player.tuning.hip_fire_hold) else 0.0,
		rig.lens_distance(),
		1.0 if _shot_ready_since_frame else 0.0,
		player.state.view_error
	)
	_shot_ready_since_frame = false
