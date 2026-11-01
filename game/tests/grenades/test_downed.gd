extends GdUnitTestSuite
## A player who goes down with the pin out (#146): the grenade drops at their feet and the fuse
## keeps running. A downed player cannot throw it.

const HAND := Vector3(0.35, 1.45, -0.35)
const AIM := Vector3(0, 0, -1)
const FEET := Vector3(3, 0, 2)

var _night: GrenadesFixture
var _def: GrenadeDef


func before_test() -> void:
	_def = GrenadesFixture.def()
	_night = GrenadesFixture.night(2, GrenadesFixture.world_cast())
	_night.place({}, {1: FEET, 2: Vector3(-20, 0, 0)})


func _cook_then_down(seconds: float = 1.0) -> Array[Dictionary]:
	var events := _night.server.apply(GrenadeAction.cook(1, 1, FEET + HAND))
	events.append_array(_night.run_seconds(seconds))
	events.append_array(_night.rules.apply(RulesAction.set_downed(1, true)))
	return events


func test_a_downed_player_cannot_throw() -> void:
	_cook_then_down()
	var events := _night.server.apply(
		GrenadeAction.throw_grenade(1, 1, FEET + HAND, AIM, Vector3.ZERO, false)
	)
	assert_array(GrenadesFixture.of(events, &"grenade_thrown")).is_empty()
	var rejected := GrenadesFixture.of(events, &"throw_rejected")
	assert_array(rejected).has_size(1)
	assert_str(rejected[0]["reason"]).is_equal("player_downed")


func test_the_cooked_grenade_drops_at_the_feet_on_the_next_step() -> void:
	_cook_then_down(1.0)
	var events := _night.run(1)
	var dropped := GrenadesFixture.of(events, &"grenade_dropped")
	assert_array(dropped).has_size(1)
	assert_int(dropped[0]["thrower_id"]).is_equal(1)
	var at: Vector3 = dropped[0]["position"]
	assert_float(Vector2(at.x, at.z).distance_to(Vector2(FEET.x, FEET.z))).is_less_equal(0.01)
	assert_float(at.y).is_less_equal(_def.drop_height + 0.01)
	assert_float(dropped[0]["fuse_left"]).is_equal_approx(_def.fuse - 1.0, 0.03)
	assert_bool(_night.server.is_cooking(1)).is_false()
	assert_int(_night.server.grenades_in_flight()).is_equal(1)


func test_the_dropped_grenade_goes_off_when_its_fuse_runs_out_at_the_feet() -> void:
	_night.place({_night.zombies[0]: FEET + Vector3(1.0, 0, 0)})
	_cook_then_down(1.0)
	var events := _night.run_seconds(_def.fuse - 1.0 + 0.2)
	var blast := GrenadesFixture.of(events, &"grenade_exploded")
	assert_array(blast).has_size(1)
	assert_bool(blast[0]["in_hand"]).is_false()
	var centre: Vector3 = blast[0]["point"]
	var from_feet := Vector2(centre.x, centre.z).distance_to(Vector2(FEET.x, FEET.z))
	assert_float(from_feet).is_less_equal(0.1)
	assert_array(GrenadesFixture.of(events, &"blast_hit")).is_not_empty()
	var own := GrenadesFixture.of(events, &"player_blasted").filter(
		func(e: Dictionary) -> bool: return e["own"]
	)
	assert_array(own).has_size(1)
	assert_int(own[0]["player_id"]).is_equal(1)


func test_a_player_who_leaves_with_the_pin_out_drops_it_too() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, FEET + HAND))
	_night.rules.apply(RulesAction.remove_player(1))
	var events := _night.run(1)
	assert_array(GrenadesFixture.of(events, &"grenade_dropped")).has_size(1)
	assert_bool(_night.server.is_cooking(1)).is_false()


func test_a_revived_player_throws_again_with_a_fresh_pin() -> void:
	_cook_then_down()
	_night.run(1)
	_night.rules.apply(RulesAction.set_downed(1, false))
	var events := _night.server.apply(GrenadeAction.cook(1, 2, FEET + HAND))
	assert_array(GrenadesFixture.of(events, &"cook_started")).has_size(1)
	events = _night.server.apply(
		GrenadeAction.throw_grenade(1, 2, FEET + HAND, AIM, Vector3.ZERO, false)
	)
	assert_array(GrenadesFixture.of(events, &"grenade_thrown")).has_size(1)
