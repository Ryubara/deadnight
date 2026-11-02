class_name PadWebProbe
extends Node
## A browser test's view of the gamepad as the engine reads it (`tools/web_smoke/pad_pause.py`),
## which does not depend on which node eats an event: it polls the `Input` singleton, the way the
## game's own controls do. On the web only; it only reads.
##
## `window.deadnight.pad_count` joypads the engine lists; `pad_start_presses` how many times a
## joypad's Start went down; `pause_presses` how many times the `pause` action went down (a key or
## a pad). A Start that raises the first and not the second never got into the input map; one that
## raises both and does not pause the night was eaten by a node on the way.

var _object: JavaScriptObject
var _start_was_down := false
var _start_presses := 0
var _pause_presses := 0


func _ready() -> void:
	set_process(false)
	if not OS.has_feature("web"):
		return
	_object = JavaScriptBridge.get_interface("window").deadnight
	_object.pad_count = 0
	_object.pad_start_presses = 0
	_object.pause_presses = 0
	set_process(true)


func _process(_delta: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.size() != int(_object.pad_count):
		_object.pad_count = pads.size()
	var down := false
	for device in pads:
		down = down or Input.is_joy_button_pressed(device, JOY_BUTTON_START)
	if down and not _start_was_down:
		_start_presses += 1
		_object.pad_start_presses = _start_presses
	_start_was_down = down
	if Input.is_action_just_pressed(&"pause"):
		_pause_presses += 1
		_object.pause_presses = _pause_presses
