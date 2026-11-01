extends GdUnitTestSuite
## The fuse, cooking, and what the server refuses.

const HAND := Vector3(0, 1.5, 0)
const AIM := Vector3(0, 0, -1)

var _night: GrenadesFixture


func before_test() -> void:
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast())


func _exploded(events: Array[Dictionary]) -> Array[Dictionary]:
	return GrenadesFixture.of(events, &"grenade_exploded")


func test_a_thrown_grenade_goes_off_when_the_fuse_runs_out() -> void:
	var events := _night.cook_and_throw(1, HAND, AIM)
	assert_array(_exploded(events)).is_empty()
	var def := GrenadesFixture.def()
	events = _night.run_seconds(def.fuse - 0.1)
	assert_array(_exploded(events)).is_empty()
	events = _night.run_seconds(0.2)
	assert_array(_exploded(events)).has_size(1)
	assert_bool(_exploded(events)[0]["in_hand"]).is_false()
	assert_int(_night.server.grenades_in_flight()).is_equal(0)


func test_cooking_spends_the_fuse_in_the_hand() -> void:
	var def := GrenadesFixture.def()
	_night.cook_and_throw(1, HAND, AIM, 2.0)
	var left := _night.server.grenade(1).fuse_left
	assert_float(left).is_equal_approx(def.fuse - 2.0, 0.03)
	var events := _night.run_seconds(1.1)
	assert_array(_exploded(events)).has_size(1)


func test_the_thrown_event_says_how_long_it_was_cooked() -> void:
	var events := _night.cook_and_throw(1, HAND, AIM, 1.0)
	var thrown := GrenadesFixture.of(events, &"grenade_thrown")
	assert_array(thrown).has_size(1)
	assert_float(thrown[0]["cooked"]).is_equal_approx(1.0, 0.03)
	assert_float(thrown[0]["fuse_left"]).is_equal_approx(2.0, 0.03)


func test_a_grenade_held_to_the_end_goes_off_in_the_hand() -> void:
	var def := GrenadesFixture.def()
	_night.server.apply(GrenadeAction.cook(1, 1, HAND))
	var events := _night.run_seconds(def.fuse - 0.2)
	assert_array(_exploded(events)).is_empty()
	events = _night.run_seconds(0.4)
	var blasts := _exploded(events)
	assert_array(blasts).has_size(1)
	assert_bool(blasts[0]["in_hand"]).is_true()
	assert_float(blasts[0]["point"].x).is_equal_approx(HAND.x, 0.001)
	assert_bool(_night.server.is_cooking(1)).is_false()


func test_the_hand_moves_while_cooking_and_the_blast_goes_off_where_it_is() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, HAND))
	_night.run_seconds(1.0)
	_night.place({}, {1: Vector3(4, 0, 0)})
	_night.server.apply(GrenadeAction.cook(1, 1, Vector3(4, 1.5, 0)))
	var events := _night.run_seconds(2.1)
	assert_float(_exploded(events)[0]["point"].x).is_equal_approx(4.0, 0.001)


func test_cooking_twice_does_not_restart_the_fuse() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, HAND))
	_night.run_seconds(1.0)
	var again := _night.server.apply(GrenadeAction.cook(1, 1, HAND))
	assert_array(again).is_empty()
	assert_float(_night.server.cooked_for(1)).is_equal_approx(1.0, 0.03)
	assert_int(_night.rules.grenades_of(1)).is_equal(_night.rules.tuning.explosives.refill_to - 1)


func test_the_pin_costs_one_grenade_of_the_players_count() -> void:
	var start := _night.rules.grenades_of(1)
	var events := _night.server.apply(GrenadeAction.cook(1, 1, HAND))
	assert_int(_night.rules.grenades_of(1)).is_equal(start - 1)
	var counts := GrenadesFixture.of(events, &"grenade_count_changed")
	assert_array(counts).has_size(1)
	assert_str(counts[0]["reason"]).is_equal("thrown")


func test_with_none_left_the_cook_is_refused_and_nothing_flies() -> void:
	var have := _night.rules.grenades_of(1)
	for i in have:
		_night.server.apply(GrenadeAction.cook(1, i, HAND))
		_night.server.apply(GrenadeAction.throw_grenade(1, i, HAND, AIM, Vector3.ZERO, false))
	var events := _night.server.apply(GrenadeAction.cook(1, 9, HAND))
	var refused := GrenadesFixture.of(events, &"cook_rejected")
	assert_array(refused).has_size(1)
	assert_str(refused[0]["reason"]).is_equal("no_grenades")
	assert_bool(_night.server.is_cooking(1)).is_false()
	assert_int(_night.server.grenades_in_flight()).is_equal(have)


func test_a_throw_without_a_cook_is_refused() -> void:
	var events := _night.server.apply(
		GrenadeAction.throw_grenade(1, 1, HAND, AIM, Vector3.ZERO, false)
	)
	assert_str(GrenadesFixture.of(events, &"throw_rejected")[0]["reason"]).is_equal("not_cooking")
	assert_int(_night.server.grenades_in_flight()).is_equal(0)


func test_a_nonsense_aim_is_refused_and_the_pin_stays_out() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, HAND))
	var events := _night.server.apply(
		GrenadeAction.throw_grenade(1, 1, HAND, Vector3(NAN, 0, 0), Vector3.ZERO, false)
	)
	assert_str(GrenadesFixture.of(events, &"throw_rejected")[0]["reason"]).is_equal("bad_aim")
	assert_bool(_night.server.is_cooking(1)).is_true()


func test_a_player_who_is_not_in_the_night_cannot_cook() -> void:
	var events := _night.server.apply(GrenadeAction.cook(42, 1, HAND))
	assert_array(GrenadesFixture.of(events, &"cook_rejected")).has_size(1)


func test_the_same_actions_give_the_same_events() -> void:
	var first := _replay()
	var second := _replay()
	assert_str(str(first)).is_equal(str(second))
	assert_int(first.size()).is_greater(3)


func _replay() -> Array[Dictionary]:
	var night := GrenadesFixture.night(1, GrenadesFixture.world_cast(-8.0))
	night.place({night.zombies[0]: Vector3(0, 0, -6)}, {1: Vector3(0, 0, 2)})
	var events := night.cook_and_throw(1, Vector3(0, 1.4, 0), Vector3(0.1, 0.2, -1), 0.7, false)
	events.append_array(night.run_seconds(4.0))
	return events
