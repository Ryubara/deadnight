extends GdUnitTestSuite
## A grenade has weight and the dead are in its way (#680): a throw at a zombie stops within a metre
## of it, a throw on open ground goes a measured, shorter way than the old floaty one, the fuse is
## the fuse it was, and a client's copy ends where the server's grenade does.

const STEP := GrenadesFixture.STEP
## Where the zombie stands for the throws at one: 6 m ahead of the hand.
const ZOMBIE := Vector3(0, 0, -6)
const HAND := Vector3(0, 1.45, 0)
## The stop a throw at a zombie must make: within this of the zombie's feet (the issue says 1 m).
const NEAR := 1.0
## Where the old grenade (gravity 16, 15 m/s, 8 degrees, half bounce) lay after 2.65 s of a level
## overarm throw, and its longest lob, measured before this rework (the research page has the
## table).
const OLD_LEVEL_THROW := 22.3
const OLD_LONGEST_THROW := 25.7

var _def: GrenadeDef


func before_test() -> void:
	_def = GrenadesFixture.def()


func _targets(at: Vector3 = ZOMBIE, scale: float = 1.0) -> Dictionary:
	return {1: {"pos": at, "yaw": 0.0, "scale": scale}}


func _bodies(targets: Dictionary) -> Callable:
	return func(from: Vector3, to: Vector3) -> Dictionary:
		return ZombieBump.nearest(from, to, targets)


## Flies one throw from `hand` at `pitch_deg` until it rests or `seconds` pass; answers the state
## and whether a zombie stopped it.
func _fly(
	pitch_deg: float, targets: Dictionary, underarm := false, hand := HAND, seconds := 5.0
) -> Dictionary:
	var aim := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), 0.0, 0.0)) * Vector3.FORWARD
	var state := GrenadeState.new(
		1, 1, _def, hand, _def.launch_velocity(aim, underarm, Vector3.ZERO), INF
	)
	var cast := GrenadesFixture.world_cast()
	var bodies := _bodies(targets)
	var struck := false
	for _i in roundi(seconds / STEP):
		if state.at_rest:
			break
		state.step(STEP, cast, bodies)
		for contact in state.contacts:
			struck = struck or contact["zombie_id"] >= 0
	return {"state": state, "struck": struck}


func _away(state: GrenadeState, from: Vector3) -> float:
	return Vector2(state.position.x - from.x, state.position.z - from.z).length()


# --- The body ---


func test_a_segment_through_the_body_hits_its_side_with_a_level_normal() -> void:
	var hit := ZombieBump.nearest(Vector3(0, 1.0, 0), Vector3(0, 1.0, -10), _targets())
	assert_int(hit["zombie_id"]).is_equal(1)
	assert_float(hit["distance"]).is_equal_approx(6.0 - ZombieBump.RADIUS, 0.01)
	assert_vector(hit["normal"]).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * 0.02)
	assert_vector(hit["away"]).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * 0.02)


func test_a_segment_over_the_head_or_beside_the_body_misses() -> void:
	assert_dict(ZombieBump.nearest(Vector3(0, 2.4, 0), Vector3(0, 2.4, -10), _targets())).is_empty()
	(
		assert_dict(ZombieBump.nearest(Vector3(1.0, 1.0, 0), Vector3(1.0, 1.0, -10), _targets()))
		. is_empty()
	)


func test_a_segment_that_stops_short_misses() -> void:
	assert_dict(ZombieBump.nearest(Vector3(0, 1.0, 0), Vector3(0, 1.0, -4), _targets())).is_empty()


func test_the_nearest_of_two_zombies_is_the_one_hit() -> void:
	var targets := _targets()
	targets[2] = {"pos": Vector3(0, 0, -3), "yaw": 0.0, "scale": 1.0}
	var hit := ZombieBump.nearest(Vector3(0, 1.0, 0), Vector3(0, 1.0, -10), targets)
	assert_int(hit["zombie_id"]).is_equal(2)


