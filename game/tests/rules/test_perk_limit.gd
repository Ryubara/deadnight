# The perk limit match setting (#913): a night carries the shop's own limit of perks (four) or none,
# chosen with the other match settings before the night. The rules' buy, the machines, the bots
# and the balance simulator ask `MatchSettings.tonic_limit`; the setting rides the dict, the
# snapshot and the ticket like the others, and a settings dict from before it means the default.
extends GdUnitTestSuite

const PERKS: Array[StringName] = [
	&"tonic_hearty",
	&"tonic_double_shot",
	&"tonic_quick_load",
	&"tonic_third_holster",
	&"tonic_swift_rescue",
	&"tonic_reload_shock",
]


func _unlimited() -> MatchSettings:
	var settings := MatchSettings.new()
	settings.perk_limit = MatchSettings.PERKS_UNLIMITED
	return settings


## A round-one night with rich players under `settings`.
func _rules(settings: MatchSettings) -> GameRules:
	var rules := RulesFixture.make_rules(1, 7, null, settings)
	RulesFixture.into_round_one(rules)
	rules.apply(RulesAction.grant_points(1, 50000))
	return rules


func test_the_default_is_the_shops_limit_and_unlimited_is_more_than_every_perk() -> void:
	var economy := RulesFixture.tuning().economy
	var usual := MatchSettings.new()
	assert_int(usual.perk_limit).is_equal(MatchSettings.PERKS_DEFAULT)
	assert_bool(usual.is_default()).is_true()
	assert_int(usual.tonic_limit(economy)).is_equal(economy.max_tonics)
	assert_bool(_unlimited().is_default()).is_false()
	assert_int(_unlimited().tonic_limit(economy)).is_greater(PerkEffects.tonic_ids(economy).size())
	# The shop sells more perks than the usual limit, so the setting has something to lift.
	assert_int(PerkEffects.tonic_ids(economy).size()).is_greater(economy.max_tonics)


func test_the_limit_holds_on_default() -> void:
	var rules := _rules(MatchSettings.new())
	for i in rules.tuning.economy.max_tonics:
		assert_int(RulesFixture.buy(rules, 1, PERKS[i])).is_equal(GameRules.BuyResult.OK)
	var points := rules.players[1].points
	assert_int(RulesFixture.buy(rules, 1, PERKS[4])).is_equal(GameRules.BuyResult.LIMIT_REACHED)
	assert_int(rules.players[1].points).is_equal(points)
	assert_int(rules.players[1].tonics.size()).is_equal(rules.tuning.economy.max_tonics)


func test_the_limit_lifts_on_unlimited_and_a_perk_is_still_bought_once() -> void:
	var rules := _rules(_unlimited())
	for perk in PERKS:
		assert_int(RulesFixture.buy(rules, 1, perk)).is_equal(GameRules.BuyResult.OK)
	assert_int(rules.players[1].tonics.size()).is_equal(PERKS.size())
	assert_int(RulesFixture.buy(rules, 1, PERKS[0])).is_equal(GameRules.BuyResult.ALREADY_OWNED)


func test_the_setting_rides_the_dict_the_snapshot_and_a_json_round_trip() -> void:
	var settings := _unlimited()
	assert_int(settings.to_dict()["perk_limit"]).is_equal(MatchSettings.PERKS_UNLIMITED)
	assert_bool(MatchSettings.from_dict(settings.to_dict()).same_as(settings)).is_true()
	# JSON has one kind of number: 1.0 comes back as the int 1.
	var parsed: Variant = JSON.parse_string(JSON.stringify(settings.to_dict()))
	assert_int(MatchSettings.from_json(parsed).perk_limit).is_equal(MatchSettings.PERKS_UNLIMITED)
	var rules := RulesFixture.make_rules(1, 7, null, settings)
	var copy := RulesFixture.make_rules(0, 7)
	assert_str(String(copy.from_dict(rules.to_dict()))).is_empty()
	assert_int(copy.settings.perk_limit).is_equal(MatchSettings.PERKS_UNLIMITED)
	assert_int(MatchSettings.from_snapshot(rules.to_dict()).perk_limit).is_equal(
		MatchSettings.PERKS_UNLIMITED
	)


func test_a_dict_from_before_the_setting_means_the_default_and_a_wrong_value_is_refused() -> void:
	var old := MatchSettings.new().to_dict()
	old.erase("perk_limit")
	assert_str(String(MatchSettings.problem(old))).is_empty()
	assert_int(MatchSettings.from_dict(old).perk_limit).is_equal(MatchSettings.PERKS_DEFAULT)
	for bad: Variant in [2, -1, "unlimited", 0.5]:
		var data := MatchSettings.new().to_dict()
		data["perk_limit"] = bad
		assert_str(String(MatchSettings.problem(data))).override_failure_message(str(bad)).is_equal(
			"perk_limit"
		)
	var wild := MatchSettings.new()
	wild.perk_limit = 9
	assert_int(wild.clamped().perk_limit).is_equal(MatchSettings.PERKS_UNLIMITED)


func test_a_configure_action_sets_the_limit_before_the_night_only() -> void:
	var rules := RulesFixture.make_rules(1, 7)
	rules.apply(RulesAction.configure(_unlimited()))
	assert_int(rules.settings.perk_limit).is_equal(MatchSettings.PERKS_UNLIMITED)
	RulesFixture.into_round_one(rules)
	rules.apply(RulesAction.configure(MatchSettings.new()))
	assert_int(rules.settings.perk_limit).is_equal(MatchSettings.PERKS_UNLIMITED)


# --- The balance simulator ---


## The most perks the simulator's player owns after `shop`, with the usual list replaced by every
## perk.
func _simulated_perks(settings: MatchSettings) -> int:
	var sim := NightSim.new(
		RulesFixture.tuning(), SimSkill.named(SimSkill.STRONG), 1, 3, 0.25, settings
	)
	sim.skill.shopping.assign(PERKS)
	sim.skill.saves_for.clear()
	RulesFixture.into_round_one(sim.rules)
	sim.rules.apply(RulesAction.grant_points(1, 50000))
	sim._shop(sim._players[1])
	return sim.rules.players[1].tonics.size()


func test_the_simulated_player_stops_at_the_limit_and_buys_every_perk_on_unlimited() -> void:
	var economy := RulesFixture.tuning().economy
	assert_int(_simulated_perks(MatchSettings.new())).is_equal(economy.max_tonics)
	assert_int(_simulated_perks(_unlimited())).is_equal(PERKS.size())


func test_a_batch_cell_runs_under_the_setting() -> void:
	var cell := BalanceBatch.run_cell(
		RulesFixture.tuning(), &"strong", 1, 2, 3, 0.25, 6, [], 0.0, {}, _unlimited()
	)
	assert_int(cell["nights"]).is_equal(2)
