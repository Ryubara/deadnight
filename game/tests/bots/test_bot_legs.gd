# The legs (bots plan, phase 2) on small meshes: a goal is walked to along the path, a reflex
# heading as it is, a person who walks at the bot is given way, two bots that meet do not both step
# aside, the ladder jumps at a curated place the way it says, and the lot gives its loops and
# breaches to a bot's level.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0
const ME := 2

var _arena: NavArena


func after_test() -> void:
	if _arena != null:
		_arena.dispose()
		_arena = null


func _hall() -> BotLevel:
	var rows: Array[String] = []
	for _z in 8:
		rows.append("########")
	_arena = NavArena.from_rows(rows)
	await _arena.settle(get_tree())
	return _arena.level()


func _me(at: Vector3) -> Dictionary:
	return {"pos": at, "downed": false}


func _person(id: int, at: Vector3, velocity := Vector3.ZERO, bot := false) -> Dictionary:
	return {"id": id, "pos": at, "velocity": velocity, "bot": bot, "downed": false}


func test_a_goal_is_walked_to_along_the_path() -> void:
	var level := await _hall()
	var legs := BotLegs.new(level, RandomNumberGenerator.new())
	legs.seat = ME
	var intent := BotIntent.new()
	intent.goal = _arena.centre(6, 1)
	var here := _arena.centre(0, 6)
	var crew: Array[Dictionary] = []
	var now := 0.0
	for _i in 600:
		now += STEP
		legs.step(STEP, now, _me(here), intent, crew, INF)
		if legs.wish == Vector3.ZERO:
			break
		here += legs.wish * 4.8 * STEP
	assert_float(Vector2(here.x - intent.goal.x, here.z - intent.goal.z).length()).is_less(1.5)
	assert_int(legs.path.queries).is_less_equal(2)
	assert_bool(legs.stuck.stuck).is_false()


func test_a_walk_that_ends_short_of_its_goal_says_so_instead_of_standing_unseen() -> void:
	# A goal off the mesh by two metres is snapped onto it, the path ends there, and the bot is
	# "arrived" at the end of its path with the goal still beyond its radius: it must say so, or a
	# brain that waits for the goal to be near holds it there for good (the soak, a Roam bot that
	# stood 92 s two metres from its place).
	var level := await _hall()
	var legs := BotLegs.new(level, RandomNumberGenerator.new())
	legs.seat = ME
	var intent := BotIntent.new()
	intent.goal = _arena.centre(7, 3) + Vector3(3.0, 0.0, 0.0)
	intent.goal_radius = 1.0
	var here := _arena.centre(0, 3)
	var crew: Array[Dictionary] = []
	var now := 0.0
	for _i in 900:
		now += STEP
		legs.step(STEP, now, _me(here), intent, crew, INF)
		if legs.wish == Vector3.ZERO and now > 1.0:
			break
		here += legs.wish * 4.8 * STEP
	assert_float(Vector2(here.x - intent.goal.x, here.z - intent.goal.z).length()).is_greater(1.0)
	assert_bool(legs.stopped_short_of.is_equal_approx(intent.goal)).is_true()
	# A new goal it can reach clears it.
	intent.goal = _arena.centre(4, 3)
	for _i in 120:
		now += STEP
		legs.step(STEP, now, _me(here), intent, crew, INF)
		here += legs.wish * 4.8 * STEP
	assert_bool(legs.stopped_short_of.is_finite()).is_false()


func test_a_reflex_heading_is_walked_as_it_is() -> void:
	var level := await _hall()
	var legs := BotLegs.new(level, RandomNumberGenerator.new())
	var intent := BotIntent.new()
	intent.reflex = Vector3(0.0, 0.0, -1.0)
	var crew: Array[Dictionary] = []
	legs.step(STEP, 0.0, _me(_arena.centre(4, 6)), intent, crew, INF)
	assert_vector(legs.wish).is_equal_approx(Vector3(0.0, 0.0, -1.0), Vector3(0.001, 0.001, 0.001))
	assert_int(legs.path.queries).is_equal(0)


func test_a_person_walking_at_a_bot_is_given_way_at_the_last_moment() -> void:
	var level := await _hall()
	var legs := BotLegs.new(level, RandomNumberGenerator.new())
	legs.seat = ME
	var intent := BotIntent.new()
	var here := _arena.centre(4, 4)
	# A person 1 m off, walking at the bot at a run.
	var crew: Array[Dictionary] = [
		_person(1, here + Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 4.8))
	]
	legs.step(STEP, 0.0, _me(here), intent, crew, INF)
	assert_bool(legs.wish != Vector3.ZERO).is_true()
	# Away from them, not into them.
	assert_float(legs.wish.z).is_greater(-0.2)
	assert_float(legs.yielded_seconds).is_greater(0.0)