func test_a_bigger_zombie_is_a_bigger_body() -> void:
	var side := Vector3(0.52, 1.0, 0)
	var small := ZombieBump.nearest(side, side + Vector3(0, 0, -10), _targets(ZOMBIE, 1.0))
	var big := ZombieBump.nearest(side, side + Vector3(0, 0, -10), _targets(ZOMBIE, 1.45))
	assert_dict(small).is_empty()
	assert_dict(big).is_not_empty()


func test_inside_a_body_and_going_out_hits_nothing_going_in_hits_at_once() -> void:
	var targets := _targets(Vector3(0, 0, -0.3))
	var from := Vector3(0, 1.0, 0)
	assert_dict(ZombieBump.nearest(from, from + Vector3(0, 0, 3), targets)).is_empty()
	var inward := ZombieBump.nearest(from, from + Vector3(0, 0, -3), targets)
	assert_dict(inward).is_not_empty()
	assert_float(inward["distance"]).is_equal(0.0)


# --- Weight ---


func test_a_throw_at_a_zombie_stops_within_a_metre_of_it() -> void:
	var struck := 0
	var worst := 0.0
	for pitch in range(-8, 24, 2):
		for sideways in [-0.3, -0.15, 0.0, 0.15, 0.3]:
			var flight := _fly(float(pitch), _targets(), false, HAND + Vector3(sideways, 0, 0))
			if not flight["struck"]:
				continue
			struck += 1
			var state: GrenadeState = flight["state"]
			worst = maxf(worst, _away(state, ZOMBIE))
			assert_bool(state.at_rest).override_failure_message("pitch %d" % pitch).is_true()
	assert_int(struck).is_greater(40)
	assert_float(worst).is_less(NEAR)


func test_a_toss_at_a_close_zombie_stops_within_a_metre_of_it() -> void:
	var near := Vector3(0, 0, -3.5)
	for pitch in [-8, 0, 8, 16]:
		var flight := _fly(float(pitch), _targets(near), true)
		assert_bool(flight["struck"]).override_failure_message("pitch %d" % pitch).is_true()
		assert_float(_away(flight["state"], near)).is_less(NEAR)


func test_a_throw_over_the_zombie_is_not_stopped_by_it() -> void:
	var flight := _fly(30.0, _targets())
	assert_bool(flight["struck"]).is_false()
	assert_float(_away(flight["state"], ZOMBIE)).is_greater(3.0)


func test_a_grenade_dropping_onto_a_head_slides_off_and_lies_by_the_zombie() -> void:
	var state := GrenadeState.new(1, 1, _def, Vector3(0.05, 3.0, -6), Vector3.ZERO, INF)
	var cast := GrenadesFixture.world_cast()
	var bodies := _bodies(_targets())
	var struck := false
	for _i in 300:
		state.step(STEP, cast, bodies)
		for contact in state.contacts:
			struck = struck or contact["zombie_id"] >= 0
	assert_bool(struck).is_true()
	assert_bool(state.at_rest).is_true()
	assert_float(_away(state, ZOMBIE)).is_less(NEAR)


func test_a_grenade_does_not_stop_at_a_zombie_it_is_not_given() -> void:
	var flight := _fly(0.0, {})
	assert_bool(flight["struck"]).is_false()
	assert_float(_away(flight["state"], Vector3.ZERO)).is_greater(8.0)


func test_a_level_throw_on_open_ground_goes_a_measured_shorter_way() -> void:
	var level := _fly(0.0, {}, false, HAND, 2.65)["state"] as GrenadeState
	var far := _away(level, Vector3.ZERO)
	assert_float(far).is_between(8.0, 11.0)
	assert_float(far).is_less(OLD_LEVEL_THROW * 0.5)


