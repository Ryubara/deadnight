extends GdUnitTestSuite
## Boss nights and rounds of one type: which rounds are special, the announcement, what spawns,
## the reward, and that a snapshot taken in the middle of one carries on the same.

var _t: RulesTuning


func before_test() -> void:
	_t = RulesFixture.tuning()


## Plays through to the break before `round_number`, killing everything that spawns.
func _to_break_before(rules: GameRules, round_number: int) -> void:
	rules.apply(RulesAction.start())
	while rules.round_number < round_number - 1 or rules.phase != GameRules.Phase.BREAK:
		if rules.phase == GameRules.Phase.BREAK:
			rules.apply(RulesAction.skip_break())
		else:
			_clear_round(rules)


func _clear_round(rules: GameRules) -> void:
	var guard := 0
	while rules.phase == GameRules.Phase.ACTIVE and guard < 20000:
		rules.apply(RulesAction.tick(RulesFixture.STEP * 6.0))
		for zombie_id in rules.zombie_ids():
			RulesFixture.kill(rules, 1, zombie_id)
		guard += 1


func test_special_rounds_fall_every_nth_round_from_the_first() -> void:
	var specials := _t.specials
	var found: Array[int] = []
	for round_number in range(1, 31):
		if specials.is_special(round_number):
			found.append(round_number)
	assert_array(found).is_equal([5, 10, 15, 20, 25, 30])
	assert_int(specials.every).is_equal(5)


func test_the_kinds_come_in_turn_and_start_again() -> void:
	var specials := _t.specials
	var ids: Array[StringName] = []
	for round_number in [5, 10, 15, 20, 25]:
		ids.append(specials.special_for(round_number).id)
	assert_array(ids).is_equal(
		[&"double_feature", &"stampede", &"double_feature", &"crawl_space", &"double_feature"]
	)
	assert_object(specials.special_for(6)).is_null()


func test_special_rounds_can_be_turned_off() -> void:
	_t.specials.every = 0
	assert_bool(_t.specials.is_special(5)).is_false()


func test_the_break_before_a_special_round_is_announced_and_longer() -> void:
	var rules := RulesFixture.make_rules(1, 5, _t)
	var log := RulesFixture.record(rules)
	_to_break_before(rules, 5)
	var announced := log.of(&"special_round_announced")
	assert_int(announced.size()).is_equal(1)
	var event := announced[0]
	assert_int(event["round"]).is_equal(5)
	assert_str(event["special_id"]).is_equal("double_feature")
	assert_str(event["title"]).is_equal("Double Feature")
	assert_str(event["kind"]).is_equal("boss")
	assert_str(event["boss_type"]).is_equal("headliner")
	assert_int(event["boss_count"]).is_equal(1)
	var breaks := log.of(&"break_started")
	var last_break: Dictionary = breaks[breaks.size() - 1]
	assert_float(last_break["seconds"]).is_equal_approx(
		_t.rounds.break_seconds + _t.specials.break_bonus_seconds, 0.001
	)
	assert_float(event["seconds"]).is_equal(last_break["seconds"])


func test_an_ordinary_break_is_not_announced() -> void:
	var rules := RulesFixture.make_rules(1, 5, _t)
	var log := RulesFixture.record(rules)
	_to_break_before(rules, 3)
	assert_int(log.count(&"special_round_announced")).is_equal(0)


func test_a_boss_night_brings_the_boss_after_some_escorts() -> void:
	var rules := RulesFixture.make_rules(1, 5, _t)
	var log := RulesFixture.record(rules)
	_to_break_before(rules, 5)
	var mark := log.events.size()
	rules.apply(RulesAction.skip_break())
	_clear_round(rules)
	var started: Dictionary = log.of(&"round_started")[4]
	assert_int(started["round"]).is_equal(5)
	assert_str(started["special_id"]).is_equal("double_feature")
	assert_int(started["boss_count"]).is_equal(1)
	var types: Array[StringName] = []
	for event in log.events.slice(mark):
		if event["type"] == &"zombie_spawn_requested":
			types.append(event["zombie_type"])
	assert_int(types.size()).is_equal(started["zombie_count"])
	assert_int(types.count(&"headliner")).is_equal(1)
	assert_int(types.find(&"headliner")).is_greater(0)
	assert_int(types.find(&"headliner")).is_less(types.size() - 1)


