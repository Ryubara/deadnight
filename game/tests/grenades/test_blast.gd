extends GdUnitTestSuite
## What a blast does to bodies: falloff from the centre, cover, knockback, and who is hurt.

var _def: GrenadeDef
var _night: GrenadesFixture


func before_test() -> void:
	_def = GrenadesFixture.def()


func _blast_at(point: Vector3, zombie_at: Vector3, ray: Callable = Callable()) -> Dictionary:
	return BlastModel.against_zombie(_def, point, zombie_at, 0.0, ray)


func test_the_part_weights_are_one_whole_and_match_the_hit_zones() -> void:
	var total := 0.0
	for weight in BlastModel.PART_WEIGHTS:
		total += weight
	assert_float(total).is_equal_approx(1.0, 0.0001)
	assert_int(BlastModel.PART_WEIGHTS.size()).is_equal(Hitbox.ZONES.size())
	for index in BlastModel.LEG_PARTS:
		assert_float(Hitbox.ZONES[index]["b"].y).is_less(0.7)


func test_damage_is_full_in_the_core_and_zero_at_the_edge() -> void:
	assert_float(_def.falloff(0.0)).is_equal(1.0)
	assert_float(_def.falloff(_def.core_radius)).is_equal(1.0)
	assert_float(_def.falloff(_def.blast_radius)).is_equal(0.0)
	assert_float(_def.falloff(_def.blast_radius + 3.0)).is_equal(0.0)
	var middle := (_def.core_radius + _def.blast_radius) / 2.0
	assert_float(_def.falloff(middle)).is_equal_approx(0.5, 0.0001)


func test_a_zombie_in_the_open_at_the_centre_takes_the_full_damage() -> void:
	var hit := _blast_at(Vector3(0, 0.3, 0), Vector3(0, 0, 0))
	assert_float(hit["damage"]).is_equal_approx(_def.damage, 0.5)
	assert_float(hit["exposure"]).is_equal_approx(1.0, 0.0001)


func test_damage_falls_with_distance_to_nothing_at_the_radius() -> void:
	var last := INF
	for metres in [1.0, 3.0, 4.5, 6.0]:
		var hit := _blast_at(Vector3(0, 0.3, 0), Vector3(0, 0, -metres))
		assert_float(hit["damage"]).is_less(last)
		last = hit["damage"]
	assert_float(_blast_at(Vector3(0, 0.3, 0), Vector3(0, 0, -12.0))["damage"]).is_equal(0.0)


func test_a_direct_blast_is_not_a_kill_for_a_late_round_zombie() -> void:
	var hit := _blast_at(Vector3(0, 0.3, 0), Vector3(0, 0, 0))
	assert_float(hit["damage"]).is_less(213.0)
	assert_float(hit["damage"]).is_greater(132.0)


func test_a_wall_between_shields_the_whole_body() -> void:
	var wall := GrenadesFixture.box_ray(AABB(Vector3(-3, 0, -3.1), Vector3(6, 3, 0.2)))
	var hit := _blast_at(Vector3(0, 0.3, 0), Vector3(0, 0, -5), wall)
	assert_float(hit["damage"]).is_equal(0.0)
	assert_float(hit["exposure"]).is_equal(0.0)


func test_low_cover_shields_the_legs_but_not_the_head() -> void:
	var low := GrenadesFixture.box_ray(AABB(Vector3(-3, 0, -2.6), Vector3(6, 0.9, 0.2)))
	var open := _blast_at(Vector3(0, 0.3, 0), Vector3(0, 0, -4))
	var covered := _blast_at(Vector3(0, 0.3, 0), Vector3(0, 0, -4), low)
	assert_float(covered["damage"]).is_greater(0.0)
	assert_float(covered["damage"]).is_less(open["damage"])
	assert_float(covered["leg_damage"]).is_less(open["leg_damage"] * 0.5)
	assert_float(covered["exposure"]).is_less(1.0)


func test_cover_that_is_beside_the_line_changes_nothing() -> void:
	var beside := GrenadesFixture.box_ray(AABB(Vector3(2, 0, -5), Vector3(1, 3, 1)))
	var open := _blast_at(Vector3(0, 0.3, 0), Vector3(0, 0, -4))
	var covered := _blast_at(Vector3(0, 0.3, 0), Vector3(0, 0, -4), beside)
	assert_float(covered["damage"]).is_equal(open["damage"])


func test_the_push_is_away_from_the_blast_and_up_and_weaker_far_off() -> void:
	var near := BlastModel.impulse(_def, Vector3.ZERO, Vector3(2, 0, 0), 1.0)
	var far := BlastModel.impulse(_def, Vector3.ZERO, Vector3(6, 0, 0), 0.1)
	assert_float(near.x).is_equal_approx(_def.knockback_speed, 0.001)
	assert_float(near.y).is_equal_approx(_def.knockback_lift, 0.001)
	assert_float(far.x).is_less(near.x)
	assert_vector(BlastModel.impulse(_def, Vector3.ZERO, Vector3.ZERO, 1.0)).is_equal(
		Vector3.UP * _def.knockback_lift
	)


# --- the server's blast, end to end ---


