extends Node
## Scripted omni-movement run of the test room for Movie Maker captures (not a test).
##
##   godot --path game --write-movie <dir>/shoulder.png --fixed-fps 10 \
##     res://tests/player/capture_omni.tscn -- shoulder
##   godot --path game --write-movie <dir>/overhead.png --fixed-fps 10 \
##     res://tests/player/capture_omni.tscn -- overhead
##
## "shoulder" films the player's own camera; "overhead" looks straight down and leaves a trail of
## dots (green: sprinting, grey: running or walking, orange: aiming) with a bar for where the body
## faces. Both play the same timeline of real input actions, measured in seconds of physics time:
## sprint forward, sideways, backward, a sprint reversal, and a strafe while aiming.
## The player is fed commands (`submit_command`), never real input, so a hand on the mouse or a
## gamepad cannot disturb the run.
## The state is also printed once a tick-tenth as `OMNI t=... speed=... facing=...` for the numbers.

const TICKS_PER_SECOND := 60.0
const OVERHEAD_HEIGHT := 30.0

# [seconds, kind, argument]. Kinds: "press" / "release" (an action), "teleport" (a Vector3),
# "mark" (a label for the log), "end".
const TIMELINE := [
	[0.1, "mark", "forward"],
	[0.1, "teleport", Vector3(0.0, 0.05, 17.0)],
	[0.5, "press", "sprint"],
	[0.5, "press", "move_forward"],
	[1.9, "release", "move_forward"],
	[1.9, "release", "sprint"],
	[2.9, "mark", "sideways"],
	[2.9, "teleport", Vector3(-7.0, 0.05, 12.0)],
	[3.3, "press", "sprint"],
	[3.3, "press", "move_right"],
	[4.7, "release", "move_right"],
	[4.7, "release", "sprint"],
	[5.7, "mark", "backward"],
	[5.7, "teleport", Vector3(9.0, 0.05, -2.0)],
	[6.1, "press", "sprint"],
	[6.1, "press", "move_back"],
	[7.5, "release", "move_back"],
	[7.5, "release", "sprint"],
	[8.5, "mark", "reversal"],
	[8.5, "teleport", Vector3(-12.0, 0.05, 17.0)],
	[8.8, "press", "sprint"],
	[8.8, "press", "move_forward"],
	[9.6, "release", "move_forward"],
	[9.6, "press", "move_back"],
	[10.8, "release", "move_back"],
	[10.8, "release", "sprint"],
	[11.8, "mark", "aim strafe"],
	[11.8, "teleport", Vector3(-7.0, 0.05, 12.0)],
	[12.1, "press", "aim"],
	[12.1, "press", "sprint"],
	[12.1, "press", "move_right"],
	[13.3, "release", "move_right"],
	[13.3, "release", "aim"],
	[13.3, "release", "sprint"],
	[14.2, "end", ""],
]
const COLOR_SPRINT := Color(0.2, 0.9, 0.3)
const COLOR_RUN := Color(0.75, 0.75, 0.75)
const COLOR_AIM := Color(1.0, 0.55, 0.1)

var _ticks := 0
var _next := 0
var _player: Player
var _overhead := false
var _label := ""
var _held := {}
var _trail_root: Node3D
var _dot_mesh: SphereMesh
var _bar_mesh: BoxMesh


func _ready() -> void:
	_overhead = "overhead" in OS.get_cmdline_user_args()
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	if _overhead:
		_build_overhead()


func _build_overhead() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 42.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)
	camera.global_transform = Transform3D(
		Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0.0, OVERHEAD_HEIGHT, 0.0)
	)
	camera.current = true
	_trail_root = Node3D.new()
	add_child(_trail_root)
	_dot_mesh = SphereMesh.new()
	_dot_mesh.radius = 0.24
	_dot_mesh.height = 0.48
	_bar_mesh = BoxMesh.new()
	_bar_mesh.size = Vector3(0.16, 0.06, 1.0)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var now := _ticks / TICKS_PER_SECOND
	while _next < TIMELINE.size() and TIMELINE[_next][0] <= now:
		var entry: Array = TIMELINE[_next]
		_next += 1
		match entry[1]:
			"end":
				get_tree().quit()
				return
			"press":
				_held[entry[2]] = true
			"release":
				_held.erase(entry[2])
			"teleport":
				_teleport(entry[2])
			"mark":
				_label = entry[2]
	_player.submit_command(_command())
	if _ticks % 6 == 0:
		_log(now)
		if _overhead:
			_drop_trail()


func _command() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(
		float(_held.has("move_right")) - float(_held.has("move_left")),
		float(_held.has("move_back")) - float(_held.has("move_forward"))
	)
	command.sprint = _held.has("sprint")
	command.aim = _held.has("aim")
	return command


func _teleport(position: Vector3) -> void:
	_player.teleport(position)
	_player.state.facing = 0.0
	_player.rotation.y = 0.0
	_player.camera_rig.yaw = 0.0
	_player.camera_rig.snap_to(position)


func _log(now: float) -> void:
	var state := _player.state
	print(
		(
			"OMNI t=%.1f seg=%s x=%.2f z=%.2f speed=%.2f facing=%.0f sprint=%s aim=%s"
			% [
				now,
				_label,
				state.position.x,
				state.position.z,
				state.ground_speed(),
				rad_to_deg(state.facing),
				state.sprinting,
				state.aiming,
			]
		)
	)


func _drop_trail() -> void:
	var state := _player.state
	var color := COLOR_AIM if state.aiming else (COLOR_SPRINT if state.sprinting else COLOR_RUN)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dot := MeshInstance3D.new()
	dot.mesh = _dot_mesh
	dot.material_override = material
	_trail_root.add_child(dot)
	dot.global_position = state.position + Vector3(0.0, 4.0, 0.0)
	var bar := MeshInstance3D.new()
	bar.mesh = _bar_mesh
	bar.material_override = material
	_trail_root.add_child(bar)
	var basis := Basis(Vector3.UP, state.facing)
	bar.global_transform = Transform3D(
		basis, state.position + Vector3(0.0, 4.0, 0.0) + basis * Vector3(0.0, 0.0, -0.55)
	)