func test_more_players_bring_more_bosses() -> void:
	var solo := _t.specials.special_for(5)
	assert_int(solo.bosses_for(1)).is_equal(1)
	assert_int(solo.bosses_for(2)).is_equal(1)
	assert_int(solo.bosses_for(4)).is_equal(2)


func test_a_boss_has_a_spawn_with_its_attack_and_is_marked() -> void:
	var rules := RulesFixture.make_rules(1, 5, _t)
	var log := RulesFixture.record(rules)
	_to_break_before(rules, 5)
	rules.apply(RulesAction.skip_break())
	_clear_round(rules)
	var boss: Dictionary = {}
	for event in log.of(&"zombie_spawn_requested"):
		if event["boss"]:
			boss = event
	assert_bool(boss.is_empty()).is_false()
	assert_str(boss["zombie_type"]).is_equal("headliner")
	assert_float(boss["telegraph_seconds"]).is_greater(0.0)
	assert_float(boss["knockback"]).is_greater(0.0)
	assert_float(boss["health"]).is_greater(_t.rounds.health_for_round(5) * 5.0)
	var removed: Array = log.of(&"zombie_removed").filter(
		func(e: Dictionary) -> bool: return e["boss"]
	)
	assert_int(removed.size()).is_equal(1)


func test_clearing_a_special_round_pays_the_reward_once_to_those_standing() -> void:
	var rules := RulesFixture.make_rules(2, 5, _t)
	var log := RulesFixture.record(rules)
	_to_break_before(rules, 5)
	rules.apply(RulesAction.skip_break())
	rules.apply(RulesAction.set_downed(2, true))
	var before_1 := rules.points_of(1)
	_clear_round(rules)
	var cleared := log.of(&"special_round_cleared")
	assert_int(cleared.size()).is_equal(1)
	var reward := _t.specials.special_for(5).reward_at(5)
	assert_int(cleared[0]["reward"]).is_equal(reward)
	assert_str(cleared[0]["special_id"]).is_equal("double_feature")
	var paid := log.of(&"points_changed").filter(
		func(e: Dictionary) -> bool: return e["reason"] == &"special_reward"
	)
	assert_int(paid.size()).is_equal(1)
	assert_int(paid[0]["player_id"]).is_equal(1)
	assert_int(rules.points_of(1)).is_greater(before_1 + reward - 1)


func test_an_ordinary_round_pays_no_reward() -> void:
	var rules := RulesFixture.make_rules(1, 5, _t)
	var log := RulesFixture.record(rules)
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.skip_break())
	_clear_round(rules)
	assert_int(log.count(&"special_round_cleared")).is_equal(0)
	assert_str(log.of(&"round_ended")[0]["special_id"]).is_equal("")


func test_a_round_of_one_type_is_only_that_type() -> void:
	var rules := RulesFixture.make_rules(1, 5, _t)
	var log := RulesFixture.record(rules)
	_to_break_before(rules, 10)
	var announced := log.of(&"special_round_announced")
	var event: Dictionary = announced[announced.size() - 1]
	assert_str(event["kind"]).is_equal("only")
	assert_str(event["boss_type"]).is_equal("")
	var mark := log.events.size()
	rules.apply(RulesAction.skip_break())
	_clear_round(rules)
	var seen: Array[StringName] = []
	for e in log.events.slice(mark):
		if e["type"] == &"zombie_spawn_requested":
			seen.append(e["zombie_type"])
	assert_array(seen).is_not_empty()
	for type_id in seen:
		assert_str(type_id).is_equal("runner")


