extends GdUnitTestSuite
## The server owns where a grenade leaves from and how fast: a client's hand and velocity are only
## hints, kept within reach of where the server has the player, and never trusted when not finite.
## Each of the reviewer's probes on #131 (#145) is a test here.

const AIM := Vector3(0, 0, -1)
## What a hand looks like on the real player (see the grenade range): beside and above the feet.
const REAL_HAND := Vector3(0.35, 1.45, -0.35)
## The slack allowed on a distance, metres.
const NEAR := 0.001

var _night: GrenadesFixture
var _def: GrenadeDef


func before_test() -> void:
	_def = GrenadesFixture.def()
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast())


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> StringName: return e["type"])


func test_a_hand_far_from_the_player_cannot_move_the_blast() -> void:
	var far := _night.zombies[0]
	_night.place({far: Vector3(0, 0, 60)}, {1: Vector3.ZERO})
	var hand := Vector3(0, 1, 60)
	var events := _night.server.apply(GrenadeAction.cook(1, 1, hand))
	events.append_array(
		_night.server.apply(
			GrenadeAction.throw_grenade(
				1, 1, hand, Vector3(0, -1, 0.01).normalized(), Vector3.ZERO, true
			)
		)
	)
	events.append_array(_night.run(400))
	var thrown := GrenadesFixture.of(events, &"grenade_thrown")
	assert_array(thrown).has_size(1)
	var anchor := Vector3.UP * _def.hand_height
	var from_anchor := (thrown[0]["position"] as Vector3).distance_to(anchor)
	assert_float(from_anchor).is_less_equal(_def.hand_reach + NEAR)
	assert_array(GrenadesFixture.of(events, &"blast_hit")).is_empty()
	assert_array(GrenadesFixture.of(events, &"zombie_removed")).is_empty()
	assert_bool(_night.rules.has_zombie(far)).is_true()


func test_a_hand_beside_the_player_is_taken_as_it_is() -> void:
	var events := _night.cook_and_throw(1, REAL_HAND, AIM)
	var thrown := GrenadesFixture.of(events, &"grenade_thrown")
	assert_array(thrown).has_size(1)
	assert_vector(thrown[0]["position"]).is_equal_approx(REAL_HAND, Vector3.ONE * NEAR)


func test_the_hand_goes_with_the_player_not_with_where_the_client_says() -> void:
	_night.place({}, {1: Vector3(10, 0, 5)})
	var events := _night.server.apply(GrenadeAction.cook(1, 1, Vector3(10, 1.45, 5)))
	assert_array(GrenadesFixture.of(events, &"cook_started")).has_size(1)
	events = _night.server.apply(GrenadeAction.cook(1, 1, Vector3(0, 1.45, 0)))
	events.append_array(_night.run_seconds(_def.fuse + 0.1))
	var blast := GrenadesFixture.of(events, &"grenade_exploded")
	assert_array(blast).has_size(1)
	var centre: Vector3 = blast[0]["point"]
	var from_player := Vector2(centre.x, centre.z).distance_to(Vector2(10, 5))
	assert_float(from_player).is_less_equal(_def.hand_reach + NEAR)


func test_a_cooked_grenade_goes_off_where_the_player_has_walked_to() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, REAL_HAND))
	_night.run_seconds(1.0)
	_night.place({}, {1: Vector3(6, 0, 0)})
	var events := _night.run_seconds(_def.fuse)
	var blast := GrenadesFixture.of(events, &"grenade_exploded")
	assert_array(blast).has_size(1)
	assert_bool(blast[0]["in_hand"]).is_true()
	assert_float((blast[0]["point"] as Vector3).x).is_equal_approx(6.0 + REAL_HAND.x, 0.01)


func test_a_huge_velocity_is_clamped_to_the_players_own_top_speed() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, REAL_HAND))
	var events := _night.server.apply(
		GrenadeAction.throw_grenade(1, 1, REAL_HAND, AIM, Vector3(0, 0, -2000), false)
	)
	var thrown := GrenadesFixture.of(events, &"grenade_thrown")
	assert_array(thrown).has_size(1)
	var ceiling := _def.over_speed + _def.max_carrier_speed * _def.inherit_velocity
	assert_float((thrown[0]["velocity"] as Vector3).length()).is_less_equal(ceiling + NEAR)


