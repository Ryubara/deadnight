# The second map's four lockers are in its walking mesh (Deadnight #1340, the same hole #1334 closed
# for the lot's breaker posts). A locker is a `StaticBody3D` of about 1.2 by 1 by 0.4 m on the
# world's layer; the baker reads CSG boxes, so the saved mesh ran straight through each one and a
# body sent past a locker walked into it and stood. A body joins the baker's input through
# `NavmeshBaker.OBSTACLE_GROUP`.
#
# The suite walks a body (a `HumanWalker`, through the server's own `apply`, the body of the game)
# over the real map and its saved meshes, with every link bought: straight across each locker from
# each side, and between the places a bot roams to wherever the path passes near one. It reads that
# no locker stops the body for longer than a stumble.
extends GdUnitTestSuite

const PATH := "res://world/smallmap/smallmap_navmeshes.res"
const LOCKERS: Array[String] = [
	"ShopProps/LockerStart",
	"ShopProps/LockerSide",
	"ShopProps/LockerUpstairs",
	"ShopProps/LockerUpstairsA",
]
## The locker no person's path crosses: its ground is in the pieces only the dead walk
## (`NavLayers`), so the dead's paths are checked for it
## (`test_the_dead_s_paths_keep_clear_of_every_locker`).
const WALKLESS: Array[String] = ["ShopProps/LockerUpstairsA"]
const LINKS: Array[StringName] = [&"door_side", &"door_stairs_start", &"door_stairs_side"]
## Seconds the body may make no headway while it has somewhere to go. A bounce off a corner is a few
## ticks; a locker held it for as long as the watch went on.
const STALL_SECONDS := 0.5
## A walk is given up on after this many seconds without headway.
const GIVE_UP_SECONDS := 2.0
## Seconds a walk may take beyond the path's length at the walker's pace (it sprints).
const SLACK_SECONDS := 4.0
const PACE := 4.0
## How far from a locker's centre a straight walk starts and ends, and how far a roam path may pass
## it to be walked.
const ACROSS := 2.5
## A straight line between two ring points crosses a locker when it passes this close to its centre.
const CROSSING := 0.7
const RING_POINTS := 16
## The dead's path keeps this far (metres, on the ground plane) from a locker's box: a body is 0.35
## m in radius, and the baker keeps its mesh 0.5 m off the box (less at a simplified corner).
const CLEARANCE := 0.3
const SAMPLE := 0.05
## A ring point is taken when the mesh has ground this near it.
const RING_SNAP := 0.6
const NEAR_LOCKER := 2.5
## A pair's walk starts this many metres of its path before the locker and ends this many after it.
const RUN_UP := 6.0
const RUN_ON := 4.0
const SETTLE_FRAMES := 60
## A break that outlasts every walk of the suite (seconds): no round starts, no dead come.
const LONG_BREAK := 1.0e6

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func _night() -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await SmallMapNight.seat(self, 1, tuning, 8)
	for link in LINKS:
		night.open_door(link)
	await night.settle(SETTLE_FRAMES)
	assert_bool(await night.settle_doors()).is_true()
	_catcher.start()
	return night


func _lockers(night: SeatedNight) -> Array[StaticBody3D]:
	var found: Array[StaticBody3D] = []
	for path in LOCKERS:
		found.append(night.world.greybox.get_node(path) as StaticBody3D)
	return found


## The longest stand of a walk from `from` to `to` in seconds, and where the body was when it ended.
func _walk(night: SeatedNight, walker: HumanWalker, from: Vector3, to: Vector3) -> Array:
	var body := night.server.body_of(1)
	body.teleport(from)
	night.run(2)
	walker.goto(to)
	var allowed := _length(_path(night, from, to)) / PACE + SLACK_SECONDS
	var worst := 0.0
	var seconds := 0.0
	while not walker.arrived() and seconds < allowed and worst < GIVE_UP_SECONDS:
		walker.tick()
		night.tick()
		worst = maxf(worst, walker.stalled)
		seconds += Night.STEP
	walker.stop()
	return [worst, body.global_position]


