# gdlint:disable=max-public-methods
# The match settings: the zombie intensity (count and spawn rate), the cap on the living and the
# break. They are the server's, set before the night, and the defaults are today's game. A round
# has no time limit.
extends GdUnitTestSuite

const ROUNDS := 10
const LONG := 400.0
## Rounds the duration test plays, and its player: each zombie dies this long after it stands.
const DURATION_ROUNDS := 10
const KILL_AFTER := 7.0
const DURATION_TOLERANCE := 0.10
## Round 1 has 4 zombies at 1x: the wait before the first, the last one's life and the one gap fewer
## than zombies are a bigger share of it, so it gets a little more room.
const FIRST_ROUND_TOLERANCE := 0.15


func _settings(count: float = 1.0, alive: int = 0, between: float = 0.0) -> MatchSettings:
	var s := MatchSettings.new()
	s.count_multiplier = count
	s.max_alive = alive
	s.break_seconds = between
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
	assert_bool(RulesFixture.make_rules().settings.is_default()).is_true()


func test_default_rounds_are_the_tuned_rounds() -> void:
	var tuned := RulesFixture.tuning()
	for round_number in range(1, ROUNDS + 1):
		for players in [1, 2, 4]:
			var plain := _round_size(MatchSettings.new(), round_number, players)
			if tuned.specials.special_for(round_number) == null:
				assert_int(plain).is_equal(tuned.rounds.zombies_for_round(round_number, players))
			assert_int(_round_size(null, round_number, players)).is_equal(plain)


func test_default_settings_leave_the_cap_alone() -> void:
	var rules := RulesFixture.make_rules(1, 5, null, MatchSettings.new())
	var log := RulesFixture.record(rules)
	RulesFixture.into_round_one(rules)
	var cap := rules.tuning.rounds.alive_cap(1, 1)
	assert_int(_most_alive(rules, 120.0)).is_equal(mini(cap, rules._round_total))
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


# --- The spawn rate follows the count ---


## Seconds each round lasts (round_started to round_ended) for a player who kills every zombie
## `KILL_AFTER` seconds after it stands, for rounds 1 to `DURATION_ROUNDS`.
func _round_durations(settings: MatchSettings) -> Array[float]:
	var rules := RulesFixture.make_rules(1, 7, null, settings)
	rules.apply(RulesAction.start())
	var born := {}
	var began := 0.0
	var now := 0.0
	var out: Array[float] = []
	while out.size() < DURATION_ROUNDS and now < 3000.0:
		var caused := rules.apply(RulesAction.tick(RulesFixture.STEP))
		now += RulesFixture.STEP
		for zombie_id in rules.zombie_ids():
			if now - born.get(zombie_id, now) >= KILL_AFTER:
				caused.append_array(RulesFixture.kill(rules, 1, zombie_id))
		for event in caused:
			match event["type"]:
				&"zombie_spawn_requested":
					born[event["zombie_id"]] = now
				&"round_started":
					began = now
				&"round_ended":
					out.append(now - began)
	return out


func test_the_spawn_interval_divides_by_the_multiplier() -> void:
	var rounds := RulesFixture.tuning().rounds
	for round_number in [1, 3, 6, 10]:
		var own := rounds.spawn_interval(round_number, 1)
		for multiplier in MatchSettings.COUNT_CHOICES:
			var got := _settings(multiplier).spawn_interval(rounds, round_number, 1)
			(
				assert_float(got)
				. override_failure_message("round %d at %dx" % [round_number, roundi(multiplier)])
				. is_equal_approx(own / multiplier, 0.0001)
			)


func test_the_default_spawn_interval_is_the_tuned_one_for_any_crowd() -> void:
	var rounds := RulesFixture.tuning().rounds
	for round_number in [1, 5, 10, 25, 60]:
		for players in [1, 2, 4, 8]:
			(
				assert_float(MatchSettings.new().spawn_interval(rounds, round_number, players))
				. is_equal(rounds.spawn_interval(round_number, players))
			)


