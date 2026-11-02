# gdlint:disable=max-public-methods
# The match settings: the zombie count multiplier, the cap on the living, the break and the round
# time limit. They are the server's, set before the night, and the defaults are today's game.
extends GdUnitTestSuite

const ROUNDS := 10
const LONG := 400.0


func _settings(
	count: float = 1.0, alive: int = 0, between: float = 0.0, limit: float = 0.0
) -> MatchSettings:
	var s := MatchSettings.new()
	s.count_multiplier = count
	s.max_alive = alive
	s.break_seconds = between
	s.round_time_limit = limit
	return s


## The zombies a round brings, read from `round_started`, for the settings and players.
func _round_size(settings: MatchSettings, round_number: int, players: int = 1) -> int:
	var rules := RulesFixture.make_rules(players, 99, null, settings)
	var log := RulesFixture.record(rules)
	rules.round_number = round_number - 1
	RulesFixture.into_round_one(rules)
	return log.of(&"round_started")[0]["zombie_count"]


## The most zombies standing at once over `seconds`, killing none.
func _most_alive(rules: GameRules, seconds: float) -> int:
	var most := 0
	for _i in ceili(seconds / RulesFixture.STEP):
		rules.apply(RulesAction.tick(RulesFixture.STEP))
		most = maxi(most, rules.zombie_ids().size())
	return most


# --- Defaults are today's game ---


func test_the_defaults_are_the_usual_rules() -> void:
	var settings := MatchSettings.new()
	assert_bool(settings.is_default()).is_true()
	assert_float(settings.count_multiplier).is_equal(1.0)
	assert_int(settings.max_alive).is_equal(0)
	assert_float(settings.break_seconds).is_equal(0.0)
	assert_float(settings.round_time_limit).is_equal(0.0)
	assert_bool(RulesFixture.make_rules().settings.is_default()).is_true()


func test_default_rounds_are_the_tuned_rounds() -> void:
	var tuned := RulesFixture.tuning()
	for round_number in range(1, ROUNDS + 1):
		for players in [1, 2, 4]:
			var plain := _round_size(MatchSettings.new(), round_number, players)
			if tuned.specials.special_for(round_number) == null:
				assert_int(plain).is_equal(tuned.rounds.zombies_for_round(round_number, players))
			assert_int(_round_size(null, round_number, players)).is_equal(plain)


func test_default_settings_leave_the_cap_and_the_clock_alone() -> void:
	var rules := RulesFixture.make_rules(1, 5, null, MatchSettings.new())
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	var cap := rules.tuning.rounds.alive_cap(1, 1)
	assert_int(_most_alive(rules, 120.0)).is_equal(mini(cap, rules._round_total))
	assert_int(log.count(&"round_time_up")).is_equal(0)
	assert_int(log.count(&"settings_changed")).is_equal(0)


# --- The count multiplier ---


func test_the_count_at_1x_2x_and_3x_for_rounds_one_to_ten() -> void:
	var tuned := RulesFixture.tuning()
	for multiplier in MatchSettings.COUNT_CHOICES:
		for round_number in range(1, ROUNDS + 1):
			var got := _round_size(_settings(multiplier), round_number)
			var label := "round %d at %dx" % [round_number, roundi(multiplier)]
			if tuned.specials.special_for(round_number) == null:
				var normal := tuned.rounds.zombies_for_round(round_number, 1)
				assert_int(got).override_failure_message(label).is_equal(
					maxi(1, roundi(float(normal) * multiplier))
				)
			else:
				# A special round starts from the scaled normal count; its own share follows.
				assert_int(got).override_failure_message(label).is_greater_equal(
					_round_size(_settings(1.0), round_number)
				)


func test_each_step_up_brings_more_zombies() -> void:
	for round_number in range(1, ROUNDS + 1):
		var one := _round_size(_settings(1.0), round_number)
		var two := _round_size(_settings(2.0), round_number)
		var three := _round_size(_settings(3.0), round_number)
		assert_int(two).override_failure_message("round %d" % round_number).is_greater(one)
		assert_int(three).override_failure_message("round %d" % round_number).is_greater(two)


func test_a_stampede_round_scales_its_share_of_the_scaled_count() -> void:
	var tuned := RulesFixture.tuning()
	var special := tuned.specials.special_for(10)
	assert_object(special).is_not_null()
	var scaled := roundi(float(tuned.rounds.zombies_for_round(10, 1)) * 3.0)
	assert_int(_round_size(_settings(3.0), 10)).is_equal(
		maxi(1, roundi(float(scaled) * special.count_fraction))
	)


func test_the_multiplier_multiplies_the_crowd_of_more_players() -> void:
	var tuned := RulesFixture.tuning().rounds
	for players in [2, 4]:
		assert_int(_round_size(_settings(3.0), 3, players)).is_equal(
			tuned.zombies_for_round(3, players) * 3
		)


