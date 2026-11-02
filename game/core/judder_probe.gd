class_name JudderProbe
extends Node
## On the web, while a page asks for it (`window.deadnight.record = true`), writes one row per
## drawn frame into `window.deadnight.frames` (a flat array): where the soldier's chest is on the
## screen as the renderer draws it, and the clock that frame fell on. A browser test
## (`tools/web_smoke/judder.py`) turns the rows into the soldier's unevenness on the screen. It
## only reads; no game code depends on it, and nothing is recorded unless the page asks.
## Why and what the numbers were: docs/research/physics-interpolation.md.

## Numbers per frame, in this order: milliseconds since start, screen x, screen y (pixels of the
## canvas), the physics frame, the engine's blend fraction, the frame's delta in milliseconds,
## the chest's interpolated world x and z.
const ROW := 8

var _object: JavaScriptObject
var _frames: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	# After the camera rig (priority 0): the camera is where this frame draws it.
	process_priority = 1000
	_object = JavaScriptBridge.get_interface("window").deadnight
	_frames = JavaScriptBridge.create_object("Array")
	_object.frames = _frames
	_object.record = false
	_object.frameRow = ROW


func _process(delta: float) -> void:
	if not _object.record:
		return
	var screen := UIRouter.top() as NightScreen
	if screen == null or screen.night == null or screen.night.server == null:
		return
	var player := screen.night.player()
	if player == null:
		return
	var model := player.get_node(^"Model") as Node3D
	var chest := model.get_global_transform_interpolated() * Vector3(0.0, 1.0, 0.0)
	var at := player.camera_rig.camera().unproject_position(chest)
	_frames.push(
		Time.get_ticks_usec() / 1000.0,
		at.x,
		at.y,
		Engine.get_physics_frames(),
		Engine.get_physics_interpolation_fraction(),
		delta * 1000.0,
		chest.x,
		chest.z
	)
