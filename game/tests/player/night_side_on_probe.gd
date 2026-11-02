extends Node
## The side-on measure (`side_on_probe.gd`) in the real night instead of the test room: the lot,
## the server, the loopback link and the HUD's screen, the soldier driven by held keys. Prints
## `WANDER <px> MOVED <share> FRAMES <n> TICKS <n>`: how far the chest wandered on the screen over
## 60 ticks of steady strafing, and the share of frames in which the chest was drawn somewhere new.
##
##     godot --headless --path game --fixed-fps 144 res://tests/player/night_side_on_probe.tscn \
##         -- --mode=shipped
##
## `--mode=shipped` is the night as the game builds it; `--mode=inherit` leaves its interpolation
## setting to the screen above it (a Control, which is not interpolated).

const SETTLE_TICKS := 100
const WINDOW_TICKS := 60
const GIVE_UP_FRAMES := 6000

var _night: Night
var _player: Player
var _model: Node3D
var _camera: Camera3D
var _frames := 0
var _ticks := 0
var _xs := PackedFloat64Array()
var _moved := 0
var _last_chest := Vector3.INF
var _started := false
var _mode := "shipped"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
	process_priority = 1000
	# The night is a child of a screen, which is a Control, as in the game (`NightScreen`).
	var screen := Control.new()
	add_child(screen)
	_night = Night.new()
	if _mode == "inherit":
		# The fault of issues #344 and #353: the night leaves the setting to the screen above it.
		_night.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	screen.add_child(_night)
	await _night.start(Night.Mode.HUMAN)
	_player = _night.player()
	_player.capture_mouse = false
	_model = _player.get_node(^"Model") as Node3D
	_camera = _player.camera_rig.camera()
	Input.action_press(&"move_right")
	_started = true


func _physics_process(_delta: float) -> void:
	if _started:
		_ticks += 1


func _process(_delta: float) -> void:
	if not _started:
		return
	_frames += 1
	if _ticks >= SETTLE_TICKS:
		var chest := _model.get_global_transform_interpolated() * Vector3(0.0, 1.0, 0.0)
		_xs.append(_camera.unproject_position(chest).x)
		if not chest.is_equal_approx(_last_chest):
			_moved += 1
		_last_chest = chest
	if _ticks >= SETTLE_TICKS + WINDOW_TICKS or _frames >= GIVE_UP_FRAMES:
		var wander := FrameJudder.peak_to_peak(_xs) if not _xs.is_empty() else -1.0
		var unevenness := FrameJudder.rms(FrameJudder.second_differences(_xs))
		print(
			(
				"WANDER %.4f UNEVEN %.4f MOVED %.3f FRAMES %d TICKS %d"
				% [
					wander,
					unevenness,
					float(_moved) / maxf(1.0, _xs.size()),
					_xs.size(),
					_ticks - SETTLE_TICKS
				]
			)
		)
		Input.action_release(&"move_right")
		get_tree().quit()
