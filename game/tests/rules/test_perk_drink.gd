extends GdUnitTestSuite
## The perk drink as the rules run it (#912, `docs/design/perks.md, "The drink"`): a tonic bought is
## paid at once and had when its drink ends (`PerkTuning.drink_seconds`); a blow meanwhile does not
## stop it; a down spills it, with no perk and no refund; nothing else is sold to full hands.

const STEP := 1.0 / 60.0

var _t: RulesTuning
var _rules: GameRules


func before_test() -> void:
	_t = RulesFixture.tuning()
	_rules = RulesFixture.make_rules(2, 99, _t)
	RulesFixture.into_round_one(_rules)
	_rules.apply(RulesAction.grant_points(1, 20000))


## Buys `item_id` for player 1 through the rules' own action (no drink-down), returns the events.
func _buy(item_id: StringName) -> Array[Dictionary]:
	return _rules.apply(RulesAction.buy(1, item_id))


func test_the_drink_lasts_the_clips_two_and_a_half_seconds() -> void:
	assert_float(_t.perks.drink_seconds).is_equal_approx(2.5, 0.001)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DrinkLayer.SPEC))
	var clip: Dictionary = spec["clips"][String(DrinkLayer.CLIP)]
	assert_float(clip["seconds"]).is_equal_approx(_t.perks.drink_seconds, 0.001)


func test_a_tonic_is_paid_at_once_and_had_when_the_drink_ends() -> void:
	var points := _rules.points_of(1)
	var events := _buy(&"tonic_double_shot")
	var started := RulesFixture.first(events, &"drink_started")
	assert_dict(started).is_not_empty()
	assert_int(started["player_id"]).is_equal(1)
	assert_str(String(started["item_id"])).is_equal("tonic_double_shot")
	assert_float(started["seconds"]).is_equal_approx(2.5, 0.001)
	assert_int(_rules.points_of(1)).is_less(points)
	assert_bool(PerkEffects.has(_rules, 1, ShopItem.Effect.FIRE_RATE)).is_false()
	assert_bool(_rules.players[1].tonics.has(&"tonic_double_shot")).is_false()
	# Just before the end it is still being drunk; the tick that ends it gives the perk.
	var before := RulesFixture.advance(_rules, 2.5 - 2.0 * STEP)
	assert_dict(RulesFixture.first(before, &"drink_finished")).is_empty()
	assert_bool(PerkPlay.is_drinking(_rules.players[1])).is_true()
	var after := RulesFixture.advance(_rules, 3.0 * STEP)
	var finished := RulesFixture.first(after, &"drink_finished")
	assert_int(finished["player_id"]).is_equal(1)
	assert_str(String(finished["item_id"])).is_equal("tonic_double_shot")
	assert_bool(PerkPlay.is_drinking(_rules.players[1])).is_false()
	assert_bool(_rules.players[1].tonics.has(&"tonic_double_shot")).is_true()


func test_the_health_tonic_raises_the_most_health_at_the_end_not_at_the_till() -> void:
	var base := _rules.max_health_of(1)
	var events := _buy(&"tonic_hearty")
	assert_dict(RulesFixture.first(events, &"player_healed")).is_empty()
	assert_float(_rules.max_health_of(1)).is_equal(base)
	var after := RulesFixture.advance(_rules, 2.6)
	var healed := RulesFixture.first(after, &"player_healed")
	assert_str(String(healed["reason"])).is_equal("tonic")
	assert_float(_rules.max_health_of(1)).is_equal(base + 50.0)


func test_a_blow_during_the_drink_hurts_and_the_drink_goes_on() -> void:
	_buy(&"tonic_quick_load")
	RulesFixture.advance(_rules, 1.0)
	var health := _rules.health_of(1)
	_rules.apply(RulesAction.blow(1, 30.0))
	assert_float(_rules.health_of(1)).is_equal(health - 30.0)
	assert_bool(PerkPlay.is_drinking(_rules.players[1])).is_true()
	var after := RulesFixture.advance(_rules, 1.6)
	assert_dict(RulesFixture.first(after, &"drink_finished")).is_not_empty()
	assert_bool(_rules.players[1].tonics.has(&"tonic_quick_load")).is_true()


func test_going_down_during_the_drink_spills_it_with_no_perk_and_no_refund() -> void:
	_buy(&"tonic_reload_shock")
	var points := _rules.points_of(1)
	RulesFixture.advance(_rules, 1.0)
	var events := _rules.apply(RulesAction.blow(1, 999.0))
	var spilled := RulesFixture.first(events, &"drink_spilled")
	assert_int(spilled["player_id"]).is_equal(1)
	assert_str(String(spilled["item_id"])).is_equal("tonic_reload_shock")
	assert_bool(PerkPlay.is_drinking(_rules.players[1])).is_false()
	assert_int(_rules.points_of(1)).is_equal(points)
	var later := RulesFixture.advance(_rules, 2.0)
	assert_dict(RulesFixture.first(later, &"drink_finished")).is_empty()
	assert_bool(_rules.players[1].tonics.has(&"tonic_reload_shock")).is_false()


func test_a_forced_down_spills_it_too_and_the_perks_had_are_lost_as_before() -> void:
	RulesFixture.buy(_rules, 1, &"tonic_double_shot")
	_buy(&"tonic_quick_load")
	var events := _rules.apply(RulesAction.set_downed(1, true))
	assert_dict(RulesFixture.first(events, &"drink_spilled")).is_not_empty()
	var lost := RulesFixture.first(events, &"perks_lost")
	assert_array(lost["lost"]).contains_exactly([&"tonic_double_shot"])


func test_full_hands_buy_nothing_until_the_drink_is_down() -> void:
	_buy(&"tonic_double_shot")
	for item_id: StringName in [&"tonic_quick_load", &"tonic_double_shot"]:
		var denied := RulesFixture.first(_buy(item_id), &"purchase_denied")
		assert_int(denied["result"]).is_equal(GameRules.BuyResult.DRINKING)
	RulesFixture.advance(_rules, 2.6)
	assert_int(RulesFixture.buy(_rules, 1, &"tonic_quick_load")).is_equal(GameRules.BuyResult.OK)
	assert_int(RulesFixture.buy(_rules, 1, &"tonic_double_shot")).is_equal(
		GameRules.BuyResult.ALREADY_OWNED
	)


func test_a_drink_under_way_survives_a_snapshot() -> void:
	_buy(&"tonic_third_holster")
	RulesFixture.advance(_rules, 1.0)
	var copy := GameRules.new(_t, 1)
	assert_str(String(copy.from_dict(_rules.to_dict()))).is_empty()
	assert_str(String(copy.players[1].drinking)).is_equal("tonic_third_holster")
	assert_float(copy.players[1].drink_left).is_equal_approx(_rules.players[1].drink_left, 0.0001)
	var after := RulesFixture.advance(copy, 1.6)
	assert_dict(RulesFixture.first(after, &"drink_finished")).is_not_empty()
	assert_bool(copy.players[1].tonics.has(&"tonic_third_holster")).is_true()


func test_no_drink_time_gives_the_perk_at_once() -> void:
	_t.perks.drink_seconds = 0.0
	var events := _buy(&"tonic_hearty")
	assert_dict(RulesFixture.first(events, &"drink_started")).is_empty()
	assert_dict(RulesFixture.first(events, &"player_healed")).is_not_empty()
	assert_bool(_rules.players[1].tonics.has(&"tonic_hearty")).is_true()
