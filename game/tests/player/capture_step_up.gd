extends Node
## The player runs at two ledges in the test room, filmed from the player's own camera (not a test):
##
##   godot --path game --write-movie <dir>/step_up.png --fixed-fps 10 \
##     res://tests/player/capture_step_up.tscn -- after
##   godot --path game --write-movie <dir>/step_up.png --fixed-fps 10 \
##     res://tests/player/capture_step_up.tscn -- before
##
## The first ledge is lower than the step height (climbed in "after"), the second taller (a wall:
## the player stops at it). "before" turns stepping off (`step_height = 0`) to show how it was.
## The player is fed commands, never real input. Prints `STEPUP t=... y=... z=... step=...`.

const LOW_LEDGE := 0.28
const TALL_LEDGE := 0.55
const FACE_Z := 4.0
const SECOND_FACE_Z := -1.0
const RUN_SECONDS := 4.6

var _player: Player
var _ticks := 0


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	if "before" in OS.get_cmdline_user_args():
		_player.tuning = _player.tuning.duplicate()
		_player.tuning.step_height = 0.0
	_ledge(room, LOW_LEDGE, FACE_Z, 3.0, Color(0.9, 0.55, 0.15))
	_ledge(room, TALL_LEDGE, SECOND_FACE_Z, 2.0, Color(0.15, 0.6, 0.85))
	_player.teleport(Vector3(4.0, 0.05, 11.0))
	_player.camera_rig.yaw = 0.0
	_player.camera_rig.snap_to(_player.global_position)


func _ledge(room: Node, height: float, face_z: float, depth: float, color: Color) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, height, depth)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	room.add_child(body)
	body.global_position = Vector3(4.0, height * 0.5, face_z - depth * 0.5)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var seconds := _ticks / 60.0
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, -1.0) if seconds > 0.4 else Vector2.ZERO
	_player.submit_command(command)
	if _ticks % 6 == 0:
		print(
			(
				"STEPUP t=%.1f y=%.3f z=%.2f step_lag=%.3f"
				% [seconds, _player.state.position.y, _player.state.position.z, _player.step_lag()]
			)
		)
	if seconds >= RUN_SECONDS:
		get_tree().quit()
