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
func _rules(settings: MatchSettings, players := 1, tuning: RulesTuning = null) -> GameRules:
	var rules := RulesFixture.make_rules(players, 7, tuning, settings)
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


## The last perk of the limit bought and not yet drunk (#912): the bottle in the hand counts.
func _drinking_the_last_one(rules: GameRules) -> void:
	for i in rules.tuning.economy.max_tonics - 1:
		assert_int(RulesFixture.buy(rules, 1, PERKS[i])).is_equal(GameRules.BuyResult.OK)
	var last := PERKS[rules.tuning.economy.max_tonics - 1]
	assert_bool(rules.apply(RulesAction.buy(1, last)).is_empty()).is_false()
	assert_bool(PerkPlay.is_drinking(rules.players[1])).is_true()


func test_the_bottle_in_the_hand_counts_and_full_hands_are_refused_before_the_limit() -> void:
	var rules := _rules(MatchSettings.new())
	var limit := rules.tuning.economy.max_tonics
	_drinking_the_last_one(rules)
	assert_int(PerkPlay.held(rules.players[1])).is_equal(limit)
	assert_int(rules.players[1].tonics.size()).is_equal(limit - 1)
	# Full hands come first in the till's order: the player is told to finish the drink, and the
	# limit is what they meet once it is down.
	var points := rules.players[1].points
	var denied := RulesFixture.first(
		rules.apply(RulesAction.buy(1, PERKS[limit])), &"purchase_denied"
	)
	assert_int(denied["result"]).is_equal(GameRules.BuyResult.DRINKING)
	assert_int(rules.players[1].points).is_equal(points)
	RulesFixture.drink_down(rules, 1)
	assert_int(rules.players[1].tonics.size()).is_equal(limit)
	assert_int(RulesFixture.buy(rules, 1, PERKS[limit])).is_equal(GameRules.BuyResult.LIMIT_REACHED)


func test_a_spilled_drink_leaves_the_limit_room_for_one_perk_not_two() -> void:
	# Two players, so one going down does not end the night; the perks had are kept (the drink
	# alone is what the down spills).
	var tuning := RulesFixture.tuning()
	tuning.perks.lost_on_down = PerkTuning.Loss.NONE
	var rules := _rules(MatchSettings.new(), 2, tuning)
	var limit := rules.tuning.economy.max_tonics
	_drinking_the_last_one(rules)
	rules.apply(RulesAction.set_downed(1, true))
	assert_bool(PerkPlay.is_drinking(rules.players[1])).is_false()
	rules.apply(RulesAction.set_downed(1, false))
	var kept := rules.players[1].tonics.size()
	assert_int(PerkPlay.held(rules.players[1])).is_equal(kept)
	assert_int(kept).is_equal(limit - 1)
	# Buying back up to the limit stops at it: no path adds a perk past it.
	for perk in PERKS:
		RulesFixture.buy(rules, 1, perk)
	assert_int(rules.players[1].tonics.size()).is_equal(limit)


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
## perk. The simulator shops in the break (a tonic is drunk down there before the next purchase,
## `NightSim._drink_out`: #912), so the night is left at its first break (the intro), not started,
## and that break is long enough to drink every perk (a short one ends and the shopping with it).
func _simulated_perks(settings: MatchSettings) -> int:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = PERKS.size() * tuning.perks.drink_seconds + 5.0
	var sim := NightSim.new(tuning, SimSkill.named(SimSkill.STRONG), 1, 3, 0.25, settings)
	sim.skill.shopping.assign(PERKS)
	sim.skill.saves_for.clear()
	sim.rules.apply(RulesAction.start())
	assert_int(sim.rules.phase).is_equal(GameRules.Phase.BREAK)
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
