extends GdUnitTestSuite
## A grenade server made after the night began knows the zombies already alive, because it asks
## the rules and keeps no list of its own (#147). Its collision dependency is checked at setup.

const HAND := Vector3(0, 1.5, 0)
const NO_CAST_ERROR := GrenadeServer.NO_WORLD_CAST_ERROR


func _blast_in_reach(server: GrenadeServer, zombie_id: int) -> Array[Dictionary]:
	server.apply(GrenadeAction.targets([{"id": zombie_id, "pos": Vector3(0, 0, 1), "yaw": 0.0}]))
	server.apply(GrenadeAction.players([{"id": 1, "pos": Vector3.ZERO}]))
	var events := server.apply(GrenadeAction.cook(1, 1, Vector3(0, 1.45, 0)))
	for _i in 200:
		events.append_array(server.apply(GrenadeAction.tick(GrenadesFixture.STEP)))
	return events


func test_a_server_made_after_the_zombies_spawned_hits_them() -> void:
	var rules := RulesFixture.make_rules(1, 1234)
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 20.0)
	var zombie: int = log.spawned_ids()[0]
	var server := GrenadeServer.new(GrenadesFixture.def(), rules, GrenadesFixture.world_cast())
	var events := _blast_in_reach(server, zombie)
	var hits := GrenadesFixture.of(events, &"blast_hit")
	assert_array(hits).has_size(1)
	assert_int(hits[0]["target_id"]).is_equal(zombie)
	assert_array(GrenadesFixture.of(events, &"zombie_damaged")).is_not_empty()


func test_a_zombie_the_rules_no_longer_have_is_not_hit() -> void:
	var night := GrenadesFixture.night(1, GrenadesFixture.world_cast())
	var gone: int = night.zombies[0]
	RulesFixture.kill(night.rules, 1, gone)
	var events := _blast_in_reach(night.server, gone)
	assert_array(GrenadesFixture.of(events, &"grenade_exploded")).has_size(1)
	assert_array(GrenadesFixture.of(events, &"blast_hit")).is_empty()


func test_a_server_without_a_world_cast_says_so_once_and_still_runs_a_flight() -> void:
	var rules := RulesFixture.make_rules(1, 1234)
	RulesFixture.into_round_one(rules)
	var made: Array[GrenadeServer] = []
	await (
		assert_error(func() -> void: made.append(GrenadeServer.new(GrenadesFixture.def(), rules)))
		. is_push_error(NO_CAST_ERROR)
	)
	var server := made[0]
	server.apply(GrenadeAction.players([{"id": 1, "pos": Vector3.ZERO}]))
	server.apply(GrenadeAction.cook(1, 1, HAND))
	var events := server.apply(
		GrenadeAction.throw_grenade(1, 1, HAND, Vector3.FORWARD, Vector3.ZERO, false)
	)
	assert_array(GrenadesFixture.of(events, &"grenade_thrown")).has_size(1)
	for _i in 200:
		events.append_array(server.apply(GrenadeAction.tick(GrenadesFixture.STEP)))
	assert_array(GrenadesFixture.of(events, &"grenade_exploded")).has_size(1)
