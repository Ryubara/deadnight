extends Node
## The player runs at a low beam, then crouches under it, filmed from the player's own camera (not a
## test):
##
##   godot --path game --write-movie <dir>/crouch.png --fixed-fps 10 \
##     res://tests/player/capture_crouch.tscn
##
## Standing, the player stops at the beam (it is lower than the body). With the crouch held it walks
## under at the crouch speed; the key is let go under the beam (no room: it stays crouched) and the
## body stands up once it is out the other end. The player is fed commands, never real input.
## Prints `CROUCH t=... z=... crouching=... height=...`.

const BEAM_BOTTOM := 1.45
const BEAM_FACE_Z := 7.0
const BEAM_DEPTH := 6.0
const CROUCH_FROM := 1.8
const KEY_UP := 3.4
const END := 6.2

var _player: Player
var _ticks := 0


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	_player = room.get_node("Player") as Player
	_player.capture_mouse = false
	_player.local_input = false
	_add_beam(room)
	_player.teleport(Vector3(4.0, 0.05, 11.0))
	_player.camera_rig.yaw = 0.0
	_player.camera_rig.snap_to(_player.global_position)


func _add_beam(room: Node) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.5, BEAM_DEPTH)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.3, 0.2)
	mesh.material_override = material
	body.add_child(mesh)
	# Two posts so the beam is seen to hold a gap, not float.
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.3, BEAM_BOTTOM, 0.3)
		post.mesh = post_mesh
		post.material_override = material
		post.position = Vector3(side * 4.15, -BEAM_BOTTOM * 0.5 - 0.25, 0.0)
		body.add_child(post)
	room.add_child(body)
	body.global_position = Vector3(4.0, BEAM_BOTTOM + 0.25, BEAM_FACE_Z - BEAM_DEPTH * 0.5)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var seconds := _ticks / 60.0
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, -1.0) if seconds > 0.4 else Vector2.ZERO
	command.crouch = seconds > CROUCH_FROM and seconds < KEY_UP
	_player.submit_command(command)
	if _ticks % 6 == 0:
		print(
			(
				"CROUCH t=%.1f z=%.2f crouching=%s height=%.2f"
				% [
					seconds,
					_player.state.position.z,
					_player.state.crouching,
					(_player.get_node("CollisionShape3D") as CollisionShape3D).shape.height,
				]
			)
		)
	if seconds >= END:
		get_tree().quit()
