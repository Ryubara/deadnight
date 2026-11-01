extends Node
## Scripted play-through of the test room for Movie Maker captures (not a test).
## godot --path game --write-movie <dir>/frame.png --fixed-fps 10 --quit-after <frames>
##   res://tests/player/capture_player.tscn
## The script presses real input actions on a timeline measured in seconds of physics time.

const TICKS_PER_SECOND := 60.0

# [seconds, action, pressed]
const TIMELINE := [
	[0.8, "move_forward", true],
	[2.3, "sprint", true],
	[3.8, "sprint", false],
	[3.8, "move_forward", false],
	[4.4, "move_forward", true],
	[4.8, "jump", true],
	[4.9, "jump", false],
	[5.8, "move_forward", false],
	[6.4, "aim", true],
	[8.4, "aim", false],
	[9.0, "swap_shoulder", true],
	[9.1, "swap_shoulder", false],
	[10.6, "swap_shoulder", true],
	[10.7, "swap_shoulder", false],
	[12.0, "end", true],
]
# [start seconds, end seconds, mouse pixels per second]
const LOOKS := [
	[6.9, 7.9, Vector2(220.0, 0.0)],
]

var _ticks := 0
var _next := 0
var _player: Player


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false


func _physics_process(delta: float) -> void:
	_ticks += 1
	var now := _ticks / TICKS_PER_SECOND
	while _next < TIMELINE.size() and TIMELINE[_next][0] <= now:
		var entry: Array = TIMELINE[_next]
		_next += 1
		if entry[1] == "end":
			get_tree().quit()
			return
		if entry[2]:
			Input.action_press(entry[1])
		else:
			Input.action_release(entry[1])
	for look: Array in LOOKS:
		if now >= look[0] and now < look[1]:
			_player.camera_rig.look_mouse((look[2] as Vector2) * delta)