func test_a_new_type_still_arrives_by_its_exact_number_under_a_multiplier() -> void:
	var runner := RulesFixture.tuning().roster.type_of(&"runner")
	for multiplier in MatchSettings.COUNT_CHOICES:
		var rules := RulesFixture.make_rules(1, 3, null, _settings(multiplier))
		rules.round_number = runner.first_round - 1
		RulesFixture.into_round_one(rules)
		assert_int(rules._plan.count(&"runner")).is_equal(runner.intro_count)


func test_a_tiny_multiplier_still_brings_one_zombie() -> void:
	assert_int(_settings(0.25).scaled_count(1)).is_equal(1)
	assert_int(_round_size(_settings(0.25), 1)).is_greater_equal(1)


# --- The cap on the living ---


func test_the_cap_override_holds_the_crowd_to_it() -> void:
	var rules := RulesFixture.make_rules(1, 4, null, _settings(3.0, 3))
	RulesFixture.into_round_one(rules)
	assert_int(_most_alive(rules, 90.0)).is_equal(3)


func test_a_cap_above_the_curve_lets_more_stand() -> void:
	var cap := RulesFixture.tuning().rounds.alive_cap(1, 1)
	var rules := RulesFixture.make_rules(1, 4, null, _settings(3.0, cap + 4))
	RulesFixture.into_round_one(rules)
	assert_int(_most_alive(rules, 120.0)).is_equal(cap + 4)


func test_the_cap_never_goes_above_the_ceiling() -> void:
	var rounds := RulesFixture.tuning().rounds
	assert_int(_settings(1.0, 999).alive_cap(rounds, 1, 1)).is_equal(rounds.alive_cap_ceiling)
	# A rules built with an out-of-bounds cap pulls it in.
	var rules := RulesFixture.make_rules(1, 4, null, _settings(1.0, 999))
	assert_int(rules.settings.max_alive).is_equal(rounds.alive_cap_ceiling)
	rounds.alive_cap_ceiling = 12
	assert_int(_settings(1.0, 30).alive_cap(rounds, 1, 1)).is_equal(12)


func test_auto_is_the_tuned_curve_in_every_round_and_player_count() -> void:
	var rounds := RulesFixture.tuning().rounds
	for round_number in range(1, 31):
		for players in [1, 2, 4]:
			assert_int(MatchSettings.new().alive_cap(rounds, round_number, players)).is_equal(
				rounds.alive_cap(round_number, players)
			)


# --- The break ---


func test_the_break_follows_the_setting() -> void:
	for seconds in [1.0, 10.0, 30.0]:
		var rules := RulesFixture.make_rules(1, 6, null, _settings(1.0, 0, seconds))
		var log := RulesFixture.record(rules)
		RulesFixture.into_round_one(rules)
		RulesFixture.clear_round(rules)
		assert_int(rules.phase).is_equal(GameRules.Phase.BREAK)
		assert_float(log.of(&"break_started").back()["seconds"]).is_equal(seconds)


func test_the_default_break_is_the_tuned_one_and_the_intro_is_not_touched() -> void:
	var rules := RulesFixture.make_rules(1, 6, null, _settings(1.0, 0, 20.0))
	var log := RulesFixture.record(rules)
	rules.apply(RulesAction.start())
	assert_float(log.of(&"break_started")[0]["seconds"]).is_equal(rules.tuning.rounds.intro_seconds)
	assert_float(MatchSettings.new().break_for(rules.tuning.rounds)).is_equal(
		rules.tuning.rounds.break_seconds
	)


# --- The round time limit ---


func test_time_up_is_said_once_at_the_limit() -> void:
	var rules := RulesFixture.make_rules(1, 8, null, _settings(3.0, 0, 0.0, 30.0))
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 29.0)
	assert_int(log.count(&"round_time_up")).is_equal(0)
	RulesFixture.run(rules, 2.0)
	assert_int(log.count(&"round_time_up")).is_equal(1)
	RulesFixture.run(rules, 60.0)
	assert_int(log.count(&"round_time_up")).is_equal(1)
	var event := log.of(&"round_time_up")[0]
	assert_int(event["round"]).is_equal(1)
	assert_float(event["limit"]).is_equal(30.0)


func test_without_a_limit_a_round_never_runs_out() -> void:
	var rules := RulesFixture.make_rules(1, 8, null, _settings(3.0))
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, LONG)
	assert_int(log.count(&"round_time_up")).is_equal(0)
	assert_int(rules.phase).is_equal(GameRules.Phase.ACTIVE)


