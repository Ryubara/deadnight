extends Node3D
## Top-down picture of the zombies' walking mesh with only the concession door open, and the path
## a bot gets to the booth door (#590). Not part of the game. Arguments after `--`:
##   `--target=slab`   walk to the slab's middle (`door_points`): the path stops short of the door;
##   `--target=stand`  (default) walk to the stand in front of it (`door_stands`).
## Green is the walking mesh, red the slab's middle, blue the stand, yellow the path from the field,
## white where the path ends.

const GREYBOX := preload("res://world/drive_in_greybox.tscn")
const FIELD := Vector3(0.0, 0.0, -34.0)
const DOOR := "Door_ProjectionBooth"
const LIFT := 0.6

var _args := {}


func _ready() -> void:
	_args = _parse_args()
	var lot := GREYBOX.instantiate()
	add_child(lot)
	_hide_roofs(lot)
	var doors := lot.get_node("Doors") as LotDoors
	await get_tree().physics_frame
	doors.open(&"door_concession")
	await get_tree().physics_frame
	var navmesh := NavmeshBaker.bake(lot)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = navmesh
	lot.add_child(region)
	var map := get_world_3d().navigation_map
	for _i in 600:
		await get_tree().physics_frame
		if not (
			NavigationServer3D.map_get_path(map, FIELD, Vector3(0.0, 0.0, -30.0), true).is_empty()
		):
			break
	for _i in 3:
		await get_tree().physics_frame
	var door := doors.get_node(DOOR)
	var slab: Vector3 = (door.get_node("Front") as Node3D).global_position
	var stand: Vector3 = (door.get_node("StandFront") as Node3D).global_position
	var goal := slab if _args.get("target", "stand") == "slab" else stand
	var way := NavigationServer3D.map_get_path(map, FIELD, goal, true)
	var end := way[way.size() - 1]
	_draw_mesh(navmesh)
	_draw_path(way)
	_dot(slab, Color(1, 0.1, 0.1), 1.2)
	_dot(stand, Color(0.2, 0.5, 1), 0.8)
	_dot(end, Color.WHITE, 1.0)
	print(
		(
			"target=%s goal=%s end=%s short by %.2f m"
			% [_args.get("target", "stand"), goal, end, _flat(end, goal)]
		)
	)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 78.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 80, 6), Vector3(0, 0, 6), Vector3(0, 0, -1))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-90, 0, 0)
	add_child(light)
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(24, 16)
	label.size = Vector2(1600, 120)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.text = (
		(
			"walk to the door's %s: the path ends %.1f m short of the goal\n"
			+ "red slab middle, blue stand, yellow path, white path end"
		)
		% [_args.get("target", "stand"), _flat(end, goal)]
	)
	layer.add_child(label)


## Metres apart on the ground.
func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _hide_roofs(lot: Node3D) -> void:
	for node in lot.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		if box.global_position.y - box.size.y * 0.5 > 3.0:
			box.visible = false


func _draw_mesh(navmesh: NavigationMesh) -> void:
	var vertices := navmesh.get_vertices()
	var points := PackedVector3Array()
	for i in navmesh.get_polygon_count():
		var polygon := navmesh.get_polygon(i)
		for k in range(1, polygon.size() - 1):
			for index in [polygon[0], polygon[k], polygon[k + 1]]:
				points.append(vertices[index] + Vector3(0.0, LIFT, 0.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.1, 0.9, 0.3, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)


func _draw_path(way: PackedVector3Array) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0.9, 0.1)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in range(1, way.size()):
		var a := way[i - 1]
		var b := way[i]
		var side := (b - a).cross(Vector3.UP).normalized() * 0.4
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
		for p in [a - side, a + side, b + side, a - side, b + side, b - side]:
			mesh.surface_add_vertex(p + Vector3(0.0, LIFT + 0.3, 0.0))
		mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)


func _dot(at: Vector3, color: Color, radius: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = sphere
	instance.material_override = material
	instance.position = Vector3(at.x, LIFT + 1.0, at.z)
	add_child(instance)


func _parse_args() -> Dictionary:
	var found := {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var parts := argument.substr(2).split("=", true, 1)
			found[parts[0]] = parts[1]
	return found
