# Bots that move (bots plan, phase 2), scenarios 17 to 20 in the real lot: a person who walks at a
# bot in a gap is given way, the bots follow through a door whose mesh was just swapped with no
# navigation error printed, a goal the mesh does not reach is marked and replaced without a storm
# of questions, and every known obstacle (the car gaps, the booth ramp, the generator cage) is
# crossed with no stuck episode over six seconds. A negative control walls a gap the mesh does not
# know about: the ladder must solve it or report it. Ticks are run by hand; the only awaits are the
# few physics frames the navigation server needs to take a new mesh in.
extends GdUnitTestSuite

const STEP := Night.STEP
const TICKS_PER_SECOND := 60
## The longest a stuck episode may last in these scenarios (seconds): the issue's limit.
const SOLVED_WITHIN := 6.0
## Seconds a crossing may take.
const CROSSING_SECONDS := 40.0
const SEED := 31

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


## A night with `humans` stand-ins (seats 1 to humans, walkers) and `bots` hosted bots after them,
## in the first break, with the doors in `doors` sold and the mesh settled.
func _night(humans: int, bots: int, doors: Array[StringName] = []) -> SeatedNight:
	var night := await NightFixture.seat(self, humans + bots, SeatedNight.one_a_round(), SEED)
	for id in range(1, humans + 1):
		night.human(id)
	for id in range(humans + 1, humans + bots + 1):
		night.seat(id, BotProfile.regular(), SEED + id)
	for door in doors:
		night.open_door(door)
	await night.settle(12)
	return night


func _place(night: SeatedNight, id: int, at: Vector3) -> void:
	night.server.body_of(id).teleport(at + Vector3(0.0, 0.1, 0.0))


## A bot with a test brain that only wants to be at the goal it is given.
func _goal_bot(night: SeatedNight, id: int) -> GoalBrain:
	var bot: BotClient = night.host.bots[0]
	for candidate in night.host.bots:
		if candidate.state.player_id == id:
			bot = candidate
	var brain := GoalBrain.new()
	brain.legs = bot.legs
	bot.brain = brain
	return brain


func _bot(night: SeatedNight, id: int) -> BotClient:
	for candidate in night.host.bots:
		if candidate.state.player_id == id:
			return candidate
	return null


func _where(night: SeatedNight, id: int) -> Vector3:
	return night.server.body_of(id).global_position


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Walks bot `id` from `from` to `goal` (a goal brain) and returns how it went:
## `{arrived, seconds, closest (to `via`, when given), longest_stuck, depth}`.
func _cross(
	night: SeatedNight, id: int, from: Vector3, goal: Vector3, via := Vector3.INF
) -> Dictionary:
	_place(night, id, from)
	night.run(5)
	var brain := _goal_bot(night, id)
	brain.goal = goal
	var bot := _bot(night, id)
	var closest := INF
	var ticks := 0
	while ticks < int(CROSSING_SECONDS * TICKS_PER_SECOND):
		night.tick()
		ticks += 1
		if via != Vector3.INF:
			closest = minf(closest, _flat(_where(night, id), via))
		if _flat(_where(night, id), goal) < 1.5:
			break
	return {
		"arrived": _flat(_where(night, id), goal) < 1.5,
		"seconds": float(ticks) / float(TICKS_PER_SECOND),
		"closest": closest,
		"longest_stuck": bot.legs.stuck.longest(),
		"depth": bot.legs.stuck.depth_max,
		"stuck_seconds": bot.legs.stuck.stuck_seconds,
	}


func _assert_crossed(result: Dictionary, label: String, through := INF) -> void:
	(
		assert_bool(result["arrived"])
		. override_failure_message("%s: did not arrive: %s" % [label, result])
		. is_true()
	)
	(
		assert_float(result["longest_stuck"])
		. override_failure_message("%s: %s" % [label, result])
		. is_less(SOLVED_WITHIN)
	)
	if through != INF:
		(
			assert_float(result["closest"])
			. override_failure_message("%s: %s" % [label, result])
			. is_less(through)
		)