func test_one_blast_hurts_every_zombie_in_reach_through_one_explosion() -> void:
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast())
	var ids := _night.zombies
	assert_int(ids.size()).is_greater(2)
	_night.place({ids[0]: Vector3(1, 0, 0), ids[1]: Vector3(-3, 0, 0), ids[2]: Vector3(0, 0, -12)})
	_night.server.apply(GrenadeAction.cook(1, 1, Vector3(0, 1.0, 0)))
	var events := _night.run_seconds(_def.fuse + 0.1)
	var hits := GrenadesFixture.of(events, &"blast_hit")
	assert_int(hits.size()).is_equal(2)
	assert_int(hits[0]["target_id"]).is_equal(ids[0])
	assert_int(hits[1]["target_id"]).is_equal(ids[1])
	assert_float(hits[0]["damage"]).is_greater(hits[1]["damage"])
	assert_array(GrenadesFixture.of(events, &"zombie_damaged")).has_size(2)
	assert_float(hits[0]["impulse"].x).is_greater(0.0)
	assert_float(hits[1]["impulse"].x).is_less(0.0)
	assert_float(hits[0]["stun"]).is_greater(0.0)


func test_the_rules_pay_and_remove_the_zombies_a_blast_kills() -> void:
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast())
	var id := _night.zombies[0]
	_night.place({id: Vector3(0.5, 0, 0)})
	var before := _night.rules.points_of(1)
	_night.server.apply(GrenadeAction.cook(1, 1, Vector3(0, 1.0, 0)))
	var events := _night.run_seconds(_def.fuse + 0.1)
	var removed := GrenadesFixture.of(events, &"zombie_removed")
	assert_array(removed).has_size(1)
	assert_str(removed[0]["zone"]).is_equal("blast")
	assert_int(_night.rules.points_of(1) - before).is_equal(40)


func test_a_zombie_behind_a_wall_is_not_touched() -> void:
	var wall := GrenadesFixture.box_ray(AABB(Vector3(-3, 0, -3.1), Vector3(6, 3, 0.2)))
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast(), wall)
	var ids := _night.zombies
	_night.place({ids[0]: Vector3(0, 0, -5), ids[1]: Vector3(0, 0, 3)})
	_night.server.apply(GrenadeAction.cook(1, 1, Vector3(0, 1.0, 0)))
	var events := _night.run_seconds(_def.fuse + 0.1)
	var hits := GrenadesFixture.of(events, &"blast_hit")
	assert_int(hits.size()).is_equal(1)
	assert_int(hits[0]["target_id"]).is_equal(ids[1])


func test_the_thrower_takes_a_reduced_blast_and_other_players_none() -> void:
	_night = GrenadesFixture.night(2, GrenadesFixture.world_cast())
	_night.place({}, {1: Vector3(0, 0, 0), 2: Vector3(1, 0, 0)})
	_night.server.apply(GrenadeAction.cook(1, 1, Vector3(0.5, 0.0, 0)))
	var events := _night.run_seconds(_def.fuse + 0.1)
	var hurt := GrenadesFixture.of(events, &"player_blasted")
	assert_int(hurt.size()).is_equal(1)
	assert_int(hurt[0]["player_id"]).is_equal(1)
	assert_bool(hurt[0]["own"]).is_true()
	assert_float(hurt[0]["damage"]).is_greater(0.0)
	assert_float(hurt[0]["damage"]).is_less(_def.damage * _def.self_damage_fraction + 0.01)


func test_friendly_fire_can_be_turned_on() -> void:
	_night = GrenadesFixture.night(2, GrenadesFixture.world_cast())
	_night.server.friendly_fire = true
	_night.place({}, {1: Vector3(0, 0, 0), 2: Vector3(1, 0, 0)})
	_night.server.apply(GrenadeAction.cook(1, 1, Vector3(0.5, 0.0, 0)))
	var hurt := GrenadesFixture.of(_night.run_seconds(_def.fuse + 0.1), &"player_blasted")
	assert_int(hurt.size()).is_equal(2)


func test_a_wall_protects_the_thrower_too() -> void:
	# The hand is held out 0.9 m in front of the thrower, with a thin wall between the two.
	var wall := GrenadesFixture.box_ray(AABB(Vector3(-3, 0, -0.5), Vector3(6, 3, 0.2)))
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast(), wall)
	_night.place({}, {1: Vector3(0, 0, -0.9)})
	_night.server.apply(GrenadeAction.cook(1, 1, Vector3(0, 1.45, 0)))
	var hurt := GrenadesFixture.of(_night.run_seconds(_def.fuse + 0.1), &"player_blasted")
	assert_array(hurt).is_empty()


func test_a_zombie_that_is_gone_is_not_a_target() -> void:
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast())
	var id := _night.zombies[0]
	_night.place({id: Vector3(0.5, 0, 0)})
	RulesFixture.kill(_night.rules, 1, id)
	_night.server.apply(GrenadeAction.cook(1, 1, Vector3(0, 1.0, 0)))
	var events := _night.run_seconds(_def.fuse + 0.1)
	assert_array(GrenadesFixture.of(events, &"blast_hit")).is_empty()
