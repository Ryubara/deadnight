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


func test_the_snapshot_carries_the_zombies_the_round_began_with() -> void:
	# A late joiner's HUD shows "left of total": the total is not derivable from what is alive.
	var original := _midnight()
	var snapshot := original.to_dict()
	assert_int(snapshot["round_total"]).is_greater(original.zombies_remaining())
	var copy := GameRules.new(RulesFixture.tuning(), 1)
	assert_str(copy.from_dict(snapshot)).is_equal("")
	assert_dict(copy.to_dict()).is_equal(snapshot)


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


## A snapshot with zombies alive in it.
func _snapshot_with_zombies() -> Dictionary:
	var rules := _midnight()
	if rules.phase == GameRules.Phase.BREAK:
		rules.apply(RulesAction.skip_break())
	for _i in 600:
		if not rules.zombie_ids().is_empty():
			break
		rules.apply(RulesAction.tick(RulesFixture.STEP))
	var snapshot := rules.to_dict()
	assert_dict(snapshot["zombies"]).is_not_empty()
	return snapshot


## What the target looks like, to prove a refused restore changed nothing.
func _assert_refused(target: GameRules, snapshot: Dictionary, why: String) -> void:
	var before := target.to_dict()
	assert_str(target.from_dict(snapshot)).is_equal(why)
	assert_dict(target.to_dict()).is_equal(before)


func test_both_old_layouts_of_version_4_are_bad_version_not_malformed() -> void:
	var target := _midnight(1, 5)
	# The layout of #161: `spawn_left` instead of `plan` and `special_id`, a zombie without `type`.
	var first := _snapshot_with_zombies()
	first["version"] = 4
	first.erase("plan")
	first.erase("special_id")
	for entry: Dictionary in first["zombies"].values():
		entry.erase("type")
		entry.erase("max_health")
		entry.erase("speed")
	_assert_refused(target, first, "bad_version")
	# The layout of #166: today's keys, still called 4.
	var second := _snapshot_with_zombies()
	second["version"] = 4
	_assert_refused(target, second, "bad_version")
	for old in [0, 1, 2, 3]:
		second["version"] = old
		_assert_refused(target, second, "bad_version")
	assert_int(GameRules.SNAPSHOT_VERSION).is_greater(4)


func test_a_snapshot_without_a_version_number_is_malformed() -> void:
	var target := _midnight(1, 5)
	var snapshot := _midnight().to_dict()
	snapshot["version"] = "5"
	_assert_refused(target, snapshot, "malformed")
	snapshot.erase("version")
	_assert_refused(target, snapshot, "malformed")


func test_a_zombie_without_a_type_is_malformed_and_changes_nothing() -> void:
	var snapshot := _snapshot_with_zombies()
	var first_id: int = snapshot["zombies"].keys()[0]
	snapshot["zombies"][first_id].erase("type")
	var target := _midnight(1, 5)
	_assert_refused(target, snapshot, "malformed")
	# The night is still whole: it snapshots and carries on.
	assert_dict(target.to_dict()).is_not_empty()
	assert_array(target.apply(RulesAction.tick(RulesFixture.STEP))).is_not_null()


func test_a_zombie_with_the_wrong_kind_of_field_is_malformed() -> void:
	var target := _midnight(1, 5)
	for field in [["health", "10"], ["crippled", 1], ["paid_hits", 1.5], ["type", 4], ["id", 999]]:
		var snapshot := _snapshot_with_zombies()
		var first_id: int = snapshot["zombies"].keys()[0]
		snapshot["zombies"][first_id][field[0]] = field[1]
		_assert_refused(target, snapshot, "malformed")
	var not_a_dictionary := _snapshot_with_zombies()
	not_a_dictionary["zombies"][not_a_dictionary["zombies"].keys()[0]] = 5
	_assert_refused(target, not_a_dictionary, "malformed")


func test_a_zombie_of_an_unknown_type_is_malformed() -> void:
	var snapshot := _snapshot_with_zombies()
	snapshot["zombies"][snapshot["zombies"].keys()[0]]["type"] = &"zeppelin"
	_assert_refused(_midnight(1, 5), snapshot, "malformed")


func test_a_plan_of_the_wrong_kind_or_with_an_unknown_type_is_malformed() -> void:
	var target := _midnight(1, 5)
	var snapshot := _midnight().to_dict()
	snapshot["plan"] = [1, 2, 3]
	_assert_refused(target, snapshot, "malformed")
	snapshot["plan"] = [&"walker", &"zeppelin"]
	_assert_refused(target, snapshot, "malformed")
	snapshot["plan"] = [&"walker", &"walker"]
	assert_str(target.from_dict(snapshot)).is_equal("")
	assert_int(target.to_dict()["plan"].size()).is_equal(2)


func test_a_special_round_that_does_not_exist_is_malformed() -> void:
	var snapshot := _midnight().to_dict()
	snapshot["special_id"] = "no_such_round"
	_assert_refused(_midnight(1, 5), snapshot, "malformed")


func test_a_damaged_player_or_generator_is_malformed() -> void:
	var target := _midnight(1, 5)
	var snapshot := _midnight().to_dict()
	snapshot["players"][1].erase("points")
	_assert_refused(target, snapshot, "malformed")
	snapshot = _midnight().to_dict()
	snapshot["players"][1]["weapons"] = [1, 2]
	_assert_refused(target, snapshot, "malformed")
	snapshot = _midnight().to_dict()
	snapshot["generator"].erase("fuel")
	_assert_refused(target, snapshot, "malformed")
	snapshot = _midnight().to_dict()
	snapshot["generator"]["circuits"] = {"screen_lot": "on"}
	_assert_refused(target, snapshot, "malformed")
	snapshot = _midnight().to_dict()
	snapshot["phase"] = 99
	_assert_refused(target, snapshot, "malformed")
	snapshot = _midnight().to_dict()
	snapshot["doors_open"] = [3]
	_assert_refused(target, snapshot, "malformed")


func test_names_that_arrive_as_strings_restore_fine() -> void:
	var snapshot := _midnight().to_dict()
	snapshot["plan"] = ["walker"]
	for entry: Dictionary in snapshot["zombies"].values():
		entry["type"] = String(entry["type"])
	var target := _midnight(1, 5)
	assert_str(target.from_dict(snapshot)).is_equal("")
	assert_array(target.to_dict()["plan"]).is_equal([&"walker"])
