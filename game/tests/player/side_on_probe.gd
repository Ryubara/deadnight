extends Node
## One run of the side-on smoothness measure, in a process of its own, at a frame rate the caller
## fixes with `--fixed-fps` (docs/research/physics-interpolation.md). A test cannot do this in its
## own process: the engine's blend fraction and the frame lengths come from the real clock, and a
## camera that follows by a spring lags the body by half a frame, so a loaded machine's uneven
## frames move the soldier on the screen by pixels that have nothing to do with the blend. With
## `--fixed-fps N` every frame is exactly 1/N s long and the frames fall over the ticks the same way
## on every machine.
##
##     godot --headless --path game --fixed-fps 144 res://tests/player/side_on_probe.tscn \
##         -- --mode=blended
##
## Prints one line, `WANDER <pixels> FRAMES <n> TICKS <n>`: how far the soldier's chest wandered on
## the screen over a stretch of steady strafing, as the renderer draws it (a 1920x1080 view).
## `--mode`:
##   blended    the shipped setup: the engine blends the body, the rig blends itself.
##   body-still the engine's physics interpolation off for the whole scene (the body is drawn at its
##              last tick, the rig still blends itself): the bug of issue #344.
##   rig-engine the rig left to the engine's blend on top of its own.

const ROOM := "res://world/test_room.tscn"
const START := Vector3(-13.0, 0.05, 10.0)
## Ticks of strafing before the soldier and the camera are at their steady pace.
const SETTLE_TICKS := 84
## Ticks measured.
const WINDOW_TICKS := 60
## Frames after which the run gives up, whatever the clock does (a hung child must end).
const GIVE_UP_FRAMES := 4000

var _mode := "blended"
var _player: Player
var _model: Node3D
var _camera: Camera3D
var _ticks := 0
var _frames := 0
var _samples := PackedFloat64Array()


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
	# After the camera rig (priority 0), so the camera is where this frame draws it.
	process_priority = 1000
	var room: Node = load(ROOM).instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	if _mode == "body-still":
		get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	elif _mode == "rig-engine":
		_player.camera_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_player.teleport(START)
	_model = _player.get_node("Model") as Node3D
	_camera = _player.camera_rig.camera()


func _physics_process(_delta: float) -> void:
	var command := PlayerCommand.new()
	command.move = Vector2(1.0, 0.0)
	_player.submit_command(command)
	_ticks += 1


func _process(_delta: float) -> void:
	_frames += 1
	if _ticks >= SETTLE_TICKS:
		var chest := _model.get_global_transform_interpolated() * Vector3(0.0, 1.0, 0.0)
		_samples.append(_camera.unproject_position(chest).x)
	if _ticks >= SETTLE_TICKS + WINDOW_TICKS or _frames >= GIVE_UP_FRAMES:
		var wander := FrameJudder.peak_to_peak(_samples) if not _samples.is_empty() else -1.0
		print("WANDER %.4f FRAMES %d TICKS %d" % [wander, _samples.size(), _ticks - SETTLE_TICKS])
		get_tree().quit()