func test_a_multiplier_never_makes_spawns_faster_than_the_floor() -> void:
	var rounds := RulesFixture.tuning().rounds
	assert_float(rounds.spawn_interval_floor).is_equal(0.2)
	# A late round, where the tuned interval has reached its minimum.
	var own := rounds.spawn_interval(80, 1)
	assert_float(own).is_equal(rounds.spawn_interval_min)
	for multiplier in [2.0, 3.0, 5.0]:
		var got := _settings(multiplier).spawn_interval(rounds, 80, 1)
		assert_float(got).override_failure_message("%dx" % roundi(multiplier)).is_equal_approx(
			maxf(own / multiplier, rounds.spawn_interval_floor), 0.0001
		)
		assert_float(got).is_greater_equal(rounds.spawn_interval_floor - 0.0001)
	# Four players at 1x already come faster than the floor; a multiplier does not slow them.
	var crowd := rounds.spawn_interval(80, 4)
	assert_float(crowd).is_less(rounds.spawn_interval_floor + 0.0001)
	assert_float(_settings(3.0).spawn_interval(rounds, 80, 4)).is_equal(crowd)


func test_a_fractional_multiplier_slows_the_spawns_with_the_count() -> void:
	var rounds := RulesFixture.tuning().rounds
	assert_float(_settings(0.5).spawn_interval(rounds, 4, 1)).is_equal_approx(
		2.0 * rounds.spawn_interval(4, 1), 0.0001
	)


func test_the_rules_spawn_the_first_zombies_by_the_scaled_interval() -> void:
	for multiplier in MatchSettings.COUNT_CHOICES:
		var rules := RulesFixture.make_rules(1, 4, null, _settings(multiplier))
		var log := RulesFixture.record(rules)
		RulesFixture.into_round_one(rules)
		RulesFixture.run(rules, 6.0)
		var interval := _settings(multiplier).spawn_interval(rules.tuning.rounds, 1, 1)
		var expected := 1 + floori((6.0 - rules.tuning.rounds.first_spawn_delay) / interval)
		var spawned := log.count(&"zombie_spawn_requested")
		assert_int(spawned).override_failure_message("%dx" % roundi(multiplier)).is_between(
			expected - 1, expected + 1
		)


func test_a_round_lasts_about_as_long_at_2x_and_3x_as_at_1x() -> void:
	var one := _round_durations(_settings(1.0))
	assert_int(one.size()).is_equal(DURATION_ROUNDS)
	for multiplier in [2.0, 3.0]:
		var longer := _round_durations(_settings(multiplier))
		assert_int(longer.size()).is_equal(DURATION_ROUNDS)
		var all_one := 0.0
		var all_more := 0.0
		for i in DURATION_ROUNDS:
			var room := FIRST_ROUND_TOLERANCE if i == 0 else DURATION_TOLERANCE
			var label := "round %d at %dx: %.1f s against %.1f s at 1x"
			(
				assert_float(longer[i])
				. override_failure_message(label % [i + 1, roundi(multiplier), longer[i], one[i]])
				. is_between(one[i] * (1.0 - room), one[i] * (1.0 + room))
			)
			all_one += one[i]
			all_more += longer[i]
		assert_float(all_more).is_between(
			all_one * (1.0 - DURATION_TOLERANCE), all_one * (1.0 + DURATION_TOLERANCE)
		)


func test_the_auto_alive_cap_grows_with_the_multiplier_up_to_the_ceiling() -> void:
	var rounds := RulesFixture.tuning().rounds
	for round_number in [1, 5, 10, 30, 80]:
		var tuned := rounds.alive_cap(round_number, 1)
		assert_int(MatchSettings.new().alive_cap(rounds, round_number, 1)).is_equal(tuned)
		for multiplier in [2.0, 3.0]:
			var got := _settings(multiplier).alive_cap(rounds, round_number, 1)
			(
				assert_int(got)
				. override_failure_message("round %d at %dx" % [round_number, roundi(multiplier)])
				. is_equal(mini(roundi(tuned * multiplier), rounds.alive_cap_ceiling))
			)
	assert_int(_settings(0.25).alive_cap(rounds, 1, 1)).is_equal(
		maxi(1, roundi(rounds.alive_cap(1, 1) * 0.25))
	)


