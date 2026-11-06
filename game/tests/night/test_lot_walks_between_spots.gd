# The real lot's paths between the places a bot roams to, walked with a body (Deadnight #1334).
# A solid prop that is not a CSG box (a breaker post, a `StaticBody3D`) was not in the walking mesh,
# which is baked from the CSG boxes: a path hugging the booth's north wall ran through the `booth`
# post, and a bot (and an errand to the east midway's boards) walked into its west face and stood.
# Props join the mesh through `NavmeshBaker.OBSTACLE_GROUP`.
#
# The suite sets the body down on every roam spot in turn and sends it to every other whose path
# passes near such a prop, by the path the navigation server gives it (a `HumanWalker`, through the
# server's own `apply`, the body of the game), and reads that no prop stops one for longer than a
# stumble. The mesh is the saved one the night walks on (`LotNavmeshes`).
extends GdUnitTestSuite

## Seconds the body may make no headway while it has somewhere to go. A bounce off a corner is a
## few ticks; the booth's post held it for as long as the watch went on.
const STALL_SECONDS := 0.5
## A walk is given up on after this many seconds without headway.
const GIVE_UP_SECONDS := 2.0
## Seconds a walk may take beyond the path's length at the walker's pace (it sprints).
const SLACK_SECONDS := 4.0
const PACE := 4.0
## A path counts as passing a prop when it comes this close to its centre: a post is under a metre
## across and the walking mesh's edge is 0.5 m off a wall.
const NEAR_PROP := 2.5
## A walk starts this many metres of its path before the prop and ends this many after it: a run-up
## to the prop and the way on, not the whole of a 100 m path (the suite would take a minute).
const RUN_UP := 6.0
const RUN_ON := 4.0
const SETTLE_FRAMES := 60
## Seeds of the bot's own stream, and the longest the bot may take to get from the west of the booth
## to the stand (it needs about 6 s; a stand at the post took the watch's whole 25).
const BOT_SEEDS: Array[int] = [8, 9, 10, 11]
const BOT_WATCH_SECONDS := 15.0
const TICKS_PER_SECOND := 60
## A break that outlasts every walk of the suite (seconds): no round starts, no dead come.
const LONG_BREAK := 1.0e6
## Where the soak's bot came from (west of the booth, on the line to its corner), and the east
## midway's barricade stand it was bound for.
const WEST := Vector3(-3.8, 0.1, 20.6)
const STAND := Vector3(12.5, 0.4, 31.6)
const GREYBOXES: Array[String] = [
	"res://world/drive_in_greybox.tscn", "res://world/smallmap/smallmap_greybox.tscn"
]
## The solid props still out of a mesh, by map: none since the second map's lockers joined (#1340).
## It stays empty: a new solid prop joins the group, and a note here is for a change to a map's
## saved meshes and the dead's walk that needs its own pull request.
const STILL_OUT: Dictionary[String, Array] = {}

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func _night() -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	var night := await NightFixture.seat(self, 1, tuning, 8)
	night.open_door(&"door_concession")
	night.open_door(&"door_booth")
	await night.settle(SETTLE_FRAMES)
	assert_bool(await night.settle_doors()).is_true()
	_catcher.start()
	return night


## The solid props of `root` the CSG baker does not read: bodies with only the world's layer on
## (the window frames and the boards have layers of their own, and open and shut at run time).
static func props_outside_the_bake(root: Node) -> Array[StaticBody3D]:
	var found: Array[StaticBody3D] = []
	for node in root.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body.collision_layer == PhysicsLayers.WORLD:
			found.append(body)
	return found


## The longest stand of a walk from `from` to `to` in seconds, and where the body was when it
## ended.
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


## True when the server's path `way` from `from` ends at `to` and nothing a bot's own check
## (`BotPath.walkable`) turns back lies across it: the boards of a breach, a window.
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


func _path(night: SeatedNight, from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(night.world.map(), from, to, true, NavLayers.WALK)


static func _length(way: PackedVector3Array) -> float:
	var total := 0.0
	for i in way.size() - 1:
		total += way[i].distance_to(way[i + 1])
	return total


## The stretches of `way` that pass within `NEAR_PROP` metres (on the ground plane) of a prop's
## centre: for each such prop `[start, end]`, `RUN_UP` metres of the path before its nearest point
## to the prop and `RUN_ON` after it.
static func _windows(
	way: PackedVector3Array, props: Array[StaticBody3D]
) -> Array[PackedVector3Array]:
	var found: Array[PackedVector3Array] = []
	for prop in props:
		var centre := Vector2(prop.global_position.x, prop.global_position.z)
		var nearest := INF
		var along := 0.0
		var travelled := 0.0
		for i in way.size() - 1:
			var a := Vector2(way[i].x, way[i].z)
			var b := Vector2(way[i + 1].x, way[i + 1].z)
			var closest := Geometry2D.get_closest_point_to_segment(centre, a, b)
			if closest.distance_to(centre) < nearest:
				nearest = closest.distance_to(centre)
				along = travelled + a.distance_to(closest)
			travelled += way[i].distance_to(way[i + 1])
		if nearest < NEAR_PROP:
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


## The path of the prop within a hand of the body at `at`, or "" when it touches none.
func _prop_touched(night: SeatedNight, at: Vector3) -> String:
	var shape := SphereShape3D.new()
	shape.radius = 0.62
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.9, 0.0))
	query.collision_mask = PhysicsLayers.WORLD
	var props := props_outside_the_bake(night.world.greybox)
	for hit in night.world.get_world_3d().direct_space_state.intersect_shape(query, 16):
		var collider := hit["collider"] as StaticBody3D
		if collider != null and props.has(collider):
			return str(night.world.greybox.get_path_to(collider))
	return ""


