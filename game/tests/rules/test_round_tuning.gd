extends GdUnitTestSuite
## The scaling curves: zombies, health, speed, spawn pacing, the cap on the living, the dark.

var _t: RoundTuning


func before_test() -> void:
	_t = RulesFixture.tuning().rounds


func test_zombie_count_starts_at_six_for_one_player() -> void:
	assert_int(_t.zombies_for_round(1, 1)).is_equal(6)


func test_zombie_count_matches_the_documented_table() -> void:
	# 6 + 2.4 (r-1) + 0.12 (r-1)^2, rounded.
	assert_int(_t.zombies_for_round(5, 1)).is_equal(18)
	assert_int(_t.zombies_for_round(10, 1)).is_equal(37)
	assert_int(_t.zombies_for_round(20, 1)).is_equal(95)


func test_zombie_count_only_grows() -> void:
	var previous := 0
	for round_number in range(1, 41):
		var count := _t.zombies_for_round(round_number, 1)
		assert_int(count).is_greater(previous)
		previous = count


func test_more_players_bring_more_zombies_but_not_proportionally() -> void:
	var solo := _t.zombies_for_round(6, 1)
	var duo := _t.zombies_for_round(6, 2)
	var four := _t.zombies_for_round(6, 4)
	assert_int(duo).is_greater(solo)
	assert_int(four).is_greater(duo)
	# Per player the load falls as the group grows: a crowd is safer than the same people alone.
	assert_float(float(four) / 4.0).is_less(float(solo))


func test_health_climbs_straight_to_the_knee_then_compounds() -> void:
	assert_float(_t.health_for_round(1)).is_equal(60.0)
	assert_float(_t.health_for_round(8)).is_equal(186.0)
	assert_float(_t.health_for_round(9)).is_equal_approx(186.0 * 1.07, 0.001)
	assert_float(_t.health_for_round(18)).is_equal_approx(186.0 * pow(1.07, 10.0), 0.01)


func test_health_never_falls() -> void:
	var previous := 0.0
	for round_number in range(1, 41):
		var health := _t.health_for_round(round_number)
		assert_float(health).is_greater(previous)
		previous = health


func test_walking_speed_rises_and_stops_at_the_cap() -> void:
	assert_float(_t.speed_for_round(1)).is_equal_approx(0.9, 0.0001)
	assert_float(_t.speed_for_round(11)).is_equal_approx(1.9, 0.0001)
	assert_float(_t.speed_for_round(500)).is_equal(_t.speed_cap)


func test_sprinters_start_at_their_round_and_stop_growing() -> void:
	assert_float(_t.sprinter_chance(3)).is_equal(0.0)
	assert_float(_t.sprinter_chance(4)).is_equal_approx(0.07, 0.0001)
	assert_float(_t.sprinter_chance(5)).is_equal_approx(0.14, 0.0001)
	assert_float(_t.sprinter_chance(100)).is_equal(0.5)


func test_no_zombie_outruns_the_cap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for round_number in [1, 6, 15, 60]:
		for _i in 300:
			var speed := _t.roll_speed(round_number, rng)
			assert_float(speed).is_less_equal(_t.speed_cap)
			assert_float(speed).is_greater(0.0)


func test_rolled_speeds_follow_the_seed() -> void:
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 7
	second.seed = 7
	for _i in 20:
		assert_float(_t.roll_speed(9, first)).is_equal(_t.roll_speed(9, second))


func test_lit_ground_slows_the_dead() -> void:
	assert_float(_t.speed_on_ground(2.0, false)).is_equal(2.0)
	assert_float(_t.speed_on_ground(2.0, true)).is_equal_approx(1.2, 0.0001)


func test_spawns_get_faster_then_hold_at_the_floor() -> void:
	assert_float(_t.spawn_interval(1, 1)).is_equal_approx(2.4, 0.0001)
	assert_float(_t.spawn_interval(2, 1)).is_equal_approx(2.4 * 0.92, 0.0001)
	assert_float(_t.spawn_interval(80, 1)).is_equal(0.5)
	assert_float(_t.spawn_interval(1, 3)).is_less(_t.spawn_interval(1, 1))


func test_the_living_cap_rises_then_holds_and_grows_with_players() -> void:
	assert_int(_t.alive_cap(1, 1)).is_equal(10)
	assert_int(_t.alive_cap(50, 1)).is_equal(28)
	assert_int(_t.alive_cap(1, 3)).is_equal(22)


func test_the_night_gets_darker_to_a_floor() -> void:
	assert_float(_t.ambient_for_round(1)).is_equal_approx(0.6, 0.0001)
	assert_float(_t.ambient_for_round(5)).is_less(_t.ambient_for_round(2))
	assert_float(_t.ambient_for_round(200)).is_equal(_t.ambient_min)


func test_the_shipped_table_is_consistent() -> void:
	var economy := RulesFixture.tuning().economy
	var seen: Dictionary = {}
	for item in economy.items:
		assert_bool(seen.has(item.id)).is_false()
		seen[item.id] = true
		assert_int(item.price).is_greater(0)
	for item in economy.items:
		if item.requires != &"":
			assert_object(economy.item(item.requires)).is_not_null()
		if item.kind == ShopItem.Kind.FUEL:
			assert_float(item.amount).is_greater(0.0)
		if item.kind == ShopItem.Kind.CRANE:
			assert_array(item.pool).is_not_empty()
			assert_int(item.pool_weights.size()).is_equal(item.pool.size())
