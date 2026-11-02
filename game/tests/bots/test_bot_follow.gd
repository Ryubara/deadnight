# The follow-position scorer (bots plan, phase 2), after Ellie in The Last of Us: where a bot stands
# to stay with the people, rated by distance against a band, the leader's facing, the side of the
# dead, the other bots, light, the breaches and the gaps. Pure arithmetic on positions plus a few
# rays on a small mesh (`NavArena`).
extends GdUnitTestSuite

var _arena: NavArena


func after_test() -> void:
	if _arena != null:
		_arena.dispose()
		_arena = null


## A hall of ten by ten squares (20 m by 20 m), lit.
func _hall() -> BotLevel:
	var rows: Array[String] = []
	for _z in 10:
		rows.append("##########")
	_arena = NavArena.from_rows(rows)
	await _arena.settle(get_tree())
	return _arena.level()


func _person(at: Vector3, facing := 0.0, downed := false, health := 100.0) -> Dictionary:
	return {"pos": at, "facing": facing, "downed": downed, "health": health}


func _context(
	here: Vector3,
	leader: Dictionary,
	others: Array[Vector3] = [],
	threat := Vector3.INF,
	band := BotFollow.CALM_BAND
) -> Dictionary:
	return {
		"here": here,
		"anchor": leader["pos"],
		"leader": leader["pos"],
		"forward": Vector3(-sin(leader["facing"]), 0.0, -cos(leader["facing"])),
		"others": others,
		"threat": threat,
		"band": band,
	}


func test_the_anchor_leans_toward_the_one_who_needs_help() -> void:
	var people: Array[Dictionary] = [
		_person(Vector3(0.0, 0.0, 0.0)),
		_person(Vector3(10.0, 0.0, 0.0), 0.0, true),
	]
	var anchor := BotFollow.anchor_of(people)
	# A downed one counts three: the anchor sits at three quarters of the way to them.
	assert_float(anchor.x).is_equal_approx(7.5, 0.3)
	assert_vector(BotFollow.anchor_of([])).is_equal(Vector3.INF)


func test_a_place_inside_the_band_beats_one_outside() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var leader := _person(_arena.centre(5, 5))
	var context := _context(_arena.centre(2, 2), leader)
	var near := follow.rate(leader["pos"] + Vector3(5.0, 0.0, 5.0).normalized() * 6.0, context)
	var close := follow.rate(leader["pos"] + Vector3(5.0, 0.0, 5.0).normalized() * 1.0, context)
	var far := follow.rate(leader["pos"] + Vector3(5.0, 0.0, 5.0).normalized() * 15.0, context)
	assert_float(near).is_greater(close)
	assert_float(near).is_greater(far)


func test_behind_the_leader_beats_in_front_of_them() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	# The leader faces north (-z, yaw 0).
	var leader := _person(_arena.centre(5, 5), 0.0)
	var context := _context(_arena.centre(5, 5) + Vector3(8.0, 0.0, 0.0), leader)
	var in_front := follow.rate(leader["pos"] + Vector3(0.0, 0.0, -6.0), context)
	var beside := follow.rate(leader["pos"] + Vector3(6.0, 0.0, 0.0), context)
	var behind := follow.rate(leader["pos"] + Vector3(0.0, 0.0, 6.0), context)
	assert_float(behind).is_greater(in_front)
	assert_float(beside).is_greater(in_front)


func test_the_dead_make_the_far_side_of_the_leader_worse() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var leader := _person(_arena.centre(5, 5), 1.0)
	var threat: Vector3 = leader["pos"] + Vector3(-8.0, 0.0, 0.0)
	var context := _context(leader["pos"], leader, [], threat)
	# One place toward the dead, one away from them, the same distance from the leader and the same
	# angle to its facing.
	var toward := follow.rate(leader["pos"] + Vector3(-1.0, 0.0, 0.2).normalized() * 6.0, context)
	var away := follow.rate(leader["pos"] + Vector3(1.0, 0.0, 0.2).normalized() * 6.0, context)
	assert_float(away).is_greater(toward)


func test_a_place_in_the_leaders_line_to_the_dead_is_worse() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var leader := _person(_arena.centre(5, 5), 3.0)
	var threat: Vector3 = leader["pos"] + Vector3(0.0, 0.0, -9.0)
	var context := _context(leader["pos"], leader, [], threat)
	var in_line := follow.rate(leader["pos"] + Vector3(0.5, 0.0, -5.0), context)
	var off_line := follow.rate(leader["pos"] + Vector3(5.0, 0.0, 0.5), context)
	assert_float(off_line).is_greater(in_line)


func test_two_bots_do_not_take_the_same_place() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var leader := _person(_arena.centre(5, 5), 0.0)
	var spot: Vector3 = leader["pos"] + Vector3(0.0, 0.0, 6.0)
	var alone := follow.rate(spot, _context(spot, leader))
	var crowded := follow.rate(spot, _context(spot, leader, [spot + Vector3(1.0, 0.0, 0.0)]))
	assert_float(crowded).is_less(alone - 1.0)