# --- Scenario 17: a person walks at the bot in a gap ---


func test_scenario_17_a_person_who_walks_at_a_bot_in_a_gap_is_given_way_within_a_second() -> void:
	var night := await _night(1, 1)
	var gap := _car_gaps(night)[0]
	var middle: Vector3 = gap["middle"]
	var bot := _bot(night, 2)
	# It holds where it stands unless something moves it: the way given is the only thing here.
	bot.profile.follows = false
	var walker := night.walkers[0]
	_place(night, 2, middle)
	_place(night, 1, gap["from"])
	night.run(5)
	walker.goto(gap["to"])
	var met := -1
	var clear_at := -1
	var longest_stall := 0.0
	var ticks := 0
	while ticks < 15 * TICKS_PER_SECOND and not walker.arrived():
		night.tick()
		ticks += 1
		longest_stall = maxf(longest_stall, walker.stalled)
		var apart := _flat(_where(night, 1), _where(night, 2))
		if met < 0 and apart < BotLegs.YIELD_NEAR:
			met = ticks
		if met >= 0 and clear_at < 0 and bot.legs.yielded_seconds > 0.0:
			clear_at = ticks
	# The person got where they were going, and was not held up for more than a moment.
	assert_bool(walker.arrived()).is_true()
	assert_float(longest_stall).is_less(1.0)
	# The bot began to give way within a second of the person coming within two and a half metres.
	assert_int(met).is_greater(0)
	assert_int(clear_at).is_greater(0)
	assert_int(clear_at - met).is_less_equal(TICKS_PER_SECOND)
	assert_float(bot.legs.yielded_seconds).is_greater(0.0)
	night.dispose()


# --- Scenario 18: the bots follow a person through a door that has just been bought ---


func test_scenario_18_the_bots_follow_through_a_door_whose_mesh_was_just_swapped() -> void:
	var night := await _night(1, 2)
	_catcher.start()
	var walker := night.walkers[0]
	_place(night, 1, Vector3(0.0, 0.0, -9.0))
	_place(night, 2, Vector3(-3.0, 0.0, -14.0))
	_place(night, 3, Vector3(3.0, 0.0, -14.0))
	night.run(30)
	walker.goto(Vector3(0.0, 0.0, -6.0))
	for _i in 6 * TICKS_PER_SECOND:
		night.tick()
		if walker.arrived():
			break
	assert_bool(walker.arrived()).is_true()
	# The door is bought with the bots a few metres behind. They see it in the next frame; the
	# engine takes the new mesh in over the next few physics frames while the night goes on.
	night.open_door(&"door_concession")
	night.run(3)
	night.give_order(BotOrders.FOLLOW, 1, _where(night, 1))
	walker.goto(Vector3(0.0, 0.0, 6.0))
	await night.settle(12)
	var route: Array[Vector3] = [
		Vector3(0.0, 0.0, 6.0), Vector3(-10.0, 0.0, 30.0), Vector3(0.0, 0.0, 34.0)
	]
	var leg := 0
	for _i in 60 * TICKS_PER_SECOND:
		night.tick()
		if walker.arrived():
			leg += 1
			if leg >= route.size():
				break
			walker.goto(route[leg])
	assert_int(leg).is_greater_equal(route.size())
	night.run(4 * TICKS_PER_SECOND)
	_catcher.stop()
	for id in [2, 3]:
		var bot := _bot(night, id)
		# Through the door and with the person.
		(
			assert_float(_where(night, id).z)
			. override_failure_message("bot %d at %s" % [id, _where(night, id)])
			. is_greater(0.0)
		)
		assert_float(_flat(_where(night, id), _where(night, 1))).is_less(12.0)
		assert_int(bot.legs.path.door_drops).is_equal(1)
		assert_int(bot.legs.path.empty_answers).is_equal(0)
		assert_float(bot.legs.stuck.longest()).is_less(SOLVED_WITHIN)
	# And the engine printed no navigation error in all of it.
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- Scenario 19: a goal the mesh does not reach ---