func test_a_player_running_at_top_speed_still_adds_their_speed() -> void:
	var run := Vector3(0, 0, -_def.max_carrier_speed)
	_night.server.apply(GrenadeAction.cook(1, 1, REAL_HAND))
	var events := _night.server.apply(GrenadeAction.throw_grenade(1, 1, REAL_HAND, AIM, run, false))
	var launch := _def.launch_velocity(AIM, false, run)
	var thrown := GrenadesFixture.of(events, &"grenade_thrown")
	assert_vector(thrown[0]["velocity"]).is_equal_approx(launch, Vector3.ONE * NEAR)


func test_a_velocity_that_is_not_a_number_is_refused_and_the_grenade_stays_in_the_hand() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, REAL_HAND))
	for bad: Vector3 in [Vector3(NAN, 0, 0), Vector3(0, INF, 0), Vector3(0, 0, -INF)]:
		var events := _night.server.apply(
			GrenadeAction.throw_grenade(1, 1, REAL_HAND, AIM, bad, false)
		)
		assert_array(_types(events)).is_equal([&"throw_rejected"])
		assert_str(events[0]["reason"]).is_equal("bad_velocity")
	assert_bool(_night.server.is_cooking(1)).is_true()
	assert_int(_night.server.grenades_in_flight()).is_equal(0)


func test_a_hand_that_is_not_a_number_is_refused_and_costs_no_grenade() -> void:
	_night.place({_night.zombies[0]: Vector3(0, 0, 2)}, {1: Vector3.ZERO})
	var before := _night.rules.grenades_of(1)
	var events := _night.server.apply(GrenadeAction.cook(1, 1, Vector3(NAN, 0, 0)))
	events.append_array(_night.run(200))
	assert_array(_types(events)).is_equal([&"cook_rejected"])
	assert_str(events[0]["reason"]).is_equal("bad_hand")
	assert_bool(_night.server.is_cooking(1)).is_false()
	assert_int(_night.rules.grenades_of(1)).is_equal(before)


func test_a_hand_that_is_not_a_number_cannot_throw_or_move_a_cook() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, REAL_HAND))
	var lost := Vector3(INF, 0, 0)
	var thrown := _night.server.apply(
		GrenadeAction.throw_grenade(1, 1, lost, AIM, Vector3.ZERO, false)
	)
	assert_str(thrown[0]["reason"]).is_equal("bad_hand")
	var moved := _night.server.apply(GrenadeAction.cook(1, 1, Vector3(0, NAN, 0)))
	assert_str(moved[0]["reason"]).is_equal("bad_hand")
	assert_bool(_night.server.is_cooking(1)).is_true()
	assert_int(_night.server.grenades_in_flight()).is_equal(0)


func test_a_player_the_server_has_not_placed_cannot_cook() -> void:
	_night = GrenadesFixture.night(2, GrenadesFixture.world_cast())
	_night.place({}, {1: Vector3.ZERO})
	var events := _night.server.apply(GrenadeAction.cook(2, 1, REAL_HAND))
	assert_array(_types(events)).is_equal([&"cook_rejected"])
	assert_str(events[0]["reason"]).is_equal("unknown_player")


func test_a_blast_does_no_damage_at_a_distance_that_is_not_a_number() -> void:
	assert_float(_def.falloff(NAN)).is_equal(0.0)
	assert_float(_def.falloff(INF)).is_equal(0.0)
	var centre := Vector3(0, 1, 0)
	var broken := BlastModel.against_zombie(_def, centre, Vector3(NAN, 0, 0), 0.0, Callable())
	assert_float(broken["damage"]).is_equal(0.0)
	var point := BlastModel.against_point(_def, centre, Vector3(NAN, 1, 0), Callable())
	assert_float(point["damage"]).is_equal(0.0)