func _path(night: SeatedNight, from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(night.world.map(), from, to, true, NavLayers.WALK)


static func _length(way: PackedVector3Array) -> float:
	var total := 0.0
	for i in way.size() - 1:
		total += way[i].distance_to(way[i + 1])
	return total


## True when the server's path `way` runs from `from` to `to` and nothing a bot's own check
## (`BotPath.walkable`) turns back lies across it.
func _reaches(night: SeatedNight, way: PackedVector3Array, from: Vector3, to: Vector3) -> bool:
	if way.is_empty() or way[way.size() - 1].distance_to(to) >= 1.0:
		return false
	if way[0].distance_to(from) >= 1.0:
		return false
	var low := Vector3(0.0, BotPath.WALK_HEIGHT, 0.0)
	for i in way.size() - 1:
		if night.level.walk_hit(way[i] + low, way[i + 1] + low) >= 0.0:
			return false
	return true


## The stretches of `way` that pass within `NEAR_LOCKER` metres (on the ground plane) of a locker's
## centre: for each such locker `[start, end]`, `RUN_UP` metres of the path before its nearest point
## and `RUN_ON` after it.
static func _windows(
	way: PackedVector3Array, lockers: Array[StaticBody3D]
) -> Array[PackedVector3Array]:
	var found: Array[PackedVector3Array] = []
	for locker in lockers:
		var centre := Vector2(locker.global_position.x, locker.global_position.z)
		var nearest := INF
		var along := 0.0
		var travelled := 0.0
		for i in way.size() - 1:
			var a := Vector2(way[i].x, way[i].z)
			var b := Vector2(way[i + 1].x, way[i + 1].z)
			var closest := Geometry2D.get_closest_point_to_segment(centre, a, b)
			# A locker upstairs is not on the path of the floor below it.
			if (
				closest.distance_to(centre) < nearest
				and absf(way[i].y - (locker.global_position.y - 0.5)) < 1.0
			):
				nearest = closest.distance_to(centre)
				along = travelled + a.distance_to(closest)
			travelled += way[i].distance_to(way[i + 1])
		if nearest < NEAR_LOCKER:
			found.append(
				PackedVector3Array([_point_at(way, along - RUN_UP), _point_at(way, along + RUN_ON)])
			)
	return found


## The point `distance` metres along `way`, held to its two ends.
static func _point_at(way: PackedVector3Array, distance: float) -> Vector3:
	var left := maxf(distance, 0.0)
	for i in way.size() - 1:
		var length := way[i].distance_to(way[i + 1])
		if left <= length:
			return way[i].lerp(way[i + 1], left / maxf(length, 0.0001))
		left -= length
	return way[way.size() - 1]


## The path of the locker within a hand of the body at `at`, or "" when it touches none.
func _locker_touched(night: SeatedNight, at: Vector3) -> String:
	var shape := SphereShape3D.new()
	shape.radius = 0.62
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.9, 0.0))
	query.collision_mask = PhysicsLayers.WORLD
	var lockers := _lockers(night)
	for hit in night.world.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var collider := hit["collider"] as StaticBody3D
		if collider != null and lockers.has(collider):
			return str(night.world.greybox.get_path_to(collider))
	return ""


func test_the_four_lockers_are_where_the_suite_looks() -> void:
	var scene := (load(SmallMapMeasure.SCENE) as PackedScene).instantiate() as Node3D
	add_child(scene)
	for path in LOCKERS:
		var locker := scene.get_node_or_null(path) as StaticBody3D
		assert_object(locker).override_failure_message("%s is gone" % path).is_not_null()
		assert_bool(locker.is_in_group(NavmeshBaker.OBSTACLE_GROUP)).is_true()
	scene.queue_free()
	await get_tree().process_frame


func test_a_body_sent_across_a_locker_is_not_stopped_by_it() -> void:
	var night := await _night()
	var walker := night.human(1)
	walker.sprint = true
	var stopped: Array[String] = []
	var walked: Dictionary[String, int] = {}
	for locker in _lockers(night):
		var name := str(night.world.greybox.get_path_to(locker))
		for ends in _crossings(night, locker):
			walked[name] = walked.get(name, 0) + 1
			var seen := _walk(night, walker, ends[0], ends[1])
			var touched := _locker_touched(night, seen[1])
			if float(seen[0]) >= STALL_SECONDS and touched != "":
				stopped.append(
					"%s to %s: stood %.2f s against %s" % [ends[0], ends[1], seen[0], touched]
				)
	night.dispose()
	await get_tree().process_frame
	for path in LOCKERS:
		if not WALKLESS.has(path):
			(
				assert_int(walked.get(path, 0))
				. override_failure_message("no walk across %s" % path)
				. is_greater(0)
			)
	assert_array(stopped).is_empty()
	assert_array(_catcher.lines).is_empty()


## True when the straight line from `from` to `to` passes farther than `CROSSING` from the centre of
## `locker`.
static func _line_misses(locker: StaticBody3D, from: Vector3, to: Vector3) -> bool:
	var middle := Vector2(locker.global_position.x, locker.global_position.z)
	var line := Geometry2D.get_closest_point_to_segment(
		middle, Vector2(from.x, from.z), Vector2(to.x, to.z)
	)
	return line.distance_to(middle) > CROSSING


## The least distance (metres, on the ground plane) between `way` and the footprint of `locker`'s
## box, the path read every `SAMPLE` metres.
static func _clearance(locker: StaticBody3D, way: PackedVector3Array) -> float:
	var shape := locker.get_node("Shape") as CollisionShape3D
	var half := (shape.shape as BoxShape3D).size * 0.5
	var inverse := locker.global_transform.affine_inverse()
	var least := INF
	for i in way.size() - 1:
		var steps := maxi(int(way[i].distance_to(way[i + 1]) / SAMPLE), 1)
		for step in steps + 1:
			var local := inverse * way[i].lerp(way[i + 1], float(step) / float(steps))
			var outside := Vector2(
				maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.z) - half.z, 0.0)
			)
			least = minf(least, outside.length())
	return least


