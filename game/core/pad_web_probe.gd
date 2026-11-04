class_name PadWebProbe
extends Node
## A browser test's view of the gamepad as the engine reads it (`tools/web_smoke/pad_pause.py`),
## which does not depend on which node eats an event: it reads the `Input` singleton, the way the
## game's own controls do. On the web only, and only while the page asks for the probes
## (`WebProbe.asked`); it only reads.
##
## `window.deadnight.pad_count` joypads the engine lists; `pad_start_presses` how many times a
## joypad's Start went down; `pause_presses` how many times the `pause` action went down (a key or
## a pad). A Start that raises the first and not the second never got into the input map; one that
## raises both and does not pause the night was eaten by a node on the way.

var _object: JavaScriptObject
var _pads: PackedInt32Array = PackedInt32Array()
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
	# The pads are listed when one comes or goes, not read again every frame (a new Array and a
	# property read over the bridge each time, in every player's page before #935).
	Input.joy_connection_changed.connect(_on_pads_changed)
	_on_pads_changed(0, true)
	set_process(true)


## A pad was connected or removed: the list and the page's count.
func _on_pads_changed(_device: int, _connected: bool) -> void:
	_pads = PackedInt32Array(Input.get_connected_joypads())
	_object.pad_count = _pads.size()


func _process(_delta: float) -> void:
	# Nothing here allocates or crosses the bridge unless a press happened: the pad ids are cached.
	var down := false
	for device in _pads:
		down = down or Input.is_joy_button_pressed(device, JOY_BUTTON_START)
	if down and not _start_was_down:
		_start_presses += 1
		_object.pad_start_presses = _start_presses
	_start_was_down = down
	if Input.is_action_just_pressed(&"pause"):
		_pause_presses += 1
		_object.pause_presses = _pause_presses
