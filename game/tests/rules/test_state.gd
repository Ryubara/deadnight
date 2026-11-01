extends GdUnitTestSuite
## Server-first: one serializable state, changed only by actions that return events, restorable from
## a snapshot.


## A scripted stretch of play: kills, a purchase, a downed player. Returns the events it caused.
func _play(rules: GameRules, seconds: float) -> Array[Dictionary]:
	var caused: Array[Dictionary] = []
	var steps := ceili(seconds / RulesFixture.STEP)
	var spawned: Array[int] = []
	for step in steps:
		for event in rules.apply(RulesAction.tick(RulesFixture.STEP)):
			caused.append(event)
			if event["type"] == &"zombie_spawn_requested":
				spawned.append(event["zombie_id"])
		# Every 40 steps the first player kills the oldest zombie; every 200 steps they spend.
		if step % 40 == 0 and not spawned.is_empty():
			caused.append_array(
				rules.apply(RulesAction.hit(1, spawned[0], RulesAction.ZONE_HEAD, 25.0))
			)
			var zone := RulesAction.ZONE_HEAD if step % 80 == 0 else RulesAction.ZONE_BODY
			caused.append_array(RulesFixture.kill(rules, 1, spawned.pop_front(), zone))
		if step % 200 == 0:
			caused.append_array(rules.apply(RulesAction.buy(1, &"crane_play")))
	return caused


func test_the_rules_need_no_scene_tree_node() -> void:
	var rules := RulesFixture.make_rules(1)
	assert_bool(is_instance_of(rules, Node)).is_false()
	assert_bool(rules is RefCounted).is_true()


func test_apply_returns_the_events_it_also_emits() -> void:
	var rules := RulesFixture.make_rules(1)
	var emitted: Array[Dictionary] = []
	rules.event_emitted.connect(func(event: Dictionary) -> void: emitted.append(event))
	var returned := rules.apply(RulesAction.start())
	assert_array(returned).is_equal(emitted)
	assert_str(returned[0]["type"]).is_equal("phase_changed")
	assert_str(returned[1]["type"]).is_equal("break_started")


func test_an_idle_tick_returns_no_events() -> void:
	var rules := RulesFixture.make_rules(1)
	assert_array(rules.apply(RulesAction.tick(RulesFixture.STEP))).is_empty()


func test_actions_and_events_are_plain_data() -> void:
	var rules := RulesFixture.make_rules(2)
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.skip_break())
	var action := RulesAction.hit(1, 3, RulesAction.ZONE_HEAD, 25.5, true)
	assert_dict(bytes_to_var(var_to_bytes(action))).is_equal(action)
	for event in _play(rules, 20.0):
		assert_dict(bytes_to_var(var_to_bytes(event))).is_equal(event)


func test_a_snapshot_survives_the_wire() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	_play(rules, 20.0)
	var snapshot := rules.to_dict()
	assert_dict(bytes_to_var(var_to_bytes(snapshot))).is_equal(snapshot)
	assert_int(snapshot["round"]).is_greater_equal(1)
	assert_int(snapshot["phase"]).is_not_equal(GameRules.Phase.IDLE)
	assert_int((snapshot["players"] as Dictionary).size()).is_equal(2)
	assert_float(snapshot["generator"]["fuel"]).is_less(100.0)


func test_a_restored_copy_continues_exactly_like_the_original() -> void:
	var original := RulesFixture.make_rules(2, 77)
	RulesFixture.into_round_one(original)
	_play(original, 25.0)
	# A server restarting, or a client joining mid-night: a different seed proves the snapshot
	# carries the streams.
	var copy := GameRules.new(RulesFixture.tuning(), 999)
	copy.from_dict(bytes_to_var(var_to_bytes(original.to_dict())))
	assert_dict(copy.to_dict()).is_equal(original.to_dict())
	var from_original := _play(original, 60.0)
	var from_copy := _play(copy, 60.0)
	assert_array(from_copy).is_equal(from_original)
	assert_dict(copy.to_dict()).is_equal(original.to_dict())
	assert_int(from_original.size()).is_greater(20)


func test_restoring_emits_nothing_and_keeps_the_low_fuel_warning_quiet() -> void:
	var original := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(original)
	original.generator.fuel = 20.0
	RulesFixture.run(original, 1.0)  # crosses the quarter mark: fuel_low fires here, once
	var copy := GameRules.new(RulesFixture.tuning(), 1)
	var heard: Array[Dictionary] = []
	copy.event_emitted.connect(func(event: Dictionary) -> void: heard.append(event))
	copy.from_dict(original.to_dict())
	assert_array(heard).is_empty()
	RulesFixture.run(copy, 5.0)
	for event in heard:
		assert_str(event["type"]).is_not_equal("fuel_low")


func test_an_unknown_action_is_rejected_not_crashed_on() -> void:
	var rules := RulesFixture.make_rules(1)
	var events := rules.apply({"type": &"fly_to_the_moon"})
	assert_str(events[0]["type"]).is_equal("action_rejected")
	events = rules.apply({})
	assert_str(events[0]["type"]).is_equal("action_rejected")
	events = rules.apply(RulesAction.set_circuit(&"nope", true))
	assert_str(events[0]["reason"]).is_equal("unknown_circuit")


func test_state_changes_only_through_apply() -> void:
	var rules := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(rules)
	var before := rules.to_dict()
	# Reads, quotes and snapshots change nothing.
	rules.points_of(1)
	rules.price_of(&"fuel_can")
	rules.zombies_remaining()
	rules.is_door_open(&"door_concession")
	rules.to_dict()
	assert_dict(rules.to_dict()).is_equal(before)


func test_a_snapshot_carries_each_living_zombies_health() -> void:
	var rules := RulesFixture.make_rules(1)
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 3.0)
	var zombie_id := log.spawned_ids()[0]
	rules.apply(RulesAction.hit(1, zombie_id, RulesAction.ZONE_BODY, 25.0))
	var copy := GameRules.new(RulesFixture.tuning(), 5)
	copy.from_dict(bytes_to_var(var_to_bytes(rules.to_dict())))
	# Round 1 health less 25 is left: a hit of 40 kills it, and it pays the kill, not another hit.
	var events := copy.apply(RulesAction.hit(1, zombie_id, RulesAction.ZONE_BODY, 40.0))
	assert_float(events[0]["damage"]).is_equal(RulesFixture.round_health(1) - 25.0)
	assert_str(events.back()["cause"]).is_equal("killed")
	assert_int(copy.points_of(1)).is_equal(200 + 4 + 60)