func test_the_walk_from_west_of_the_booth_to_the_east_midways_stand_never_stands_still() -> void:
	var night := await _night()
	var seen := _walk(night, night.human(1), WEST, STAND)
	night.dispose()
	await get_tree().process_frame
	(
		assert_float(seen[0])
		. override_failure_message("the body stood %.2f s, at %s" % [seen[0], seen[1]])
		. is_less(STALL_SECONDS)
	)
	assert_array(_catcher.lines).is_empty()


func test_no_walk_between_two_roam_spots_is_stopped_by_a_post() -> void:
	var night := await _night()
	var walker := night.human(1)
	walker.sprint = true
	var props := props_outside_the_bake(night.world.greybox)
	assert_int(props.size()).is_equal(4)
	var spots := night.level.roam_spots
	var stopped: Array[String] = []
	var walks := 0
	for from in spots:
		for to in spots:
			var way := _path(night, from, to)
			if from == to or not _reaches(night, way, from, to):
				continue
			for window in _windows(way, props):
				walks += 1
				var seen := _walk(night, walker, window[0], window[1])
				var touched := _prop_touched(night, seen[1])
				if float(seen[0]) >= STALL_SECONDS and touched != "":
					stopped.append(
						(
							"%s to %s, from %s: stood %.2f s against %s"
							% [from, to, window[0], seen[0], touched]
						)
					)
	night.dispose()
	await get_tree().process_frame
	# Enough walks to mean something: the posts are ringed by paths.
	assert_int(walks).is_greater(50)
	assert_array(stopped).is_empty()
	assert_array(_catcher.lines).is_empty()


func test_the_saved_mesh_has_no_ground_under_a_solid_prop() -> void:
	var night := await _night()
	for prop in props_outside_the_bake(night.world.greybox):
		var at := prop.global_position
		var ground := NavigationServer3D.map_get_closest_point(night.world.map(), at)
		(
			assert_float(Vector2(ground.x - at.x, ground.z - at.z).length())
			. override_failure_message(
				"the mesh has ground %s under %s" % [ground, night.world.greybox.get_path_to(prop)]
			)
			. is_greater(NavmeshBaker.AGENT_RADIUS)
		)
	night.dispose()
	await get_tree().process_frame


func test_every_solid_prop_of_a_map_is_in_the_baker_group() -> void:
	for path in GREYBOXES:
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		add_child(scene)
		var known: Array = STILL_OUT.get(path, [])
		for prop in props_outside_the_bake(scene):
			var prop_name := str(scene.get_path_to(prop))
			(
				assert_bool(prop.is_in_group(NavmeshBaker.OBSTACLE_GROUP) or known.has(prop_name))
				. override_failure_message(
					"%s of %s is solid and out of the mesh" % [prop_name, path]
				)
				. is_true()
			)
		scene.queue_free()
		await get_tree().process_frame


func test_a_bot_walking_from_west_of_the_booth_to_the_stand_has_no_stuck_episode() -> void:
	for bot_seed in BOT_SEEDS:
		var night := await _night()
		var bot := night.seat(1, BotProfile.regular(), bot_seed)
		var body := night.server.body_of(1)
		var brain := bot.brain as BotFightBrain
		body.teleport(WEST)
		night.run(2)
		brain._roam.spot = STAND
		var ticks := 0
		while ticks < int(BOT_WATCH_SECONDS * TICKS_PER_SECOND) and _flat(body, STAND) > 1.5:
			night.tick()
			ticks += 1
		(
			assert_int(brain.legs.stuck.episodes)
			. override_failure_message(
				(
					"seed %d: %d stuck episodes, at %s"
					% [bot_seed, brain.legs.stuck.episodes, body.global_position]
				)
			)
			. is_equal(0)
		)
		(
			assert_float(_flat(body, STAND))
			. override_failure_message(
				"seed %d: the bot is at %s" % [bot_seed, body.global_position]
			)
			. is_less_equal(1.5)
		)
		night.dispose()
		await get_tree().process_frame


static func _flat(body: Node3D, point: Vector3) -> float:
	return Vector2(body.global_position.x - point.x, body.global_position.z - point.z).length()