func test_a_cap_the_host_chose_is_not_scaled() -> void:
	var rounds := RulesFixture.tuning().rounds
	assert_int(_settings(3.0, 7).alive_cap(rounds, 10, 1)).is_equal(7)


# --- Configuring ---


func test_configure_sets_the_settings_before_the_night() -> void:
	var rules := RulesFixture.make_rules()
	var log := RulesFixture.record(rules)
	var caused := rules.apply(RulesAction.configure(_settings(2.0, 9, 8.0)))
	assert_int(caused.size()).is_equal(1)
	assert_str(String(caused[0]["type"])).is_equal("settings_changed")
	assert_dict(caused[0]["settings"]).is_equal(rules.settings.to_dict())
	assert_float(rules.settings.count_multiplier).is_equal(2.0)
	assert_int(rules.settings.max_alive).is_equal(9)
	assert_float(rules.settings.break_seconds).is_equal(8.0)
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
	typed["break_seconds"] = "never"
	assert_str(String(MatchSettings.problem(typed))).is_equal("break_seconds")
	for settings: Dictionary in [short, typed]:
		var caused := rules.apply({"type": RulesAction.CONFIGURE, "settings": settings})
		assert_str(String(caused[0]["type"])).is_equal("action_rejected")
	assert_bool(rules.settings.is_default()).is_true()


func test_clamped_pulls_every_value_into_its_bounds() -> void:
	var wild := _settings(9.0, 400, 0.2).clamped()
	assert_float(wild.count_multiplier).is_equal(MatchSettings.MAX_COUNT_MULTIPLIER)
	assert_int(wild.max_alive).is_equal(RoundTuning.new().alive_cap_ceiling)
	assert_float(wild.break_seconds).is_equal(MatchSettings.MIN_BREAK)
	assert_str(String(MatchSettings.problem(wild.to_dict()))).is_empty()
	assert_bool(_settings(1.0, 0, -5.0).clamped().is_default()).is_true()


# --- The snapshot ---


func test_the_snapshot_carries_the_settings() -> void:
	var settings := _settings(2.0, 8, 12.0)
	var rules := RulesFixture.make_rules(1, 10, null, settings)
	RulesFixture.into_round_one(rules)
	RulesFixture.run(rules, 20.0)
	var snapshot := rules.to_dict()
	assert_dict(snapshot["match_settings"]).is_equal(settings.to_dict())
	assert_int(snapshot["version"]).is_equal(GameRules.SNAPSHOT_VERSION)


func test_a_restore_brings_the_settings_back_through_every_form() -> void:
	var rules := RulesFixture.make_rules(2, 10, null, _settings(3.0, 9, 14.0))
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
	snapshot["version"] = 9
	snapshot.erase("match_settings")
	assert_str(String(RulesFixture.make_rules().from_dict(snapshot))).is_equal("bad_version")
	assert_int(GameRules.SNAPSHOT_VERSION).is_greater_equal(10)


func test_settings_read_from_json_take_a_whole_float_for_the_alive_cap() -> void:
	# JSON has one kind of number: the backend's `max_alive: 12` arrives as 12.0.
	var parsed := MatchSettings.from_json(
		JSON.parse_string('{"count_multiplier":3,"max_alive":12,"break_seconds":0}')
	)
	assert_object(parsed).is_not_null()
	assert_int(parsed.max_alive).is_equal(12)
	assert_float(parsed.count_multiplier).is_equal(3.0)
	# A fraction, a missing key, a value out of bounds, null and the wrong type are all null.
	for bad: Variant in [
		{"count_multiplier": 3.0, "max_alive": 3.5, "break_seconds": 0.0},
		{"count_multiplier": 3.0, "max_alive": 3},
		{"count_multiplier": 9.0, "max_alive": 3, "break_seconds": 0.0},
		null,
		"hard",
	]:
		assert_object(MatchSettings.from_json(bad)).is_null()
