extends SceneTree
## Two audits of a map scene for the design review (#833), as JSON:
##
## - the dead's spawn points: inside a solid or off the floor, in view of the players' start, how
##   far from the nearest breach (a `Barricade`), and the nearest lamp;
## - the shop spots (a press reaches a flat distance of `spot_reach`, with no wall test): for each,
##   how many standing places within reach have a wall between them and the spot.
##
##   godot --headless --path game -s res://tools/world/map_audit.gd -- \
##     --scene=res://world/drive_in_greybox.tscn --out=<absolute>.json

const GRID := 0.5
const EYE := 1.0
const WORLD := 1
## A shop spot's reach (`NightTuning.spot_reach`, from its marker).
var _reach := NightTuning.shipped().spot_reach

var _space: PhysicsDirectSpaceState3D
var _scene: Node3D


func _initialize() -> void:
	var scene_path := ""
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
		elif argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	_scene = (load(scene_path) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	for _i in 6:
		await physics_frame
	_space = _scene.get_world_3d().direct_space_state
	var report := {"spawns": _spawns(), "spots": _spots()}
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print(
		"audited ",
		report["spawns"].size(),
		" spawns and ",
		report["spots"].size(),
		" spots -> ",
		out
	)
	quit()


func _starts() -> Array[Vector3]:
	var starts: Array[Vector3] = []
	for node in _scene.find_children("*", "Marker3D", true, false):
		if String(node.get_parent().name) == "PlayerSpawns":
			starts.append((node as Node3D).global_position)
	return starts


func _spawns() -> Array:
	var rows: Array = []
	var starts := _starts()
	var breaches: Array[Vector3] = []
	for node in _scene.find_children("*", "Node3D", true, false):
		if node is Barricade:
			breaches.append((node as Barricade).centre())
	var lamps: Array[Vector3] = []
	for light in _scene.find_children("*", "OmniLight3D", true, false):
		if (
			(light as Light3D).is_in_group("powered_light")
			or String((light as Node).get_path()).contains("Lamps")
		):
			lamps.append((light as Node3D).global_position)
	for node in _scene.find_children("*", "Node3D", true, false):
		if node.get_parent() == null or String(node.get_parent().name) != "ZombieSpawns":
			continue
		var at := (node as Node3D).global_position
		var seen_from := 0
		var nearest_start := INF
		for start in starts:
			nearest_start = minf(nearest_start, start.distance_to(at))
			if not _blocked(start + Vector3(0, 1.55, 0), at + Vector3(0, 1.4, 0)):
				seen_from += 1
		var breach := INF
		for centre in breaches:
			breach = minf(breach, Vector2(centre.x - at.x, centre.z - at.z).length())
		var lamp := INF
		for position in lamps:
			lamp = minf(lamp, position.distance_to(Vector3(at.x, position.y, at.z)))
		(
			rows
			. append(
				{
					"path": String(_scene.get_path_to(node)),
					"pos": _v(at),
					"inside_solid": _inside_solid(at),
					"floor_below": _floor_y(at),
					"starts_seeing_it": seen_from,
					"starts": starts.size(),
					"nearest_start": snappedf(nearest_start, 0.1),
					"nearest_breach": snappedf(breach, 0.1),
					"nearest_lamp": snappedf(lamp, 0.1),
					"meta": _meta(node),
				}
			)
		)
	return rows


func _spots() -> Array:
	var rows: Array = []
	var group := _scene.get_node_or_null("ShopSpots")
	if group == null:
		return rows
	for marker in group.get_children():
		var at := (marker as Node3D).global_position
		var total := 0
		var blocked := 0
		var worst := []
		var x := -_reach
		while x <= _reach:
			var z := -_reach
			while z <= _reach:
				if Vector2(x, z).length() <= _reach:
					var floor_y := _floor_y(Vector3(at.x + x, at.y + 0.5, at.z + z))
					if floor_y != INF and absf(floor_y - at.y) < 0.6:
						var spot_eye := Vector3(at.x + x, floor_y + EYE, at.z + z)
						if not _inside_solid(Vector3(at.x + x, floor_y, at.z + z)):
							total += 1
							if _blocked(spot_eye, at + Vector3(0, EYE, 0)):
								blocked += 1
								if worst.size() < 3 or Vector2(x, z).length() < _near(worst):
									worst.append(
										{
											"at": _v(Vector3(at.x + x, floor_y, at.z + z)),
											"apart": snappedf(Vector2(x, z).length(), 0.1)
										}
									)
				z += GRID
			x += GRID
		worst.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return a["apart"] < b["apart"]
		)
		(
			rows
			. append(
				{
					"path": String(_scene.get_path_to(marker)),
					"pos": _v(at),
					"meta": _meta(marker),
					"standing_places_in_reach": total,
					"behind_a_wall": blocked,
					"nearest_behind_a_wall": worst.slice(0, 3),
				}
			)
		)
	return rows


func _near(worst: Array) -> float:
	var best := INF
	for entry: Dictionary in worst:
		best = minf(best, entry["apart"])
	return best


func _blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = WORLD
	return not _space.intersect_ray(query).is_empty()


func _inside_solid(at: Vector3) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = WORLD
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 0.9, 0))
	return not _space.intersect_shape(query, 1).is_empty()


func _floor_y(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3(0, 1.0, 0), at - Vector3(0, 1.5, 0)
	)
	query.collision_mask = WORLD
	var hit := _space.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else INF


func _meta(node: Node) -> Dictionary:
	var meta := {}
	for key in node.get_meta_list():
		var value: Variant = node.get_meta(key)
		if (
			value is String
			or value is StringName
			or value is int
			or value is float
			or value is bool
		):
			meta[String(key)] = value
	return meta


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
