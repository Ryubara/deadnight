extends Node
## Scripted tour of the shoulder camera in the test room, for before and after captures from the
## same spots (not a test). Real input actions on a timeline of physics seconds, so the same
## script gives the same shots with any camera:
##
##     godot --path game res://tests/captures/shoulder_camera_tour.tscn \
##         --write-movie <abs>/tour.png --fixed-fps 10 --quit-after 190
## Prints SHOT <name> <frame> as each shot starts (frame numbers at 10 fps).

const TICKS_PER_SECOND := 60.0
const MOVIE_FPS := 10.0

## [seconds, kind, argument]: `shot` names the start of a shot; `tp` puts the player at a Vector3
## facing `yaw` degrees; `press` and `release` hold an input action; `end` quits.
const TIMELINE := [
	[0.0, "tp", [Vector3(0.0, 0.05, 12.0), 0.0]],
	[0.0, "shot", "stand"],
	[1.2, "shot", "run"],
	[1.2, "press", "move_forward"],
	[2.6, "release", "move_forward"],
	[3.0, "shot", "sprint"],
	[3.0, "press", "move_forward"],
	[3.0, "press", "sprint"],
	[4.8, "release", "sprint"],
	[4.8, "release", "move_forward"],
	[5.8, "shot", "aim"],
	[5.8, "press", "aim"],
	[7.4, "shot", "aim_release"],
	[7.4, "release", "aim"],
	[8.8, "shot", "swap"],
	[8.8, "press", "swap_shoulder"],
	[8.9, "release", "swap_shoulder"],
	[10.4, "press", "swap_shoulder"],
	[10.5, "release", "swap_shoulder"],
	[11.8, "tp", [Vector3(0.0, 0.05, 19.4), 0.0]],
	[11.8, "shot", "back_wall"],
	[13.2, "tp", [Vector3(14.4, 0.05, 0.0), 0.0]],
	[13.2, "shot", "side_wall_shoulder_side"],
	[14.6, "press", "aim"],
	[14.6, "shot", "side_wall_aim"],
	[16.2, "release", "aim"],
	[16.2, "tp", [Vector3(-14.4, 0.05, 0.0), 0.0]],
	[16.2, "shot", "side_wall_far_side"],
	[17.6, "end", ""],
]
## [start seconds, end seconds, mouse pixels per second]: a quick look to the left and back.
const LOOKS := [[1.6, 2.4, Vector2(-500.0, 0.0)]]

var _ticks := 0
var _next := 0
var _player: Player


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false


func _physics_process(delta: float) -> void:
	var now := _ticks / TICKS_PER_SECOND
	_ticks += 1
	while _next < TIMELINE.size() and TIMELINE[_next][0] <= now:
		var entry: Array = TIMELINE[_next]
		_next += 1
		_run(entry[1], entry[2])
	for look: Array in LOOKS:
		if now >= look[0] and now < look[1]:
			_player.camera_rig.look_mouse((look[2] as Vector2) * delta)


func _run(kind: String, argument: Variant) -> void:
	match kind:
		"tp":
			_player.teleport(argument[0])
			_player.camera_rig.yaw = deg_to_rad(argument[1])
			_player.camera_rig.pitch = 0.0
		"shot":
			print("SHOT %s %d" % [argument, roundi(_ticks / TICKS_PER_SECOND * MOVIE_FPS)])
		"press":
			Input.action_press(argument)
		"release":
			Input.action_release(argument)
		"end":
			get_tree().quit()
