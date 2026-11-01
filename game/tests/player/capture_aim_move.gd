extends Node
## Scripted capture of moving while aiming (#74), from the player's own shoulder camera (not a
## test): aim held, then forward, a strafe right, a strafe left, a backpedal, and a diagonal back
## and to the left. Real input actions on a timeline of physics seconds; prints MOVE <name> <frame>
## at each start so frames can be matched to moves. Aiming zooms the shoulder camera in to the
## chest, so `-- teammate` films from a camera trailing the player at 4.5 m instead, where the legs
## show (how another player sees him).
## godot --path game --write-movie <abs>/frame.png --fixed-fps 30 --quit-after <frames>
##   res://tests/player/capture_aim_move.tscn [-- teammate]

const TICKS_PER_SECOND := 60.0
## [seconds, name, actions held]
const MOVES := [
	[0.0, "stand", []],
	[0.8, "forward", ["move_forward"]],
	[2.6, "strafe_right", ["move_right"]],
	[4.4, "strafe_left", ["move_left"]],
	[6.2, "back", ["move_back"]],
	[8.0, "back_left", ["move_back", "move_left"]],
	[9.8, "end", []],
]

var _ticks := 0
var _next := 0
var _held: Array = []
var _player: Player
var _teammate: Camera3D


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	Input.action_press("aim")
	if "teammate" in OS.get_cmdline_user_args():
		_teammate = Camera3D.new()
		_teammate.fov = 36.0
		add_child(_teammate)


func _process(_delta: float) -> void:
	if _teammate == null:
		return
	# Behind and to the right of where the player faces, a little above his head.
	var at := _player.global_position
	var facing := _player.state.facing
	var behind := Vector3(sin(facing), 0.0, cos(facing))
	var right := Vector3(cos(facing), 0.0, -sin(facing))
	_teammate.global_position = at + behind * 3.8 + right * 2.4 + Vector3.UP * 1.9
	_teammate.look_at(at + Vector3.UP * 0.8)
	_teammate.make_current()


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var now := _ticks / TICKS_PER_SECOND
	while _next < MOVES.size() and MOVES[_next][0] <= now:
		var move: Array = MOVES[_next]
		_next += 1
		for action: String in _held:
			Input.action_release(action)
		if move[1] == "end":
			Input.action_release("aim")
			get_tree().quit()
			return
		_held = move[2]
		for action: String in _held:
			Input.action_press(action)
		print("MOVE %s %d" % [move[1], Engine.get_frames_drawn()])
