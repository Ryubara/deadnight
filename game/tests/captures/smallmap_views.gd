extends Node3D
## Captures of the second map's greybox (#631): two plans from above (the ground floor, and the
## upper floor with the ring's lap drawn in yellow) and views from the shoulder camera in each room,
## on each stair and through the links, all links open. Not part of the game; run it windowed:
##
##   gds godot -- --path game res://tests/captures/smallmap_views.tscn -- --out=<folder>
##
## Writes one PNG a view into the folder and quits.

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const PLAYER_SCENE := preload("res://gameplay/player/player.tscn")
## Shoulder views: name, feet, the direction faced (x, z).
const VIEWS := [
	["start_counter", Vector3(8.0, 0.0, 11.5), Vector2(0.0, -1.0)],
	["start_windows", Vector3(9.0, 0.0, 9.5), Vector2(0.8, 0.6)],
	["side_racks", Vector3(14.5, 0.0, -2.0), Vector2(-1.0, -0.05)],
	["stair_a_up", Vector3(1.2, 0.0, 1.0), Vector2(1.0, 0.0)],
	["stair_b_down", Vector3(3.4, 3.4, -6.8), Vector2(-1.0, 0.0)],
	["door_side", Vector3(14.0, 0.0, 2.5), Vector2(0.0, -1.0)],
	["upstairs_a", Vector3(3.0, 3.4, 3.4), Vector2(1.0, -0.1)],
	["upstairs_b", Vector3(14.5, 3.4, -4.0), Vector2(-1.0, 0.0)],
	["opening", Vector3(12.0, 3.4, 2.6), Vector2(0.0, -1.0)],
]

var _out := "user://smallmap"
var _lot: Node3D
var _camera: Camera3D


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_lot = (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(_lot)
	_camera = Camera3D.new()
	# Placed by hand between frames: not blended between physics ticks.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.current = true
	for _i in 4:
		await get_tree().physics_frame
	var doors := _lot.get_node("Doors") as LotDoors
	for door in doors.get_children():
		doors.open(StringName(door.get_meta(&"shop_id")))
	for _i in 4:
		await get_tree().physics_frame
	await _plans()
	await _shoulder_views()
	get_tree().quit()


func _plans() -> void:
	var environment := (_lot.get_node("Lighting/WorldEnvironment") as WorldEnvironment).environment
	var ambient := environment.ambient_light_energy
	environment.ambient_light_energy = 2.0
	environment.fog_enabled = false
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 30, 0)
	add_child(sun)
	var nav := SmallMapNavigation.new(_lot, SmallMapNavigation.zombie_mesh())
	await nav.settle(get_tree())
	var lap := _draw_ring(nav)
	nav.free_map()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 27.0
	_camera.look_at_from_position(
		Vector3(5.0, 60.0, 3.0), Vector3(5.0, 0.0, 3.0), Vector3(0, 0, -1)
	)
	# The ground floor: everything above the first ceiling's underside hidden.
	var hidden := _hide_above(3.15)
	lap.visible = false
	await _shot("plan_ground")
	for node in hidden:
		node.visible = true
	_hide_above(6.55)
	lap.visible = true
	await _shot("plan_upper_ring")
	for node in _lot.find_children("*", "Node3D", true, false):
		if node is VisualInstance3D or node is CSGShape3D:
			node.visible = true
	lap.queue_free()
	sun.queue_free()
	environment.ambient_light_energy = ambient
	environment.fog_enabled = true


## Hides every drawn box whose bottom is above `height`; returns them.
func _hide_above(height: float) -> Array[Node3D]:
	var hidden: Array[Node3D] = []
	for node in _lot.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		if box.visible and box.global_position.y - box.size.y * 0.5 > height:
			box.visible = false
			hidden.append(box)
	return hidden


func _draw_ring(nav: SmallMapNavigation) -> MeshInstance3D:
	var markers := _lot.get_node("Measure/Ring").get_children()
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.1)
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for i in markers.size():
		var a := (markers[i] as Node3D).global_position
		var b := (markers[(i + 1) % markers.size()] as Node3D).global_position
		var way := nav.path(a, b)
		for k in range(1, way.size()):
			var p := way[k - 1] + Vector3.UP * 0.3
			var q := way[k] + Vector3.UP * 0.3
			var side := (q - p).cross(Vector3.UP).normalized() * 0.15
			for v in [p - side, p + side, q + side, p - side, q + side, q - side]:
				mesh.surface_add_vertex(v)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
	return instance


func _shoulder_views() -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 75.0
	_camera.near = 0.05
	var body := PLAYER_SCENE.instantiate() as Player
	body.local_input = false
	body.capture_mouse = false
	add_child(body)
	body.set_physics_process(false)
	body.set_process(false)
	# The body brings its own camera rig, which takes the view: this capture places its own.
	_camera.make_current()
	var space := get_world_3d().direct_space_state
	for view: Array in VIEWS:
		var feet: Vector3 = view[1]
		var facing: Vector2 = view[2]
		var yaw := atan2(-facing.x, -facing.y)
		body.teleport(feet + Vector3.UP * 0.05)
		# Standing still and looking the way the view faces: the body turns to the view as in play.
		var look := PlayerCommand.new()
		look.yaw = yaw
		look.aim = true
		for _i in 40:
			body.tick(look)
			await get_tree().physics_frame
		body.reset_physics_interpolation()
		var rig := CameraProbe.rig(space, body.global_position, yaw, 1.0, -0.12)
		_camera.global_transform = Transform3D(
			Basis.from_euler(Vector3(-0.12, yaw, 0.0)), rig["camera"]
		)
		await _shot(view[0])
	body.queue_free()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote %s" % path)
