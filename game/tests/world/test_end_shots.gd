extends GdUnitTestSuite
## The end-of-night camera's angles on both maps (`MapInfo.end_shots`,
## docs/design/end-of-night.md): each map has enough of them; along the whole drift of every one
## the lens keeps clear of every wall, floor and prop (a burst of rays from it and a sphere swept
## along it), the view is not a wall in its face, and what it looks at is over the map. The
## pull-back from where a player's own camera stands at each start of each map ends clear of the
## walls and well away from the player.

## Air the lens keeps from anything solid: the shoulder camera's sphere and a little more.
const CLEAR := 0.3
## Shots a map has at least (the sequence cuts between a few).
const MIN_SHOTS := 3
## Metres along the drift between two checks.
const STEP := 0.5
## A shot's view must be open for this far before it meets a wall (a wall or a pillar in its
## face). const OPEN_VIEW := 1.5 Where the lens of a player's own camera stands from them: behind
## and above, as the shoulder rig does.
const PLAYER_LENS := Vector3(0.0, 2.1, 3.2)

var _scene: Node3D
var _space: PhysicsDirectSpaceState3D


func _load(map_id: String) -> MapInfo:
	var info := MapRegistry.of(map_id)
	_scene = auto_free(info.load_scene().instantiate()) as Node3D
	add_child(_scene)
	for i in 4:
		await get_tree().physics_frame
	_space = _scene.get_world_3d().direct_space_state
	return info


## Whether any of 26 rays (the faces, edges and corners of a cube) of length `reach` from `point`
## meets a solid thing: a point in a wall or against one is met at once from the inside, which an
## overlap test of a concave wall does not say.
func _near_solid(point: Vector3, reach: float) -> Vector3:
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x == 0 and y == 0 and z == 0:
					continue
				var ray := PhysicsRayQueryParameters3D.create(
					point, point + Vector3(x, y, z).normalized() * reach, EndCamera.WALL_MASK
				)
				var hit := _space.intersect_ray(ray)
				if not hit.is_empty():
					return hit["position"]
	return Vector3.INF


func _check_shot(map_id: String, number: int, shot: EndShot) -> Array[String]:
	var faults: Array[String] = []
	var tag := "%s shot %d" % [map_id, number]
	var length := shot.lens_from.distance_to(shot.lens_to)
	var steps := maxi(int(ceil(length / STEP)), 1)
	for i in steps + 1:
		var f := float(i) / float(steps)
		var at := shot.lens(f)
		var touched := _near_solid(at, CLEAR)
		if touched != Vector3.INF:
			faults.append(
				(
					"%s: the lens at %s (%.0f%% along) is within %.1f m of %s"
					% [tag, at, f * 100.0, CLEAR, touched]
				)
			)
			break
		var toward := shot.look(f) - at
		var ray := PhysicsRayQueryParameters3D.create(
			at, at + toward.normalized() * minf(OPEN_VIEW, toward.length()), EndCamera.WALL_MASK
		)
		var hit := _space.intersect_ray(ray)
		if not hit.is_empty():
			faults.append(
				(
					"%s: at %.0f%% the view meets %s within %.0f m"
					% [tag, f * 100.0, hit["position"], OPEN_VIEW]
				)
			)
			break
	if length > 0.01:
		var swept := CameraPlacement.sweep(
			_space, [], EndCamera.WALL_MASK, shot.lens_from, shot.lens_to - shot.lens_from, 0.2
		)
		if swept < 1.0:
			faults.append(
				"%s: the drift is stopped by a wall %.0f%% of the way" % [tag, swept * 100.0]
			)
	if shot.fov < 30.0 or shot.fov > 100.0:
		faults.append("%s: a field of view of %.0f" % [tag, shot.fov])
	return faults


func _over_the_map(point: Vector3) -> bool:
	var bounds := PlayBounds.of(_scene)
	# The look point is over the map's ground or within 8 m of the edge of it.
	for dx in [-8.0, 0.0, 8.0]:
		for dz in [-8.0, 0.0, 8.0]:
			if not bounds.is_out(Vector3(point.x + dx, 0.0, point.z + dz)):
				return true
	return false


func _check_map(map_id: String) -> void:
	var info := await _load(map_id)
	assert_int(info.end_shots.size()).is_greater_equal(MIN_SHOTS)
	var faults: Array[String] = []
	for i in info.end_shots.size():
		faults.append_array(_check_shot(map_id, i, info.end_shots[i]))
		if not _over_the_map(info.end_shots[i].look_from):
			faults.append(
				(
					"%s shot %d looks at %s, which is not over the map"
					% [map_id, i, info.end_shots[i].look_from]
				)
			)
	assert_array(faults).override_failure_message("\n".join(faults)).is_empty()


func test_the_lots_angles_keep_clear_of_every_wall() -> void:
	await _check_map("drive_in")


func test_the_back_rooms_angles_keep_clear_of_every_wall() -> void:
	await _check_map("small_indoor")


func _check_pull_back(map_id: String) -> void:
	var info := await _load(map_id)
	var spawns := _scene.get_node_or_null("Field/PlayerSpawns")
	if spawns == null:
		spawns = _scene.get_node("PlayerSpawns")
	var tuning := EndTuning.shipped()
	var faults: Array[String] = []
	for marker: Marker3D in spawns.get_children():
		var focus := marker.global_position + Vector3.UP * 0.9
		# The lens behind the player on each side of them (the player may have turned any way).
		for turn in [0.0, 90.0, 180.0, 270.0]:
			var lens := focus + PLAYER_LENS.rotated(Vector3.UP, deg_to_rad(turn))
			var end := EndCamera.pull_target(_space, lens, focus, tuning)
			var swept := CameraPlacement.sweep(
				_space, [], EndCamera.WALL_MASK, lens, end - lens, 0.1
			)
			if swept < 1.0:
				faults.append(
					"%s %s turned %.0f: the way to %s is blocked" % [map_id, marker.name, turn, end]
				)
			if _near_solid(end, 0.2) != Vector3.INF:
				faults.append(
					"%s %s turned %.0f: the end %s is in a wall" % [map_id, marker.name, turn, end]
				)
			if end.distance_to(focus) < 1.5:
				faults.append(
					"%s %s turned %.0f: no pull-back (%s)" % [map_id, marker.name, turn, end]
				)
	assert_array(faults).override_failure_message("\n".join(faults)).is_empty()
	assert_object(info).is_not_null()


func test_the_pull_back_from_the_lots_starts_is_clear_and_goes_somewhere() -> void:
	await _check_pull_back("drive_in")


func test_the_pull_back_from_the_back_rooms_starts_is_clear_and_goes_somewhere() -> void:
	await _check_pull_back("small_indoor")
