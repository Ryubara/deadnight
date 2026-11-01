extends GdUnitTestSuite
## A snapshot has one wire form that survives JSON exactly, and a restore refuses what does not fit.


## A scripted stretch of play, to get a night with a bit of everything in it.
func _play(rules: GameRules, seconds: float) -> Array[Dictionary]:
	var caused: Array[Dictionary] = []
	var spawned: Array[int] = []
	for step in ceili(seconds / RulesFixture.STEP):
		for event in rules.apply(RulesAction.tick(RulesFixture.STEP)):
			caused.append(event)
			if event["type"] == &"zombie_spawn_requested":
				spawned.append(event["zombie_id"])
		if step % 40 == 0 and not spawned.is_empty():
			var hit := RulesAction.hit(1, spawned[0], RulesAction.ZONE_BODY, 25.0)
			caused.append_array(rules.apply(hit))
			if step % 120 == 0:
				caused.append_array(RulesFixture.kill(rules, 1, spawned.pop_front()))
		if step % 200 == 0:
			caused.append_array(rules.apply(RulesAction.buy(1, &"crane_play")))
	return caused


func _midnight(player_count: int = 2, seed_value: int = 77) -> GameRules:
	var rules := RulesFixture.make_rules(player_count, seed_value)
	RulesFixture.into_round_one(rules)
	_play(rules, 25.0)
	return rules


func test_the_wire_string_goes_through_json_and_restores_exactly() -> void:
	var original := _midnight()
	var json := JSON.stringify({"snapshot": original.to_wire()})
	var parsed: Dictionary = JSON.parse_string(json)
	var copy := GameRules.new(RulesFixture.tuning(), 999)
	assert_str(copy.from_wire(parsed["snapshot"])).is_equal("")
	assert_dict(copy.to_dict()).is_equal(original.to_dict())
	var from_original := _play(original, 60.0)
	var from_copy := _play(copy, 60.0)
	assert_array(from_copy).is_equal(from_original)
	assert_dict(copy.to_dict()).is_equal(original.to_dict())
	assert_int(from_original.size()).is_greater(20)


func test_the_bytes_form_restores_exactly_and_keeps_integer_keys() -> void:
	var original := _midnight()
	var copy := GameRules.new(RulesFixture.tuning(), 1)
	assert_str(copy.from_bytes(original.to_bytes())).is_equal("")
	assert_dict(copy.to_dict()).is_equal(original.to_dict())
	for player_id in copy.players:
		assert_int(typeof(player_id)).is_equal(TYPE_INT)
	assert_int(typeof(original.to_dict()["spawn_rng_state"])).is_equal(TYPE_INT)


func test_plain_json_does_not_survive_which_is_why_the_wire_form_exists() -> void:
	var original := _midnight()
	var through_json: Dictionary = JSON.parse_string(JSON.stringify(original.to_dict()))
	assert_dict(through_json).is_not_equal(original.to_dict())
	# Whatever a restore says about the damaged copy, it must not raise.
	var copy := GameRules.new(RulesFixture.tuning(), 1)
	assert_str(copy.from_dict(through_json)).is_not_equal("")


func test_the_snapshot_names_its_version_and_tuning() -> void:
	var snapshot := _midnight().to_dict()
	assert_int(snapshot["version"]).is_equal(GameRules.SNAPSHOT_VERSION)
	assert_str(snapshot["tuning_id"]).is_equal(RulesFixture.tuning().fingerprint())
	assert_int((snapshot["tuning_id"] as String).length()).is_equal(RulesTuning.FINGERPRINT_LENGTH)


func test_a_snapshot_of_another_version_is_refused_and_changes_nothing() -> void:
	var snapshot := _midnight().to_dict()
	snapshot["version"] = 99
	var target := _midnight(1, 5)
	var before := target.to_dict()
	assert_str(target.from_dict(snapshot)).is_equal("bad_version")
	assert_dict(target.to_dict()).is_equal(before)


func test_a_snapshot_under_a_different_tuning_is_refused_and_changes_nothing() -> void:
	var snapshot := _midnight().to_dict()
	var retuned := RulesFixture.tuning()
	retuned.economy.kill = 61
	var target := GameRules.new(retuned, 1)
	var before := target.to_dict()
	assert_str(target.from_dict(snapshot)).is_equal("wrong_tuning")
	assert_dict(target.to_dict()).is_equal(before)


func test_a_changed_shop_price_changes_the_fingerprint_too() -> void:
	var retuned := RulesFixture.tuning()
	retuned.economy.items[0].price += 1
	assert_str(retuned.fingerprint()).is_not_equal(RulesFixture.tuning().fingerprint())
	assert_str(RulesFixture.tuning().fingerprint()).is_equal(RulesFixture.tuning().fingerprint())


func test_a_damaged_snapshot_is_malformed_not_a_crash() -> void:
	var target := _midnight()
	var before := target.to_dict()
	assert_str(target.from_dict({})).is_equal("malformed")
	var snapshot := target.to_dict()
	snapshot.erase("players")
	assert_str(target.from_dict(snapshot)).is_equal("malformed")
	snapshot = target.to_dict()
	snapshot["spawn_rng_state"] = "12"
	assert_str(target.from_dict(snapshot)).is_equal("malformed")
	assert_str(target.from_bytes(PackedByteArray())).is_equal("malformed")
	assert_str(target.from_bytes(PackedByteArray([1, 2, 3]))).is_equal("malformed")
	assert_str(target.from_wire("not base64 at all!")).is_equal("malformed")
	assert_dict(target.to_dict()).is_equal(before)