func test_the_longest_lob_is_much_shorter_than_the_old_one() -> void:
	var longest := 0.0
	for pitch in range(-10, 60, 5):
		var state := _fly(float(pitch), {}, false, HAND, 2.65)["state"] as GrenadeState
		longest = maxf(longest, _away(state, Vector3.ZERO))
	assert_float(longest).is_between(11.0, 15.0)
	assert_float(longest).is_less(OLD_LONGEST_THROW * 0.6)


func test_it_hardly_rolls_after_it_lands() -> void:
	var state := GrenadeState.new(
		1, 1, _def, HAND, _def.launch_velocity(Vector3.FORWARD, false, Vector3.ZERO), INF
	)
	var cast := GrenadesFixture.world_cast()
	var first_ground := -1.0
	for _i in 300:
		state.step(STEP, cast)
		if first_ground < 0.0 and state.bounces > 0:
			first_ground = _away(state, Vector3.ZERO)
		if state.at_rest:
			break
	assert_bool(state.at_rest).is_true()
	assert_float(_away(state, Vector3.ZERO) - first_ground).is_less(5.0)


func test_the_fuse_is_still_three_seconds_and_a_zombie_does_not_change_it() -> void:
	assert_float(_def.fuse).is_equal(3.0)
	var night := GrenadesFixture.night(1, GrenadesFixture.world_cast())
	night.place({1: ZOMBIE})
	var events := night.cook_and_throw(1, HAND, Vector3.FORWARD)
	events.append_array(night.run_seconds(_def.fuse - 0.1))
	assert_array(GrenadesFixture.of(events, &"grenade_struck")).is_not_empty()
	assert_array(GrenadesFixture.of(events, &"grenade_exploded")).is_empty()
	events = night.run_seconds(0.2)
	assert_array(GrenadesFixture.of(events, &"grenade_exploded")).has_size(1)


# --- The server and the client's copy ---


func test_the_server_says_which_zombie_stopped_the_grenade_and_where_it_is() -> void:
	var night := GrenadesFixture.night(1, GrenadesFixture.world_cast())
	night.place({1: ZOMBIE})
	var events := night.cook_and_throw(1, HAND, Vector3.FORWARD)
	events.append_array(night.run_seconds(1.0))
	var bounced := GrenadesFixture.of(events, &"grenade_bounced").filter(
		func(e: Dictionary) -> bool: return e["zombie_id"] == 1
	)
	assert_array(bounced).has_size(1)
	assert_bool(bounced[0]["wall"]).is_false()
	var struck := GrenadesFixture.of(events, &"grenade_struck")
	assert_array(struck).has_size(1)
	assert_int(struck[0]["zombie_id"]).is_equal(1)


func test_a_client_copy_given_the_struck_state_ends_where_the_server_grenade_does() -> void:
	var night := GrenadesFixture.night(1, GrenadesFixture.world_cast())
	night.place({1: ZOMBIE})
	var thrown := (
		GrenadesFixture.of(night.cook_and_throw(1, HAND, Vector3.FORWARD), &"grenade_thrown")[0]
	)
	var cast := GrenadesFixture.world_cast()
	var copy := GrenadeState.new(
		thrown["grenade_id"],
		thrown["thrower_id"],
		_def,
		thrown["position"],
		thrown["velocity"],
		thrown["fuse_left"]
	)
	var settled := false
	for _i in roundi(2.0 / STEP):
		var events := night.run(1)
		for event in events:
			if event["type"] == &"grenade_struck":
				copy = GrenadeState.from_dict(_def, event["state"])
				settled = true
		if settled:
			settled = false
		else:
			copy.step(STEP, cast)
	var server_side := night.server.grenade(1)
	assert_vector(copy.position).is_equal_approx(server_side.position, Vector3.ONE * 0.001)
	assert_bool(copy.at_rest).is_equal(server_side.at_rest)
	assert_float(Vector2(copy.position.x, copy.position.z).distance_to(Vector2(0, -6))).is_less(
		NEAR
	)
