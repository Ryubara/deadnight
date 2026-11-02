class_name SlopeWorld
extends RefCounted
## A flat floor with a ramp on it, and a player to drive with commands (`Player.tick`), for the
## tests that replay a run: the ramp's low end meets the floor at x = 0 and it climbs toward +x.

const TICK := 1.0 / 60.0


## Builds the floor, the ramp and a player in `host`, and waits for the physics server to know
## them. The player's own processing is off; the test calls `tick`.
static func build(host: Node, slope_degrees: float = 20.0) -> Player:
	_add_box(host, Vector3(80, 1, 80), Vector3(0, -0.5, 0), 0.0)
	_add_box(host, Vector3(20, 1, 20), Vector3(10, 0, 0), slope_degrees)
	var player: Player = load("res://gameplay/player/player.tscn").instantiate()
	player.local_input = false
	player.capture_mouse = false
	host.add_child(player)
	player.set_physics_process(false)
	player.get_node("AnimationTree").set_process(false)
	player.camera_rig.set_process(false)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	player.teleport(Vector3(2, 0.05, 0))
	return player


static func _add_box(host: Node, size: Vector3, at: Vector3, tilt_degrees: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	body.rotation.z = deg_to_rad(tilt_degrees)
	host.add_child(body)
