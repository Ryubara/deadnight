class_name WorldView
extends Node3D
## Draws the world for a client: a capsule per player, plus a ring where the server last said
## the local player was (the "ghost": the gap between it and the capsule is what prediction
## hides).

const PALETTE: Array[Color] = [
	Color("e4572e"),
	Color("29b6f6"),
	Color("ffc914"),
	Color("76b041"),
	Color("b86adf"),
	Color("ff8fab"),
]
const SMOOTHING := 25.0
const CM_TO_M := 0.01

var _avatars: Dictionary[int, Node3D] = {}
var _ghost: MeshInstance3D
var _local_id := 0


func _ready() -> void:
	_ghost = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.5
	_ghost.mesh = ring
	_ghost.visible = false
	add_child(_ghost)


## The local capsule follows the predicted position (smoothed to hide the 30 Hz stepping).
func show_local(id: int, pos_cm: Vector2i) -> void:
	_local_id = id
	_place(id, Vector2(pos_cm) * CM_TO_M, true, true)


func show_remote(id: int, pos_cm: Vector2) -> void:
	_place(id, pos_cm * CM_TO_M, false, false)


func show_ghost(pos_cm: Vector2i) -> void:
	_ghost.visible = true
	_ghost.position = Vector3(pos_cm.x * CM_TO_M, 0.05, pos_cm.y * CM_TO_M)


func remove_avatar(id: int) -> void:
	var avatar: Node3D = _avatars.get(id)
	if avatar:
		avatar.queue_free()
		_avatars.erase(id)


func _place(id: int, pos: Vector2, local: bool, smooth: bool) -> void:
	var avatar: Node3D = _avatars.get(id)
	var target := Vector3(pos.x, 0.0, pos.y)
	if avatar == null:
		avatar = _make_avatar(id, local)
		avatar.position = target
	elif smooth:
		avatar.position = avatar.position.lerp(
			target, 1.0 - exp(-SMOOTHING * get_process_delta_time())
		)
	else:
		avatar.position = target


func _make_avatar(id: int, local: bool) -> Node3D:
	var avatar := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	body.mesh = capsule
	body.position.y = 0.8
	var material := StandardMaterial3D.new()
	material.albedo_color = PALETTE[id % PALETTE.size()]
	body.material_override = material
	avatar.add_child(body)
	var label := Label3D.new()
	label.text = "YOU (P%d)" % id if local else "P%d" % id
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.014
	label.font_size = 48
	label.outline_size = 12
	label.position.y = 2.1
	avatar.add_child(label)
	add_child(avatar)
	_avatars[id] = avatar
	return avatar