func test_when_time_is_up_the_dead_come_faster_and_nobody_loses() -> void:
	var rules := RulesFixture.make_rules(1, 8, null, _settings(3.0, 0, 0.0, 30.0))
	var cap := rules.tuning.rounds.alive_cap(1, 1)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 29.0)
	assert_int(rules.zombie_ids().size()).is_equal(cap)
	var queued := rules._plan.size()
	assert_int(queued).is_greater(0)
	RulesFixture.run(rules, 10.0)
	# More than the round's cap now stand (the ceiling lifts), and the queue drains.
	assert_int(rules.zombie_ids().size()).is_greater(cap)
	assert_int(queued - rules._plan.size()).is_greater_equal(3)
	assert_int(rules.phase).is_equal(GameRules.Phase.ACTIVE)


func test_overtime_keeps_a_cap_the_host_chose() -> void:
	var rules := RulesFixture.make_rules(1, 8, null, _settings(3.0, 4, 0.0, 30.0))
	RulesFixture.into_round_one(rules)
	assert_int(_most_alive(rules, 90.0)).is_equal(4)


func test_overtime_spawns_come_by_the_tuned_rate() -> void:
	var rounds := RulesFixture.tuning().rounds
	var settings := _settings(1.0, 0, 0.0, 30.0)
	assert_float(settings.spawn_interval(rounds, 3, 1, true)).is_equal_approx(
		rounds.spawn_interval(3, 1) / rounds.overtime_spawn_rate, 0.0001
	)
	assert_float(settings.spawn_interval(rounds, 3, 1, false)).is_equal(rounds.spawn_interval(3, 1))


func test_each_round_has_its_own_clock() -> void:
	var rules := RulesFixture.make_rules(1, 9, null, _settings(1.0, 0, 1.0, 30.0))
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	# Round 1 is cleared in seconds, inside its limit; the 1 s break passes; round 2 runs out at 30.
	RulesFixture.clear_round(rules)
	assert_int(log.count(&"round_time_up")).is_equal(0)
	RulesFixture.run(rules, 1.5)
	assert_int(rules.round_number).is_equal(2)
	RulesFixture.run(rules, 28.0)
	assert_int(log.count(&"round_time_up")).is_equal(0)
	RulesFixture.run(rules, 2.5)
	assert_int(log.count(&"round_time_up")).is_equal(1)
	assert_int(log.of(&"round_time_up")[0]["round"]).is_equal(2)


# --- Configuring ---


func test_configure_sets_the_settings_before_the_night() -> void:
	var rules := RulesFixture.make_rules()
	var log := RulesFixture.record(rules)
	var caused := rules.apply(RulesAction.configure(_settings(2.0, 9, 8.0, 90.0)))
	assert_int(caused.size()).is_equal(1)
	assert_str(String(caused[0]["type"])).is_equal("settings_changed")
	assert_dict(caused[0]["settings"]).is_equal(rules.settings.to_dict())
	assert_float(rules.settings.count_multiplier).is_equal(2.0)
	assert_int(rules.settings.max_alive).is_equal(9)
	assert_float(rules.settings.break_seconds).is_equal(8.0)
	assert_float(rules.settings.round_time_limit).is_equal(90.0)
	assert_int(log.count(&"settings_changed")).is_equal(1)


func test_configure_after_the_start_is_refused_and_changes_nothing() -> void:
	var rules := RulesFixture.make_rules(1, 3, null, _settings(2.0))
	RulesFixture.into_round_one(rules)
	var caused := rules.apply(RulesAction.configure(_settings(3.0, 5)))
	assert_str(String(caused[0]["type"])).is_equal("action_rejected")
	assert_str(String(caused[0]["reason"])).is_equal("wrong_phase")
	assert_float(rules.settings.count_multiplier).is_equal(2.0)
	assert_int(rules.settings.max_alive).is_equal(0)


func test_configure_with_a_value_out_of_bounds_is_refused() -> void:
	var rules := RulesFixture.make_rules()
	var bad := [
		{"count_multiplier": 0.0},
		{"count_multiplier": 6.0},
		{"count_multiplier": NAN},
		{"max_alive": -1},
		{"max_alive": 999},
		{"break_seconds": 0.5},
		{"break_seconds": 500.0},
		{"break_seconds": -3.0},
		{"round_time_limit": 10.0},
		{"round_time_limit": 99999.0},
		{"round_time_limit": INF},
	]
	for change: Dictionary in bad:
		var data := MatchSettings.new().to_dict()
		data.merge(change, true)
		var caused := rules.apply({"type": RulesAction.CONFIGURE, "settings": data})
		assert_str(String(caused[0]["type"])).override_failure_message(str(change)).is_equal(
			"action_rejected"
		)
		assert_str(String(caused[0]["reason"])).is_equal("out_of_range")
		assert_str(String(caused[0]["field"])).is_equal("settings")
	assert_bool(rules.settings.is_default()).is_true()


