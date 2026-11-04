# Bots walk on what a person can walk (#995). The dead's navigation mesh joins the yard, the road
# and the plaza to the lot through every breach of the fence, and the boards across a breach stop a
# person: a bot sent home from the road was routed through the nearest breach and stood against its
# boards for as long as it wanted to go home. The walking mesh (`NavLayers.WALK`, what a path asked
# without a layer uses) has no polygon across a barricade; the dead's (`NavLayers.DEAD`) keeps them.
#
# The bots start beyond the road door, on the far side of the lot's south breaches, with every door
# sold, in a break that does not end; the way home is the lot's gate and nothing else.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SEED := 41
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60
const DOORS: Array[StringName] = [
	&"door_concession", &"door_booth", &"door_back_lot", &"door_yard", &"door_road"
]
## Where a bot starts: the plaza just south of each of the midway's pockets' breaches, the yard's
## and the back lot's south breaches' outer ground, and the road door.
const STARTS: Array[Vector3] = [
	Vector3(12.0, 0.0, 34.0),
	Vector3(-12.0, 0.0, 34.0),
	Vector3(0.0, 0.0, 40.0),
]
## Seconds a bot is given to get home from the road, and the metres from home that count as there.
const HOME_SECONDS := 60.0
const HOME_RADIUS := 6.0
## Metres a barricade's line is widened by when a path is checked against it.
const LINE_SLACK := 0.1
## Metres between the points of a path that are checked against a barricade's line.
const SAMPLE := 0.05

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func _tuning() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	return tuning


func _night() -> SeatedNight:
	var night := await NightFixture.seat(self, 1, _tuning(), SEED)
	for door in DOORS:
		night.open_door(door)
	await night.settle(SETTLE_FRAMES)
	await _wait_for_mesh(night)
	_catcher.start()
	return night


func _wait_for_mesh(night: SeatedNight) -> void:
	for _i in 1200:
		if not night.world.navigation.is_busy():
			break
		await get_tree().physics_frame
	await night.settle(SETTLE_FRAMES)


func test_the_walking_mesh_has_no_way_through_a_barricade_and_the_dead_do() -> void:
	var night := await _night()
	var map := night.world.map()
	var barricades := night.world.find_children("*", "Barricade", true, false)
	assert_int(barricades.size()).is_greater(10)
	var dead_crossed := 0
	for node in barricades:
		var barricade := node as Barricade
		var out := barricade.global_transform * Vector3(0.0, 0.0, -1.2)
		var inside := barricade.global_transform * Vector3(0.0, 0.0, 1.2)
		var on := NavigationServer3D.map_get_closest_point(map, out)
		var walk := NavigationServer3D.map_get_path(map, on, inside, true, NavLayers.WALK)
		(
			assert_bool(_crosses(barricade, walk))
			. override_failure_message("a walking path crosses %s: %s" % [barricade.name, walk])
			. is_false()
		)
		var dead := NavigationServer3D.map_get_path(map, on, inside, true, NavLayers.DEAD)
		if _crosses(barricade, dead):
			dead_crossed += 1
	# The dead's way in is the gap: nearly every breach is crossed by a path of theirs.
	(
		assert_int(dead_crossed)
		. override_failure_message(
			"the dead cross %d of %d barricades" % [dead_crossed, barricades.size()]
		)
		. is_greater(barricades.size() - 3)
	)
	night.dispose()
	await get_tree().process_frame


func test_a_bot_beyond_the_road_door_gets_home_by_the_gate() -> void:
	for start in STARTS:
		var night := await _night()
		var body := night.server.body_of(1)
		night.server.rules.players[1].points = 0
		night.seat(1, BotProfile.autopilot(), SEED + 1, true)
		body.teleport(
			NavigationServer3D.map_get_closest_point(night.world.map(), start) + Vector3(0, 0.1, 0)
		)
		var home := Autopilot.HOME
		var seconds := -1.0
		for tick in int(HOME_SECONDS * TICKS_PER_SECOND):
			night.tick()
			if _flat(body.global_position, home) < HOME_RADIUS:
				seconds = float(tick) / TICKS_PER_SECOND
				break
		(
			assert_float(seconds)
			. override_failure_message(
				"the bot from %s stopped at %s" % [start, body.global_position]
			)
			. is_greater(0.0)
		)
		assert_array(_catcher.lines).is_empty()
		night.dispose()
		await get_tree().process_frame


## Whether `path` passes through the boards' line of `barricade`: a point of it within `LINE_SLACK`
## metres of the line and within the boards' length of the middle (sampled every `SAMPLE` metres).
func _crosses(barricade: Barricade, path: PackedVector3Array) -> bool:
	var to_local := barricade.global_transform.affine_inverse()
	for i in path.size() - 1:
		var a := to_local * path[i]
		var b := to_local * path[i + 1]
		var steps := maxi(ceili(a.distance_to(b) / SAMPLE), 1)
		for step in steps + 1:
			var at := a.lerp(b, float(step) / float(steps))
			if absf(at.z) <= LINE_SLACK and absf(at.x) <= barricade.board_half:
				return true
	return false


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
