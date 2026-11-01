class_name ZombieMarkers
extends Node3D
## Stand-in zombies for a build without the zombie models: one coloured capsule per zombie in the
## snapshot, the colour saying what it is doing. `NightView` uses it until the character assets
## (#90) put the models in, then `ZombieHorde` takes over with the same snapshots.

const HEIGHT := 1.7
const RADIUS := 0.3
const MODE_COLOURS := {
	ZombieBody.Mode.EMERGING: Color(0.35, 0.4, 0.3),
	ZombieBody.Mode.CHASE: Color(0.45, 0.62, 0.35),
	ZombieBody.Mode.ATTACK: Color(0.85, 0.3, 0.25),
	ZombieBody.Mode.STAGGER: Color(0.9, 0.8, 0.35),
	ZombieBody.Mode.DYING: Color(0.25, 0.25, 0.25),
}

var last_snapshot_bytes := 0

var _marks: Dictionary[int, MeshInstance3D] = {}
var _mesh := CapsuleMesh.new()


func _init() -> void:
	_mesh.radius = RADIUS
	_mesh.height = HEIGHT


func view_count() -> int:
	return _marks.size()


func apply_snapshot(bytes: PackedByteArray, _delta: float) -> void:
	last_snapshot_bytes = bytes.size()
	var seen: Dictionary[int, bool] = {}
	for entry in ZombieCodec.decode(bytes):
		var zombie_id: int = entry["id"]
		seen[zombie_id] = true
		if not _marks.has(zombie_id):
			_add(zombie_id)
		var mark := _marks[zombie_id]
		mark.position = entry["position"] + Vector3(0.0, HEIGHT * 0.5, 0.0)
		mark.rotation.y = entry["yaw"]
		(mark.material_override as StandardMaterial3D).albedo_color = MODE_COLOURS.get(
			entry["mode"], Color.WHITE
		)
	for zombie_id in _marks.keys():
		if not seen.has(zombie_id):
			_marks[zombie_id].queue_free()
			_marks.erase(zombie_id)


func _add(zombie_id: int) -> void:
	var mark := MeshInstance3D.new()
	mark.mesh = _mesh
	mark.material_override = StandardMaterial3D.new()
	add_child(mark)
	_marks[zombie_id] = mark