func test_a_place_near_a_breach_is_worse() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var leader := _person(_arena.centre(5, 5), 0.0)
	var spot: Vector3 = leader["pos"] + Vector3(0.0, 0.0, 6.0)
	var before := follow.rate(spot, _context(spot, leader))
	level.breaches = [spot + Vector3(1.0, 0.0, 1.0)]
	var after := follow.rate(spot, _context(spot, leader))
	assert_float(after).is_less(before - 1.0)


func test_a_bot_that_is_well_placed_stays() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var leader := _person(_arena.centre(5, 5), 0.0)
	var people: Array[Dictionary] = [leader]
	var here: Vector3 = leader["pos"] + Vector3(2.0, 0.0, 6.0)
	var no_bots: Array[Vector3] = []
	var no_dead: Array[Vector3] = []
	assert_vector(follow.plan(here, people, no_bots, no_dead, false, Vector3.INF)).is_equal(
		Vector3.INF
	)
	# Too far to be well placed: it is given a place, inside the band, behind or beside.
	var far: Vector3 = leader["pos"] + Vector3(-10.5, 0.0, 0.5)
	var spot := follow.plan(far, people, no_bots, no_dead, false, Vector3.INF)
	assert_bool(spot != Vector3.INF).is_true()
	var apart := Vector2(spot.x - leader["pos"].x, spot.z - leader["pos"].z).length()
	assert_float(apart).is_between(BotFollow.CALM_BAND.x - 0.5, BotFollow.CALM_BAND.y + 0.5)


func test_nobody_to_follow_gives_no_place() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var no_people: Array[Dictionary] = []
	var none: Array[Vector3] = []
	assert_vector(follow.plan(Vector3.ZERO, no_people, none, none, false, Vector3.INF)).is_equal(
		Vector3.INF
	)


func test_four_bots_take_four_different_places() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var leader := _person(_arena.centre(5, 5), 0.0)
	var people: Array[Dictionary] = [leader]
	var taken: Array[Vector3] = []
	var none: Array[Vector3] = []
	for i in 4:
		var here: Vector3 = leader["pos"] + Vector3(-9.0 + float(i), 0.0, -8.0)
		var spot := follow.plan(here, people, taken, none, false, Vector3.INF)
		assert_bool(spot != Vector3.INF).is_true()
		for other in taken:
			assert_float(Vector2(spot.x - other.x, spot.z - other.z).length()).is_greater(
				BotFollow.SPACING * 0.7
			)
		taken.append(spot)


func test_a_place_held_is_kept_against_one_a_little_better() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var leader := _person(_arena.centre(5, 5), 0.0)
	var people: Array[Dictionary] = [leader]
	var none: Array[Vector3] = []
	var far: Vector3 = leader["pos"] + Vector3(-10.5, 0.0, -0.5)
	var first := follow.plan(far, people, none, none, false, Vector3.INF)
	assert_bool(first != Vector3.INF).is_true()
	var second := follow.plan(far, people, none, none, false, first)
	assert_vector(second).is_equal(first)


func test_a_place_it_could_not_reach_is_not_chosen_again() -> void:
	var level := await _hall()
	var follow := BotFollow.new(level)
	var leader := _person(_arena.centre(5, 5), 0.0)
	var people: Array[Dictionary] = [leader]
	var none: Array[Vector3] = []
	var far: Vector3 = leader["pos"] + Vector3(-10.5, 0.0, -0.5)
	var first := follow.plan(far, people, none, none, false, Vector3.INF)
	assert_bool(first != Vector3.INF).is_true()
	var avoid := func(spot: Vector3) -> bool:
		return Vector2(spot.x - first.x, spot.z - first.z).length() < 2.5
	var second := follow.plan(far, people, none, none, false, Vector3.INF, avoid)
	assert_bool(second != Vector3.INF).is_true()
	assert_float(Vector2(second.x - first.x, second.z - first.z).length()).is_greater_equal(2.5)


func test_it_never_picks_a_place_inside_a_gap() -> void:
	# A hall with a corridor leading off it: the corridor is two metres wide, a gap.
	var rows: Array[String] = [
		"########",
		"########",
		"########",
		"########",
		"########",
		"########",
		"#       ",
		"#       ",
	]
	_arena = NavArena.from_rows(rows)
	await _arena.settle(get_tree())
	var level := _arena.level()
	var follow := BotFollow.new(level)
	# The leader at the mouth of the corridor, near the band, so places in it are candidates.
	var leader := _person(_arena.centre(0, 5), 0.0)
	var people: Array[Dictionary] = [leader]
	var none: Array[Vector3] = []
	for start in [Vector3(14.0, 0.0, 2.0), Vector3(12.0, 0.0, 10.0), Vector3(8.0, 0.0, 14.0)]:
		var spot := follow.plan(start, people, none, none, false, Vector3.INF)
		if spot != Vector3.INF:
			assert_bool(level.in_passage(spot)).is_false()
