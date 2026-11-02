extends GdUnitTestSuite
## What the scoreboard reads from the rules: each player's kills and downs and the night's clock are
## counted by the rules from real events, kept in the snapshot, and the snapshot layout of every
## earlier version is refused as `bad_version`.

const BLOW := 60.0


func _spawn(rules: GameRules, count: int) -> Array[int]:
	var ids: Array[int] = []
	for _i in 600:
		for event in rules.apply(RulesAction.tick(RulesFixture.STEP)):
			if event["type"] == &"zombie_spawn_requested":
				ids.append(int(event["zombie_id"]))
		if ids.size() >= count:
			break
	return ids


func test_kills_are_counted_for_the_player_who_made_them() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	var ids := _spawn(rules, 5)
	RulesFixture.kill(rules, 1, ids[0])
	RulesFixture.kill(rules, 2, ids[1])
	RulesFixture.kill(rules, 2, ids[2], RulesAction.ZONE_HEAD)
	RulesFixture.kill(rules, 2, ids[3], RulesAction.ZONE_BODY, true)
	assert_int(rules.kills_of(1)).is_equal(1)
	assert_int(rules.kills_of(2)).is_equal(3)
	assert_int(rules.kills_of(99)).is_equal(0)


func test_a_blast_kill_counts_for_the_thrower() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	var ids := _spawn(rules, 3)
	rules.apply(
		RulesAction.explosion(2, [{"zombie_id": ids[0], "damage": 9999.0, "leg_damage": 0.0}])
	)
	assert_int(rules.kills_of(2)).is_equal(1)
	assert_int(rules.kills_of(1)).is_equal(0)


func test_a_down_is_counted_once_for_a_blow_and_once_for_a_forced_down() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	rules.apply(RulesAction.blow(1, 1000.0))
	assert_bool(rules.players[1].downed).is_true()
	assert_int(rules.downs_of(1)).is_equal(1)
	# A blow on a player who is already down does nothing, and counts nothing.
	rules.apply(RulesAction.blow(1, 1000.0))
	assert_int(rules.downs_of(1)).is_equal(1)
	rules.apply(RulesAction.set_downed(2, true))
	rules.apply(RulesAction.set_downed(2, true))
	assert_int(rules.downs_of(2)).is_equal(1)
	# Getting up is not a down; going down again is another.
	rules.apply(RulesAction.set_downed(2, false))
	rules.apply(RulesAction.set_downed(2, true))
	assert_int(rules.downs_of(2)).is_equal(2)
	assert_int(rules.downs_of(1)).is_equal(1)


func test_the_clock_runs_in_a_break_and_in_a_round_and_stops_at_the_end() -> void:
	var rules := RulesFixture.make_rules(1)
	RulesFixture.run(rules, 5.0)
	assert_float(rules.night_time).is_equal(0.0)
	rules.apply(RulesAction.start())
	RulesFixture.run(rules, 2.0)
	assert_float(rules.night_time).is_equal_approx(2.0, 0.05)
	rules.apply(RulesAction.skip_break())
	RulesFixture.run(rules, 3.0)
	assert_float(rules.night_time).is_equal_approx(5.0, 0.05)
	rules.apply(RulesAction.set_downed(1, true))
	assert_int(rules.phase).is_equal(GameRules.Phase.OVER)
	var at_end := rules.night_time
	RulesFixture.run(rules, 5.0)
	assert_float(rules.night_time).is_equal(at_end)


func test_the_counts_and_the_clock_survive_a_snapshot() -> void:
	var rules := RulesFixture.make_rules(2)
	RulesFixture.into_round_one(rules)
	var ids := _spawn(rules, 2)
	RulesFixture.kill(rules, 2, ids[0])
	rules.apply(RulesAction.blow(1, 1000.0))
	var copy := GameRules.new(RulesFixture.tuning(), 1)
	assert_str(copy.from_bytes(rules.to_bytes())).is_equal("")
	assert_int(copy.kills_of(2)).is_equal(1)
	assert_int(copy.downs_of(1)).is_equal(1)
	assert_float(copy.night_time).is_equal(rules.night_time)
	assert_dict(copy.to_dict()).is_equal(rules.to_dict())


func test_the_layout_of_version_9_is_bad_version_not_malformed() -> void:
	var rules := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(rules)
	var old := rules.to_dict()
	old["version"] = 9
	old.erase("night_time")
	for entry: Dictionary in old["players"].values():
		entry.erase("downs")
	var target := RulesFixture.make_rules(1)
	assert_str(target.from_dict(old)).is_equal("bad_version")
	assert_int(GameRules.SNAPSHOT_VERSION).is_greater(9)


func test_a_snapshot_with_a_negative_count_or_clock_is_malformed() -> void:
	var rules := RulesFixture.make_rules(1)
	RulesFixture.into_round_one(rules)
	var target := RulesFixture.make_rules(1)
	for damage: Array in [["night_time", -1.0], ["players.downs", -1], ["players.kills", -3]]:
		var snapshot := rules.to_dict()
		var path: PackedStringArray = String(damage[0]).split(".")
		if path.size() == 1:
			snapshot[path[0]] = damage[1]
		else:
			snapshot["players"][1][path[1]] = damage[1]
		assert_str(target.from_dict(snapshot)).is_equal("malformed")
