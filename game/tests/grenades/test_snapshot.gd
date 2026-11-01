extends GdUnitTestSuite
## The grenade server's state (cooks, grenades in flight, the clock, the next id, where everyone
## stands) goes to bytes and back beside the rules' snapshot (#147). A server restored mid-night
## carries on as the original would.

const HAND := Vector3(0.35, 1.45, -0.35)
const AIM := Vector3(0, -1, 0.01)

var _night: GrenadesFixture
var _def: GrenadeDef


func before_test() -> void:
	_def = GrenadesFixture.def()
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast())
	_night.place({_night.zombies[0]: Vector3(1, 0, 0)}, {1: Vector3.ZERO})


## A second night rebuilt from the first one's snapshots: the rules first, then the grenades.
func _restored() -> GrenadesFixture:
	var copy := GrenadesFixture.new()
	copy.zombies = _night.zombies
	copy.rules = RulesFixture.make_rules(1, 1234)
	assert_str(copy.rules.from_bytes(_night.rules.to_bytes())).is_equal(&"")
	copy.server = GrenadeServer.new(_def, copy.rules, GrenadesFixture.world_cast())
	assert_str(copy.server.from_bytes(_night.server.to_bytes())).is_equal(&"")
	return copy


func test_a_grenade_in_flight_explodes_at_the_same_tick_and_point_after_a_restore() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, HAND))
	_night.run_seconds(2.4)
	_night.server.apply(GrenadeAction.throw_grenade(1, 1, HAND, AIM, Vector3.ZERO, true))
	_night.run_seconds(0.2)
	assert_int(_night.server.grenades_in_flight()).is_equal(1)
	var copy := _restored()
	assert_int(copy.server.grenades_in_flight()).is_equal(1)
	var original := _night.run_seconds(1.0)
	var carried_on := copy.run_seconds(1.0)
	var blast := GrenadesFixture.of(carried_on, &"grenade_exploded")
	assert_array(blast).has_size(1)
	assert_array(GrenadesFixture.of(carried_on, &"blast_hit")).is_not_empty()
	assert_array(carried_on).is_equal(original)
	assert_float(copy.server.now).is_equal(_night.server.now)


func test_a_cook_in_progress_goes_off_in_the_hand_at_the_same_tick_after_a_restore() -> void:
	_night.server.apply(GrenadeAction.cook(1, 7, HAND))
	_night.run_seconds(1.0)
	var copy := _restored()
	assert_bool(copy.server.is_cooking(1)).is_true()
	assert_float(copy.server.cooked_for(1)).is_equal_approx(_night.server.cooked_for(1), 0.0001)
	var original := _night.run_seconds(_def.fuse)
	var carried_on := copy.run_seconds(_def.fuse)
	assert_array(GrenadesFixture.of(carried_on, &"grenade_exploded")).has_size(1)
	assert_array(carried_on).is_equal(original)


func test_a_restored_cook_can_still_be_thrown() -> void:
	_night.server.apply(GrenadeAction.cook(1, 7, HAND))
	_night.run_seconds(0.5)
	var copy := _restored()
	var events := copy.server.apply(
		GrenadeAction.throw_grenade(1, 7, HAND, AIM, Vector3.ZERO, false)
	)
	var thrown := GrenadesFixture.of(events, &"grenade_thrown")
	assert_array(thrown).has_size(1)
	assert_float(thrown[0]["cooked"]).is_equal_approx(0.5, 0.03)


func test_the_next_grenade_id_carries_on() -> void:
	_night.cook_and_throw(1, HAND, AIM)
	var copy := _restored()
	var events := copy.server.apply(GrenadeAction.cook(1, 2, HAND))
	events = copy.server.apply(GrenadeAction.throw_grenade(1, 2, HAND, AIM, Vector3.ZERO, false))
	assert_int(GrenadesFixture.of(events, &"grenade_thrown")[0]["grenade_id"]).is_equal(2)


func test_the_snapshot_survives_bytes_and_the_wire() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, HAND))
	var from_wire := GrenadeServer.new(_def, _night.rules, GrenadesFixture.world_cast())
	assert_str(from_wire.from_wire(_night.server.to_wire())).is_equal(&"")
	assert_bool(from_wire.is_cooking(1)).is_true()
	assert_array(from_wire.to_bytes()).is_equal(_night.server.to_bytes())


func test_a_restore_replaces_what_the_server_had() -> void:
	var empty := _night.server.to_bytes()
	_night.server.apply(GrenadeAction.cook(1, 1, HAND))
	assert_str(_night.server.from_bytes(empty)).is_equal(&"")
	assert_bool(_night.server.is_cooking(1)).is_false()


func test_a_snapshot_that_does_not_fit_is_refused_and_changes_nothing() -> void:
	_night.server.apply(GrenadeAction.cook(1, 1, HAND))
	var before := _night.server.to_bytes()
	var good := _night.server.to_dict()
	var other_version := good.duplicate(true)
	other_version["version"] = GrenadeServer.SNAPSHOT_VERSION + 1
	assert_str(_night.server.from_dict(other_version)).is_equal(GameRules.RESTORE_BAD_VERSION)
	var other_grenade := good.duplicate(true)
	other_grenade["def_id"] = "not_a_frag"
	assert_str(_night.server.from_dict(other_grenade)).is_equal(GameRules.RESTORE_WRONG_TUNING)
	var missing := good.duplicate(true)
	missing.erase("grenades")
	assert_str(_night.server.from_dict(missing)).is_equal(GameRules.RESTORE_MALFORMED)
	var wrong_type := good.duplicate(true)
	wrong_type["now"] = "soon"
	assert_str(_night.server.from_dict(wrong_type)).is_equal(GameRules.RESTORE_MALFORMED)
	var broken_cook := good.duplicate(true)
	broken_cook["cooks"][1].erase("started")
	assert_str(_night.server.from_dict(broken_cook)).is_equal(GameRules.RESTORE_MALFORMED)
	assert_str(_night.server.from_bytes(PackedByteArray([1, 2, 3]))).is_equal(
		GameRules.RESTORE_MALFORMED
	)
	assert_array(_night.server.to_bytes()).is_equal(before)