func test_a_zombie_that_stands_in_the_way_is_walked_round_not_into() -> void:
	# The dead stop a body (#914): a bot whose way runs through one bends round it.
	var level := await _hall()
	var legs := BotLegs.new(level, RandomNumberGenerator.new())
	legs.seat = ME
	var intent := BotIntent.new()
	intent.goal = _arena.centre(6, 3)
	var here := _arena.centre(0, 3)
	var crew: Array[Dictionary] = []
	var dead: Array[Vector3] = [here + Vector3(1.8, 0.0, 0.0)]
	legs.step(STEP, STEP, _me(here), intent, crew, 1.8, true, dead)
	assert_float(absf(legs.wish.z)).is_greater(0.3)
	# One beside the way, or behind, changes nothing.
	var beside: Array[Vector3] = [here + Vector3(1.0, 0.0, 2.5)]
	legs.step(STEP, 2.0 * STEP, _me(here), intent, crew, 2.5, true, beside)
	assert_float(absf(legs.wish.z)).is_less(0.15)
	var behind: Array[Vector3] = [here + Vector3(-1.0, 0.0, 0.0)]
	legs.step(STEP, 3.0 * STEP, _me(here), intent, crew, 1.0, true, behind)
	assert_float(absf(legs.wish.z)).is_less(0.15)


func test_a_person_far_off_or_walking_away_is_not_given_way() -> void:
	var level := await _hall()
	var legs := BotLegs.new(level, RandomNumberGenerator.new())
	legs.seat = ME
	var intent := BotIntent.new()
	var here := _arena.centre(4, 4)
	var crew: Array[Dictionary] = [
		_person(1, here + Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -4.8)),
		_person(3, here + Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -4.8)),
	]
	legs.step(STEP, 0.0, _me(here), intent, crew, INF)
	assert_vector(legs.wish).is_equal(Vector3.ZERO)
	assert_float(legs.yielded_seconds).is_equal(0.0)


func test_of_two_bots_that_meet_only_the_higher_seat_goes_round() -> void:
	var level := await _hall()
	var middle := _arena.centre(4, 4)
	var low := BotLegs.new(level, RandomNumberGenerator.new())
	low.seat = 2
	var high := BotLegs.new(level, RandomNumberGenerator.new())
	high.seat = 3
	var intent_low := BotIntent.new()
	intent_low.reflex = Vector3(1.0, 0.0, 0.0)
	var intent_high := BotIntent.new()
	intent_high.reflex = Vector3(-1.0, 0.0, 0.0)
	var low_crew: Array[Dictionary] = [
		_person(3, middle + Vector3(1.5, 0.0, 0.0), Vector3(-4.8, 0.0, 0.0), true)
	]
	var high_crew: Array[Dictionary] = [_person(2, middle, Vector3(4.8, 0.0, 0.0), true)]
	low.step(STEP, 0.0, _me(middle), intent_low, low_crew, INF)
	high.step(STEP, 0.0, _me(middle + Vector3(1.5, 0.0, 0.0)), intent_high, high_crew, INF)
	# The lower seat keeps straight on; the higher turns off to a side.
	assert_vector(low.wish).is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3(0.01, 0.01, 0.01))
	assert_float(absf(high.wish.z)).is_greater(0.3)


func test_a_bot_that_turns_right_round_is_not_judged_while_it_swings() -> void:
	var level := await _hall()
	var legs := BotLegs.new(level, RandomNumberGenerator.new())
	var intent := BotIntent.new()
	var crew: Array[Dictionary] = []
	var here := _arena.centre(4, 4)
	# A run one way, then the other way with the body still carrying on the old one (it is braking
	# and turning): the swing is not stuck.
	intent.reflex = Vector3(1.0, 0.0, 0.0)
	var now := 0.0
	for _i in 15:
		now += STEP
		legs.step(STEP, now, _me(here + Vector3(0.1 * float(_i), 0.0, 0.0)), intent, crew, INF)
	intent.reflex = Vector3(-1.0, 0.0, 0.0)
	for _i in 40:
		now += STEP
		legs.step(STEP, now, _me(here + Vector3(1.5, 0.0, 0.0)), intent, crew, INF)
	assert_bool(legs.stuck.stuck).is_false()


func test_the_jump_rung_uses_a_curated_place_the_way_it_says() -> void:
	var level := await _hall()
	var from := _arena.centre(4, 4)
	level.links = [BotLink.new(from, from + Vector3(0.0, 1.0, -2.0))]
	var legs := BotLegs.new(level, RandomNumberGenerator.new())
	legs.seat = ME
	var intent := BotIntent.new()
	intent.reflex = Vector3(1.0, 0.0, 0.0)
	var crew: Array[Dictionary] = []
	var now := 0.0
	var jumped_north := false
	# Pressed against a wall that never gives: the ladder reaches the third rung at the link.
	for _i in 600:
		now += STEP
		legs.step(STEP, now, _me(from), intent, crew, INF)
		if legs.stuck.rung == 3 and legs.wish.z < -0.9:
			jumped_north = true
			break
	assert_bool(jumped_north).is_true()


func test_the_lot_gives_its_loops_and_breaches_to_a_bots_level() -> void:
	var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), 5)
	assert_int(night.level.breaches.size()).is_equal(6)
	assert_int(night.level.loops.size()).is_equal(2)
	for ring in night.level.loops:
		assert_int(ring.size()).is_equal(4)
	# The first ring is round the generator cage (x 36 to 44, z 15 to 21) with a margin.
	var cage := night.level.loops[0]
	assert_float(cage[0].x).is_equal_approx(36.0 - LotBotData.LOOP_MARGIN, 0.5)
	assert_float(cage[2].z).is_equal_approx(21.0 + LotBotData.LOOP_MARGIN, 0.5)
	assert_array(night.level.links).is_empty()
	night.dispose()
