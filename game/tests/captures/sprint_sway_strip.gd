extends Node
## A walk into a sprint and a stop in the test room, for before and after captures of the sprint
## sway (not a test). Real input actions on a timeline of physics seconds, so the same script gives
## the same shots whatever the camera does:
##
##     godot --path game res://tests/captures/sprint_sway_strip.tscn \
##         --write-movie <abs>/s.png --fixed-fps 30 --quit-after 130
## Prints one `TRACE` line per physics tick: seconds, ground speed, sprinting, and the turn of the
## lens against the aim in degrees (pitch, yaw, roll). Reads only what the rig has always had
## (`camera()` and `aim_transform()`), so it runs on a build without the sway too.

const TICKS_PER_SECOND := 60.0

## [seconds, kind, argument]: `tp` puts the player at a Vector3 facing yaw degrees; `press` and
## `release` hold an input action; `end` quits.
const TIMELINE := [
	[0.0, "tp", [Vector3(0.0, 0.05, 17.0), 0.0]],
	[0.5, "press", "move_forward"],
	[1.1, "press", "sprint"],
	[3.1, "release", "sprint"],
	[3.1, "release", "move_forward"],
	[4.2, "end", ""],
]

var _ticks := 0
var _next := 0
var _player: Player


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false


func _physics_process(_delta: float) -> void:
	var now := _ticks / TICKS_PER_SECOND
	_ticks += 1
	while _next < TIMELINE.size() and TIMELINE[_next][0] <= now:
		var entry: Array = TIMELINE[_next]
		_next += 1
		_run(entry[1], entry[2])
	var rig := _player.camera_rig
	var turn := rig.aim_transform().basis.inverse() * rig.camera().global_transform.basis
	var euler := turn.get_euler() * (180.0 / PI)
	print(
		(
			"TRACE %.4f %.3f %d %.4f %.4f %.4f"
			% [now, _player.ground_speed(), int(_player.is_sprinting()), euler.x, euler.y, euler.z]
		)
	)


func _run(kind: String, argument: Variant) -> void:
	match kind:
		"tp":
			_player.teleport(argument[0])
			_player.camera_rig.yaw = deg_to_rad(argument[1])
			_player.camera_rig.pitch = 0.0
		"press":
			Input.action_press(argument)
		"release":
			Input.action_release(argument)
		"end":
			get_tree().quit()