## The walks of the server's path that cross `locker`: from a point on a ring round it to one on the
## other side, where the straight line between them runs within `CROSSING` metres of its centre (a
## path through the locker, were it in the mesh) and the server's path between them is walkable.
func _crossings(night: SeatedNight, locker: StaticBody3D) -> Array[PackedVector3Array]:
	var ring := _ring(night, locker)
	var found: Array[PackedVector3Array] = []
	for from in ring:
		for to in ring:
			if from == to or _line_misses(locker, from, to):
				continue
			if _reaches(night, _path(night, from, to), from, to):
				found.append(PackedVector3Array([from, to]))
	return found


## Points of the mesh on a ring of `ACROSS` metres round `locker`, on its floor.
func _ring(night: SeatedNight, locker: StaticBody3D) -> Array[Vector3]:
	var map := night.world.map()
	var centre := locker.global_position - Vector3(0.0, 0.5, 0.0)
	var ring: Array[Vector3] = []
	for i in RING_POINTS:
		var angle := TAU * float(i) / float(RING_POINTS)
		var wanted := centre + Vector3(cos(angle), 0.0, sin(angle)) * ACROSS
		var on_mesh := NavigationServer3D.map_get_closest_point(map, wanted)
		if (
			Vector2(on_mesh.x - wanted.x, on_mesh.z - wanted.z).length() < RING_SNAP
			and absf(on_mesh.y - wanted.y) < 0.6
		):
			ring.append(on_mesh)
	return ring


func test_no_walk_between_two_roam_spots_is_stopped_by_a_locker() -> void:
	var night := await _night()
	var walker := night.human(1)
	walker.sprint = true
	var lockers := _lockers(night)
	var spots := night.level.roam_spots
	var stopped: Array[String] = []
	var walks := 0
	for from in spots:
		for to in spots:
			var way := _path(night, from, to)
			if from == to or not _reaches(night, way, from, to):
				continue
			for window in _windows(way, lockers):
				walks += 1
				var seen := _walk(night, walker, window[0], window[1])
				var touched := _locker_touched(night, seen[1])
				if float(seen[0]) >= STALL_SECONDS and touched != "":
					stopped.append(
						(
							"%s to %s, from %s: stood %.2f s against %s"
							% [from, to, window[0], seen[0], touched]
						)
					)
	night.dispose()
	await get_tree().process_frame
	# Enough walks to mean something: the lockers stand in the rooms' paths.
	assert_int(walks).is_greater(20)
	assert_array(stopped).is_empty()
	assert_array(_catcher.lines).is_empty()


func test_the_dead_s_paths_keep_clear_of_every_locker() -> void:
	var night := await _night()
	for locker in _lockers(night):
		var name := str(night.world.greybox.get_path_to(locker))
		var ring := _ring(night, locker)
		var crossed := 0
		var closest := INF
		for from in ring:
			for to in ring:
				if from == to or _line_misses(locker, from, to):
					continue
				var way := NavigationServer3D.map_get_path(
					night.world.map(), from, to, true, NavLayers.DEAD
				)
				if way.is_empty() or way[way.size() - 1].distance_to(to) >= 1.0:
					continue
				crossed += 1
				closest = minf(closest, _clearance(locker, way))
		(
			assert_int(crossed)
			. override_failure_message("the dead have no path across %s" % name)
			. is_greater(0)
		)
		(
			assert_float(closest)
			. override_failure_message("a path of the dead runs %.2f m from %s" % [closest, name])
			. is_greater_equal(CLEARANCE)
		)
	night.dispose()
	await get_tree().process_frame


func test_the_mesh_the_night_walks_on_has_no_ground_under_a_locker() -> void:
	var night := await _night()
	# The night walks on the saved file, not on a bake it made itself: a stale file would be
	# baked over with a warning, and the walk would be the right one for the wrong reason.
	var saved := night.world.layout.navmeshes()
	assert_str(saved.resource_path).is_equal(PATH)
	assert_object(saved.mesh_for(night.world.greybox)).is_not_null()
	assert_object(night.world.navigation.saved).is_same(saved)
	for locker in _lockers(night):
		var at := locker.global_position - Vector3(0.0, 0.5, 0.0)
		var ground := NavigationServer3D.map_get_closest_point(night.world.map(), at)
		(
			assert_float(Vector2(ground.x - at.x, ground.z - at.z).length())
			. override_failure_message(
				(
					"the mesh has ground %s under %s"
					% [ground, night.world.greybox.get_path_to(locker)]
				)
			)
			. is_greater(NavmeshBaker.AGENT_RADIUS)
		)
	night.dispose()
	await get_tree().process_frame