func test_scenario_19_a_goal_the_mesh_does_not_reach_is_marked_and_replaced_without_a_storm(
) -> void:
	var night := await _night(0, 1)
	_catcher.start()
	var shut_in := Vector3(0.0, 0.0, 28.0)
	var elsewhere := Vector3(0.0, 0.0, -43.0)
	_place(night, 1, Vector3(0.0, 0.0, -30.0))
	night.run(5)
	var brain := _goal_bot(night, 1)
	# The first errand is inside the booth, whose door is not bought; the second is on the field.
	brain.errands = [shut_in, elsewhere]
	var bot := _bot(night, 1)
	var seconds := 24
	for _i in seconds * TICKS_PER_SECOND:
		night.tick()
	_catcher.stop()
	assert_int(bot.legs.path.unreachable_marks).is_greater_equal(1)
	(
		assert_bool(
			bot.legs.path.is_blocked(shut_in, bot.now) or bot.legs.path.unreachable_marks > 1
		)
		. is_true()
	)
	# It took the other errand.
	assert_float(_flat(_where(night, 1), elsewhere)).is_less(2.0)
	# No storm: the marked goal is tried again every five seconds, not every tick, and the questions
	# stay inside the budget of three a second.
	assert_int(bot.legs.path.unreachable_marks).is_less_equal(seconds / 5 + 2)
	assert_int(bot.legs.path.queries).is_less_equal(seconds * 3)
	assert_int(bot.legs.path.queries).is_less_equal(12)
	assert_int(bot.legs.path.empty_answers).is_equal(0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- Scenario 20: the obstacles the lot is known for ---


func test_scenario_20_the_car_gaps_are_crossed_in_stride() -> void:
	var night := await _night(0, 1)
	var gaps := _car_gaps(night)
	assert_int(gaps.size()).is_greater_equal(3)
	for gap in gaps:
		var result := await _cross(night, 1, gap["from"], gap["to"], gap["middle"])
		_assert_crossed(result, "car gap at %s" % [gap["middle"]], 1.6)
	night.dispose()


## The gaps between parked cars that the walking mesh passes (it closes most of them to a 0.5 m
## agent: a way across is 12 m or more round), each as `{middle, from, to}`: the way across, 3.5 m
## either side of the middle of a pair of neighbours.
func _car_gaps(night: SeatedNight) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var map := night.world.map()
	for row in night.world.greybox.get_node("Field/Rows").get_children():
		var cars := row.get_children()
		for i in cars.size() - 1:
			var a: Vector3 = (cars[i] as Node3D).global_position
			var b: Vector3 = (cars[i + 1] as Node3D).global_position
			if _flat(a, b) > 5.0:
				continue
			var middle := (a + b) * 0.5
			var across := Vector3(-(b.z - a.z), 0.0, b.x - a.x).normalized()
			var from := middle - across * 3.5
			var to := middle + across * 3.5
			var way := NavigationServer3D.map_get_path(map, from, to, true)
			var length := 0.0
			for k in way.size() - 1:
				length += way[k].distance_to(way[k + 1])
			if not way.is_empty() and length < 7.6 and _flat(way[way.size() - 1], to) < 1.0:
				found.append({"middle": middle, "from": from, "to": to})
	return found


func test_scenario_20_the_booth_ramp_is_climbed() -> void:
	var night := await _night(0, 1, [&"door_concession", &"door_booth"])
	var result := await _cross(
		night, 1, Vector3(3.0, 0.0, 24.0), Vector3(0.0, 3.85, 27.0), Vector3(-4.8, 1.8, 27.0)
	)
	_assert_crossed(result, "booth ramp")
	assert_float(_where(night, 1).y).is_greater(3.0)
	night.dispose()


func test_scenario_20_the_generator_cage_is_crossed() -> void:
	var night := await _night(0, 1, [&"door_concession", &"door_yard"])
	var result := await _cross(
		night, 1, Vector3(31.0, 0.0, 18.0), Vector3(49.0, 0.0, 18.0), Vector3(40.0, 0.0, 18.0)
	)
	_assert_crossed(result, "generator cage", 4.0)
	night.dispose()


# --- The negative control: a gap the mesh does not know is shut ---


## A solid box in the way that the walking mesh was never baked with (a gap closed after the fact).
func _block(night: SeatedNight, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	night.world.add_child(body)
	body.global_position = at + Vector3(0.0, size.y * 0.5, 0.0)
	return body


func test_a_gap_the_mesh_does_not_know_is_shut_is_solved_by_the_ladder_without_a_teleport() -> void:
	var night := await _night(0, 1)
	var gap := _car_gaps(night)[0]
	var middle: Vector3 = gap["middle"]
	var across: Vector3 = (gap["to"] - gap["from"]).normalized()
	# Shut it: a box across the whole gap, higher than a jump, wide enough to touch the cars (its
	# thin side along the way through).
	_block(night, middle, Vector3(2.6, 2.2, 0.8)).rotate_y(atan2(-across.x, -across.z))
	await night.settle(3)
	_place(night, 1, gap["from"])
	night.run(5)
	var brain := _goal_bot(night, 1)
	# It wants to be across; failing that, back where it started.
	brain.errands = [gap["to"], gap["from"]]
	var bot := _bot(night, 1)
	var before := _where(night, 1)
	var biggest_step := 0.0
	var reached_back := false
	for _i in 14 * TICKS_PER_SECOND:
		night.tick()
		var now := _where(night, 1)
		biggest_step = maxf(biggest_step, before.distance_to(now))
		before = now
		if bot.legs.dropped.size() > 0 and _flat(now, gap["from"]) < 2.5:
			reached_back = true
			break
	# The ladder climbed to the fourth rung (dropped the goal), inside its six seconds, took the
	# other errand and never jumped in space: a body moves at most a sprint's step a tick.
	assert_int(bot.legs.stuck.depth_max).is_greater_equal(4)
	assert_float(bot.legs.stuck.longest()).is_less(SOLVED_WITHIN)
	assert_int(bot.legs.dropped.size()).is_greater_equal(1)
	assert_bool(reached_back).is_true()
	assert_float(biggest_step).is_less(0.2)
	night.dispose()


func test_a_bot_pushed_into_a_wall_ends_the_ladder_with_a_report() -> void:
	var night := await _night(0, 1)
	var gap := _car_gaps(night)[0]
	var middle: Vector3 = gap["middle"]
	_block(night, middle, Vector3(6.0, 2.2, 0.6))
	await night.settle(3)
	var across: Vector3 = (gap["to"] - gap["from"]).normalized()
	_place(night, 1, middle - across * 1.5)
	night.run(5)
	var brain := ReflexBrain.new()
	brain.heading = across
	_bot(night, 1).brain = brain
	var bot := _bot(night, 1)
	for _i in 12 * TICKS_PER_SECOND:
		night.tick()
		if bot.telemetry.has_event(&"bot_stuck"):
			break
	assert_bool(bot.telemetry.has_event(&"bot_stuck")).is_true()
	var reports := bot.telemetry.events.filter(
		func(e: Dictionary) -> bool: return e["name"] == &"bot_stuck"
	)
	var report: Dictionary = reports[0]
	assert_int(report["rungs"].size()).is_equal(6)
	assert_bool(report["position"] is Vector3).is_true()
	assert_int(report["decisions"].size()).is_between(1, BotLegs.REPORT_DECISIONS)
	assert_float(bot.legs.stuck.longest()).is_greater(7.0)
	night.dispose()


## A brain that only pushes the stick one way.
class ReflexBrain:
	extends BotBrain
	var heading := Vector3.ZERO

	func think(_beliefs: BotBeliefs, _state: ClientState) -> BotIntent:
		var intent := BotIntent.new()
		intent.reflex = heading
		return intent