func test_configure_with_a_missing_or_mistyped_field_is_refused() -> void:
	var rules := RulesFixture.make_rules()
	var short := MatchSettings.new().to_dict()
	short.erase("max_alive")
	assert_str(String(MatchSettings.problem(short))).is_equal("max_alive")
	var typed := MatchSettings.new().to_dict()
	typed["round_time_limit"] = "never"
	assert_str(String(MatchSettings.problem(typed))).is_equal("round_time_limit")
	for settings: Dictionary in [short, typed]:
		var caused := rules.apply({"type": RulesAction.CONFIGURE, "settings": settings})
		assert_str(String(caused[0]["type"])).is_equal("action_rejected")
	assert_bool(rules.settings.is_default()).is_true()


func test_clamped_pulls_every_value_into_its_bounds() -> void:
	var wild := _settings(9.0, 400, 0.2, 5.0).clamped()
	assert_float(wild.count_multiplier).is_equal(MatchSettings.MAX_COUNT_MULTIPLIER)
	assert_int(wild.max_alive).is_equal(RoundTuning.new().alive_cap_ceiling)
	assert_float(wild.break_seconds).is_equal(MatchSettings.MIN_BREAK)
	assert_float(wild.round_time_limit).is_equal(MatchSettings.MIN_TIME_LIMIT)
	assert_str(String(MatchSettings.problem(wild.to_dict()))).is_empty()
	assert_bool(_settings(1.0, 0, -5.0, -5.0).clamped().is_default()).is_true()


# --- The snapshot ---


func test_the_snapshot_carries_the_settings_and_the_round_clock() -> void:
	var settings := _settings(2.0, 8, 12.0, 60.0)
	var rules := RulesFixture.make_rules(1, 10, null, settings)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 20.0)
	var snapshot := rules.to_dict()
	assert_dict(snapshot["match_settings"]).is_equal(settings.to_dict())
	assert_float(snapshot["round_elapsed"]).is_equal_approx(20.0, 0.05)
	assert_int(snapshot["version"]).is_equal(GameRules.SNAPSHOT_VERSION)


func test_a_restore_brings_the_settings_back_through_every_form() -> void:
	var rules := RulesFixture.make_rules(2, 10, null, _settings(3.0, 9, 14.0, 45.0))
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 12.0)
	for form in ["dict", "bytes", "wire"]:
		var other := RulesFixture.make_rules(1, 77)
		var answer: StringName
		match form:
			"dict":
				answer = other.from_dict(rules.to_dict())
			"bytes":
				answer = other.from_bytes(rules.to_bytes())
			_:
				var through_json: Dictionary = JSON.parse_string(
					JSON.stringify({"w": rules.to_wire()})
				)
				answer = other.from_wire(through_json["w"])
		assert_str(String(answer)).override_failure_message(form).is_empty()
		assert_dict(other.settings.to_dict()).override_failure_message(form).is_equal(
			rules.settings.to_dict()
		)


func test_a_restored_night_runs_out_of_time_when_the_original_does() -> void:
	var rules := RulesFixture.make_rules(1, 10, null, _settings(3.0, 0, 0.0, 30.0))
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 20.0)
	var copy := RulesFixture.make_rules(1, 5)
	var log := RulesFixture.record(copy)
	assert_str(String(copy.from_dict(rules.to_dict()))).is_empty()
	RulesFixture.run(copy, 8.0)
	assert_int(log.count(&"round_time_up")).is_equal(0)
	RulesFixture.run(copy, 3.0)
	assert_int(log.count(&"round_time_up")).is_equal(1)


func test_a_snapshot_with_settings_out_of_bounds_is_malformed_and_changes_nothing() -> void:
	var rules := RulesFixture.make_rules(1, 10, null, _settings(2.0))
	var snapshot := rules.to_dict()
	snapshot["match_settings"]["count_multiplier"] = 50.0
	var other := RulesFixture.make_rules(1, 5)
	assert_str(String(other.from_dict(snapshot))).is_equal("malformed")
	assert_bool(other.settings.is_default()).is_true()
	var no_settings := rules.to_dict()
	no_settings.erase("match_settings")
	assert_str(String(other.from_dict(no_settings))).is_equal("malformed")


func test_the_layout_before_the_settings_is_refused_as_a_bad_version() -> void:
	var snapshot := RulesFixture.make_rules().to_dict()
	snapshot["version"] = 8
	snapshot.erase("match_settings")
	snapshot.erase("round_elapsed")
	assert_str(String(RulesFixture.make_rules().from_dict(snapshot))).is_equal("bad_version")
	assert_int(GameRules.SNAPSHOT_VERSION).is_greater_equal(9)
