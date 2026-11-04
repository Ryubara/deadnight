extends Node
## Walking-mesh path lengths between points of the lot (#950), as text: for each `--from=x,z` and
## `--to=x,z` pair, how long the path is and where it goes. Finds a spot the mesh sends the dead the
## long way round from.
##
##   godot --headless --path game res://tools/world/path_probe.tscn --
##     --from=-12.2,-35 --to=-8.5,-43


func _ready() -> void:
	var from_list: Array[Vector2] = []
	var to := Vector2.ZERO
	var map_id := "drive_in"
	var grid := PackedStringArray()
	var near := PackedStringArray()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--from="):
			from_list.append(_pair(argument.trim_prefix("--from=")))
		elif argument.begins_with("--to="):
			to = _pair(argument.trim_prefix("--to="))
		elif argument.begins_with("--near="):
			near = argument.trim_prefix("--near=").split(",")
		elif argument.begins_with("--grid="):
			grid = argument.trim_prefix("--grid=").split(",")
		elif argument.begins_with("--map="):
			map_id = argument.trim_prefix("--map=")
	var world := NightWorld.new()
	world.scene = load(MapRegistry.of(StringName(map_id)).scene_path) as PackedScene
	add_child(world)
	await world.build()
	for _i in 6:
		await get_tree().physics_frame
	var pathing := NavmeshPathing.new(world.map())
	for from in from_list:
		var path := pathing.find_path(Vector3(from.x, 0.0, from.y), Vector3(to.x, 0.0, to.y))
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		var text := ""
		for point in path:
			text += "(%.1f,%.1f)" % [point.x, point.z]
		print(
			(
				"PATH from (%.1f,%.1f): %d points, %.1f m: %s"
				% [from.x, from.y, path.size(), length, text]
			)
		)
	if near.size() >= 3:
		var height := float(near[3]) if near.size() > 3 else 1.0
		_print_near(world, Vector3(float(near[0]), height, float(near[1])), float(near[2]))
	if grid.size() == 5 and not from_list.is_empty():
		_print_grid(pathing, from_list[0], grid)
	get_tree().quit()


func _pair(text: String) -> Vector2:
	var parts := text.split(",")
	return Vector2(float(parts[0]), float(parts[1]))


## A map of how far the walk is from `from` to each cell of `grid` (x0, z0, x1, z1, step): the
## digit is the path length in tens of metres, '.' a cell with no path or off the mesh.
func _print_grid(pathing: NavmeshPathing, from: Vector2, grid: PackedStringArray) -> void:
	var x0 := float(grid[0])
	var z0 := float(grid[1])
	var x1 := float(grid[2])
	var z1 := float(grid[3])
	var step := float(grid[4])
	var z := z0
	while z <= z1:
		var row := ""
		var x := x0
		while x <= x1:
			var path := pathing.find_path(Vector3(from.x, 0.0, from.y), Vector3(x, 0.0, z))
			var mark := "."
			if (
				not path.is_empty()
				and Vector2(path[-1].x, path[-1].z).distance_to(Vector2(x, z)) < 0.6
			):
				var length := 0.0
				for i in range(1, path.size()):
					length += path[i - 1].distance_to(path[i])
				mark = str(mini(int(length / 5.0), 9))
			row += mark
			x += step
		print("GRID z=%6.1f %s" % [z, row])
		z += step


## The solids within `radius` of `at`: what the physics server holds there, by path.
func _print_near(world: Node, at: Vector3, radius: float) -> void:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), at)
	query.collision_mask = 0xFFFFFFFF
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query, 64):
		var body: Node = hit["collider"]
		var place := ""
		if body is Node3D:
			place = (
				" at (%.1f,%.1f,%.1f)"
				% [body.global_position.x, body.global_position.y, body.global_position.z]
			)
		print("NEAR ", body.get_path(), " ", body.get_class(), place)
