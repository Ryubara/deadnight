extends Node3D
## What a player sees out of each of the second map's windows, and from the start (#917): for
## every socket in `Windows/` the shoulder camera of a player standing 2.4 m inside it, facing out
## through it, at the night's own light; then the start, from the first player's place, facing the
## way the players spawn and facing the nearest window. Also, from where each window's dead rise,
## the view back at the building (a dead's eye, not a player's: what is outside, and the way
## in). Reads the map's sockets, so it films any layout. Not part of the game; run it windowed:
##
##   gds godot -- --path game res://tests/captures/smallmap_window_views.tscn -- --out=<folder>
##
## Writes one PNG a view into the folder and quits.

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const PLAYER_SCENE := preload("res://gameplay/player/player.tscn")
## How far inside a window the player stands, and the eye of the dead's view.
const BEHIND := 2.4
const ASIDE := 0.7
const DEAD_EYE := 1.6

var _out := "user://smallmap_windows"
var _lot: Node3D
var _camera: Camera3D
var _body: Player


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_lot = (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(_lot)
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = 75.0
	_camera.near = 0.05
	add_child(_camera)
	for _i in 4:
		await get_tree().physics_frame
	var doors := _lot.get_node("Doors") as LotDoors
	for door in doors.get_children():
		doors.open(StringName(door.get_meta(&"shop_id")))
	_body = PLAYER_SCENE.instantiate() as Player
	_body.local_input = false
	_body.capture_mouse = false
	add_child(_body)
	_body.set_physics_process(false)
	_body.set_process(false)
	_camera.make_current()
	for _i in 4:
		await get_tree().physics_frame
	await _windows()
	await _start()
	await _dead_views()
	get_tree().quit()


## Each window boarded, then with its boards torn (what is outside it, unhidden). The player stands
## a little to the left of the window's line, so the window shows past the right shoulder.
func _windows() -> void:
	for torn: bool in [false, true]:
		for socket: Node3D in _lot.get_node("Windows").get_children():
			var boards := socket.get_node("Boards") as Barricade
			boards.set_boards(0 if torn else boards.capacity(), false)
			var inward := socket.global_basis.z
			inward.y = 0.0
			inward = inward.normalized()
			var left := Vector3(-inward.z, 0.0, inward.x)
			var feet := socket.global_position + inward * BEHIND + left * ASIDE
			var name := "window_%s%s" % [socket.get_meta(&"barricade_id"), "_torn" if torn else ""]
			await _shoulder(name, feet, Vector2(-inward.x, -inward.z))
			boards.set_boards(boards.capacity(), false)


func _start() -> void:
	var first := _lot.get_node("PlayerSpawns").get_child(0) as Node3D
	var ahead := -first.global_basis.z
	await _shoulder("start_spawn_facing", first.global_position, Vector2(ahead.x, ahead.z))
	var nearest: Node3D = null
	for socket: Node3D in _lot.get_node("Windows").get_children():
		if socket.get_meta(&"room") != "start":
			continue
		if (
			nearest == null
			or (
				_flat(socket.global_position, first.global_position)
				< _flat(nearest.global_position, first.global_position)
			)
		):
			nearest = socket
	if nearest != null:
		var to := nearest.global_position - first.global_position
		await _shoulder(
			"start_to_nearest_window", first.global_position, Vector2(to.x, to.z).normalized()
		)


## From each window's spawn, at a dead's eye, looking at the window's middle.
func _dead_views() -> void:
	_body.visible = false
	var sockets := {}
	for socket: Node3D in _lot.get_node("Windows").get_children():
		sockets[socket.get_meta(&"barricade_id")] = socket
	for spawn: Node3D in _lot.get_node("ZombieSpawns").get_children():
		var id: String = spawn.get_meta(&"barricade_id")
		var socket: Node3D = sockets.get(id)
		if socket == null:
			continue
		var eye := spawn.global_position + Vector3.UP * DEAD_EYE
		var target := socket.global_position + Vector3.UP * 1.5
		_camera.global_transform = Transform3D.IDENTITY.translated(eye).looking_at(
			target, Vector3.UP
		)
		await _shot("dead_%s" % id)
	_body.visible = true


func _shoulder(name: String, feet: Vector3, facing: Vector2) -> void:
	var yaw := atan2(-facing.x, -facing.y)
	_body.teleport(feet + Vector3.UP * 0.05)
	var look := PlayerCommand.new()
	look.yaw = yaw
	look.aim = true
	for _i in 40:
		_body.tick(look)
		await get_tree().physics_frame
	_body.reset_physics_interpolation()
	var space := get_world_3d().direct_space_state
	var rig := CameraProbe.rig(space, _body.global_position, yaw, 1.0, -0.05)
	_camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(-0.05, yaw, 0.0)), rig["camera"]
	)
	await _shot(name)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote %s" % path)