func test_a_snapshot_in_the_middle_of_a_boss_night_carries_on_the_same() -> void:
	var rules := RulesFixture.make_rules(2, 9, _t)
	_to_break_before(rules, 5)
	rules.apply(RulesAction.skip_break())
	RulesFixture.run(rules, 6.0)
	assert_str(rules.special_id()).is_equal("double_feature")
	var copy := GameRules.new(_t, 9)
	assert_str(copy.from_wire(rules.to_wire())).is_equal("")
	assert_str(copy.special_id()).is_equal("double_feature")
	for _i in 600:
		var a := rules.apply(RulesAction.tick(RulesFixture.STEP))
		var b := copy.apply(RulesAction.tick(RulesFixture.STEP))
		assert_array(a).is_equal(b)
	assert_dict(rules.to_dict()).is_equal(copy.to_dict())


## Restores a copy of `rules` and ticks both for `ticks` steps: every event must match, and the
## states at the end too.
func _assert_copy_carries_on_the_same(rules: GameRules, ticks: int = 400) -> void:
	var copy := GameRules.new(_t, 9)
	assert_str(copy.from_wire(rules.to_wire())).is_equal("")
	assert_str(copy.special_id()).is_equal(rules.special_id())
	assert_dict(copy.to_dict()).is_equal(rules.to_dict())
	for _i in ticks:
		var a := rules.apply(RulesAction.tick(RulesFixture.STEP))
		var b := copy.apply(RulesAction.tick(RulesFixture.STEP))
		assert_array(a).is_equal(b)
	assert_dict(rules.to_dict()).is_equal(copy.to_dict())


func test_a_snapshot_in_the_middle_of_each_special_kind_carries_on_the_same() -> void:
	# The boss night (5), a round of one type (10, 20: runners, crawlers), two players, with spawns
	# still to come, and again once some of the round's dead have been killed.
	for round_number in [5, 10, 20]:
		var rules := RulesFixture.make_rules(2, 40 + round_number, _t)
		_to_break_before(rules, round_number)
		rules.apply(RulesAction.skip_break())
		RulesFixture.run(rules, 6.0)
		assert_bool(_t.specials.is_special(rules.round_number)).is_true()
		assert_str(rules.special_id()).is_not_empty()
		assert_int(rules.to_dict()["plan"].size()).is_greater(0)
		_assert_copy_carries_on_the_same(rules)
		for zombie_id in rules.zombie_ids().slice(0, 2):
			RulesFixture.kill(rules, 1, zombie_id)
		_assert_copy_carries_on_the_same(rules)


func test_a_snapshot_in_the_break_before_a_special_round_carries_on_the_same() -> void:
	for round_number in [5, 10]:
		var rules := RulesFixture.make_rules(2, 60 + round_number, _t)
		_to_break_before(rules, round_number)
		assert_int(rules.phase).is_equal(GameRules.Phase.BREAK)
		RulesFixture.run(rules, 2.0)
		# Through the rest of the break and into the round it announced.
		_assert_copy_carries_on_the_same(rules, 60 * 40)
		assert_int(rules.round_number).is_equal(round_number)
		assert_str(rules.special_id()).is_not_empty()


func test_the_same_seed_gives_the_same_boss_night() -> void:
	var first := _boss_night_types(31)
	assert_array(first).is_equal(_boss_night_types(31))


func _boss_night_types(seed_value: int) -> Array[StringName]:
	var rules := RulesFixture.make_rules(1, seed_value, _t)
	var log := RulesFixture.record(rules)
	_to_break_before(rules, 5)
	rules.apply(RulesAction.skip_break())
	_clear_round(rules)
	var types: Array[StringName] = []
	for event in log.of(&"zombie_spawn_requested"):
		types.append(event["zombie_type"])
	return types


func test_the_shipped_special_table_names_real_types() -> void:
	for kind in _t.specials.rounds:
		assert_str(kind.id).is_not_empty()
		if kind.kind == SpecialRound.Kind.BOSS:
			var boss := _t.roster.type_of(kind.boss_type)
			assert_object(boss).is_not_null()
			assert_bool(boss.boss).is_true()
		else:
			assert_object(_t.roster.type_of(kind.only_type)).is_not_null()
		assert_int(kind.reward_at(5)).is_greater(0)
