extends GdUnitTestSuite
## The six perks as the rules and the combat server run them (`docs/design/perks.md`): the table,
## what each one does, what going down costs, and the revive perk's own revive.

const PERKS: Array[StringName] = [
	&"tonic_hearty",
	&"tonic_double_shot",
	&"tonic_quick_load",
	&"tonic_third_holster",
	&"tonic_swift_rescue",
	&"tonic_reload_shock",
]
## Names of another game's perks, in pieces so this file does not hold them whole: none may be in
## the shop table.
const NOT_OURS: Array[String] = [
	"jugger",
	"double tap",
	"speed cola",
	"mule",
	"quick revive",
	"electric",
	"cherry",
]

var _t: RulesTuning
var _rules: GameRules


func before_test() -> void:
	_t = RulesFixture.tuning()
	_rules = RulesFixture.make_rules(2, 99, _t)
	RulesFixture.into_round_one(_rules)
	_rules.apply(RulesAction.grant_points(1, 20000))
	_rules.apply(RulesAction.grant_points(2, 20000))


func _buy(player_id: int, item_id: StringName) -> void:
	assert_int(RulesFixture.buy(_rules, player_id, item_id)).is_equal(GameRules.BuyResult.OK)


func _server(rules: GameRules) -> CombatServer:
	return WeaponsFixture.make_server(rules)


func test_every_perk_is_a_tonic_with_an_effect_a_name_and_a_price() -> void:
	var effects := {}
	for id in PERKS:
		var item := _t.economy.item(id)
		assert_object(item).is_not_null()
		assert_int(item.kind).is_equal(ShopItem.Kind.TONIC)
		assert_int(item.effect).is_not_equal(ShopItem.Effect.NONE)
		assert_str(item.display_name).is_not_empty()
		assert_int(item.price).is_greater(0)
		effects[item.effect] = true
	assert_int(effects.size()).is_equal(PERKS.size())
	assert_int(PerkEffects.tonic_ids(_t.economy).size()).is_equal(PERKS.size())


func test_no_perk_carries_a_name_of_another_game() -> void:
	for item in _t.economy.items:
		var text := ("%s %s" % [item.id, item.display_name]).to_lower().replace("_", " ")
		for banned in NOT_OURS:
			assert_bool(text.contains(banned)).override_failure_message(text).is_false()


func test_the_per_player_limit_is_in_the_rules_and_a_player_loses_perks_when_down() -> void:
	assert_int(_t.economy.max_tonics).is_between(3, 6)
	assert_int(_t.perks.lost_on_down).is_equal(PerkTuning.Loss.ALL)


func test_more_health_raises_the_most_and_a_down_takes_it_away_again() -> void:
	var base := _rules.max_health_of(1)
	_buy(1, &"tonic_hearty")
	assert_float(_rules.max_health_of(1)).is_equal(base + 50.0)
	var events := _rules.apply(RulesAction.blow(1, 999.0))
	var lost := RulesFixture.first(events, &"perks_lost")
	assert_array(lost["lost"]).contains_exactly([&"tonic_hearty"])
	assert_float(_rules.max_health_of(1)).is_equal(base)
	assert_array(_rules.players[1].tonics).is_empty()


func test_faster_fire_shortens_the_wait_between_shots() -> void:
	var def := WeaponCatalog.get_def(&"pistol")
	var server := _server(_rules)
	server.apply(CombatAction.give_weapon(1, &"pistol"))
	var plain := server.weapon_of(1)
	plain.fire(PerkEffects.fire_interval_scale(_rules, 1))
	var before := plain.cooldown
	assert_float(before).is_equal_approx(def.fire_interval, 0.0001)
	_buy(1, &"tonic_double_shot")
	plain.cooldown = 0.0
	plain.fire(PerkEffects.fire_interval_scale(_rules, 1))
	assert_float(plain.cooldown).is_equal_approx(
		def.fire_interval / _t.perks.fire_rate_multiplier, 0.0001
	)
	# The other player, with no perk, still waits the whole time.
	assert_float(PerkEffects.fire_interval_scale(_rules, 2)).is_equal(1.0)


func test_a_shot_through_the_server_is_ready_again_sooner_with_the_perk() -> void:
	_buy(1, &"tonic_double_shot")
	var server := _server(_rules)
	server.apply(CombatAction.give_weapon(1, &"smg"))
	server.apply(CombatAction.give_weapon(2, &"smg"))
	var from := Vector3(0.0, 1.1, 8.0)
	var to := Vector3(0.0, 1.1, 0.0)
	for player_id in [1, 2]:
		server.apply(WeaponsFixture.fire_at(player_id, 1, from, to))
	var interval := WeaponCatalog.get_def(&"smg").fire_interval
	var step := 1.0 / 60.0
	# After 70% of the interval the perk's player can fire, the other cannot yet.
	for _i in ceili(interval * 0.7 / step):
		server.apply(CombatAction.tick(step))
	assert_str(server.weapon_of(1).fire_block()).is_equal("")
	assert_str(server.weapon_of(2).fire_block()).is_equal("cooldown")


func test_faster_reload_takes_half_the_time_and_the_event_says_so() -> void:
	var server := _server(_rules)
	for player_id in [1, 2]:
		server.apply(CombatAction.give_weapon(player_id, &"rifle"))
		server.weapon_of(player_id).ammo = 1
	_buy(1, &"tonic_quick_load")
	var def := WeaponCatalog.get_def(&"rifle")
	var mine := WeaponsFixture.of(server.apply(CombatAction.reload_weapon(1)), &"reload_started")
	var theirs := WeaponsFixture.of(server.apply(CombatAction.reload_weapon(2)), &"reload_started")
	assert_float(mine[0]["seconds"]).is_equal_approx(
		def.reload_time * _t.perks.reload_time_scale, 0.0001
	)
	assert_float(theirs[0]["seconds"]).is_equal_approx(def.reload_time, 0.0001)
	# It really finishes in that time.
	var step := 1.0 / 60.0
	for _i in ceili(mine[0]["seconds"] / step) + 2:
		server.apply(CombatAction.tick(step))
	assert_bool(server.weapon_of(1).is_reloading()).is_false()
	assert_bool(server.weapon_of(2).is_reloading()).is_true()


func test_a_third_weapon_is_carried_only_with_the_perk() -> void:
	var server := _server(_rules)
	for id in [&"pistol", &"smg", &"shotgun"]:
		server.apply(CombatAction.give_weapon(2, id))
	assert_int(server.carried(2).size()).is_equal(WeaponCatalog.CARRY_LIMIT)
	_buy(1, &"tonic_third_holster")
	for id in [&"pistol", &"smg", &"shotgun"]:
		server.apply(CombatAction.give_weapon(1, id))
	assert_array(server.carried(1)).has_size(WeaponCatalog.CARRY_LIMIT + 1)
	assert_int(PerkEffects.carry_limit(_rules, 1)).is_equal(3)


func test_the_rules_keep_three_weapons_with_the_perk_and_give_the_third_up_on_a_down() -> void:
	_buy(1, &"tonic_third_holster")
	_buy(1, &"weapon_shotgun")
	_buy(1, &"weapon_rifle")
	var player: PlayerState = _rules.players[1]
	assert_array(player.weapons).has_size(3)
	var last: StringName = player.weapons[2]
	var server := _server(_rules)
	for id in player.weapons:
		server.apply(CombatAction.give_weapon(1, WeaponCatalog.catalog_id(id)))
	assert_array(server.carried(1)).has_size(3)
	var events := _rules.apply(RulesAction.blow(1, 999.0))
	var lost := RulesFixture.first(events, &"perks_lost")
	assert_array(lost["weapons"]).contains_exactly([last])
	assert_array(player.weapons).has_size(2)
	# The combat server heard the same event through the rules' signal.
	assert_array(server.carried(1)).has_size(2)
	assert_bool(server.carried(1).has(WeaponCatalog.catalog_id(last))).is_false()
	assert_object(server.weapon_of(1)).is_not_null()


func test_the_revive_perk_halves_the_hold_of_its_holder_not_of_the_downed() -> void:
	var plain := _t.health.revive_seconds
	assert_float(PerkEffects.revive_seconds(_rules, 1)).is_equal(plain)
	_buy(1, &"tonic_swift_rescue")
	assert_float(PerkEffects.revive_seconds(_rules, 1)).is_equal_approx(
		plain * _t.perks.revive_time_scale, 0.0001
	)
	assert_float(PerkEffects.revive_seconds(_rules, 2)).is_equal(plain)


func test_a_lone_player_with_the_revive_perk_gets_themselves_up_without_losing_perks() -> void:
	var solo := RulesFixture.make_rules(1, 5, _t)
	RulesFixture.into_round_one(solo)
	solo.apply(RulesAction.grant_points(1, 20000))
	RulesFixture.buy(solo, 1, &"tonic_swift_rescue")
	RulesFixture.buy(solo, 1, &"tonic_hearty")
	var events := solo.apply(RulesAction.blow(1, 999.0))
	assert_bool(RulesFixture.first(events, &"player_downed").is_empty()).is_false()
	assert_bool(RulesFixture.first(events, &"perks_lost").is_empty()).is_true()
	assert_bool(RulesFixture.first(events, &"game_over").is_empty()).is_true()
	assert_int(solo.phase).is_equal(GameRules.Phase.ACTIVE)
	var caused := RulesFixture.advance(solo, _t.perks.self_revive_seconds + 0.5)
	assert_bool(RulesFixture.first(caused, &"self_revive_started").is_empty()).is_false()
	var up := RulesFixture.first(caused, &"player_revived")
	assert_bool(up["self"]).is_true()
	assert_bool(solo.players[1].downed).is_false()
	var healed := RulesFixture.first(caused, &"player_healed")
	assert_float(healed["health"]).is_equal(solo.max_health_of(1) * _t.health.revive_fraction)
	assert_array(solo.players[1].tonics).has_size(2)
	assert_int(solo.players[1].self_revives).is_equal(1)


func test_the_self_revive_runs_out_after_its_uses_and_then_the_night_ends() -> void:
	var solo := RulesFixture.make_rules(1, 5, _t)
	RulesFixture.into_round_one(solo)
	solo.apply(RulesAction.grant_points(1, 20000))
	RulesFixture.buy(solo, 1, &"tonic_swift_rescue")
	for _use in _t.perks.self_revive_uses:
		solo.apply(RulesAction.blow(1, 999.0))
		RulesFixture.advance(solo, _t.perks.self_revive_seconds + 0.5)
		assert_bool(solo.players[1].downed).is_false()
	var events := solo.apply(RulesAction.blow(1, 999.0))
	assert_bool(RulesFixture.first(events, &"game_over").is_empty()).is_false()
	assert_int(solo.phase).is_equal(GameRules.Phase.OVER)


func test_without_the_perk_a_lone_player_down_ends_the_night() -> void:
	var solo := RulesFixture.make_rules(1, 5, _t)
	RulesFixture.into_round_one(solo)
	var events := solo.apply(RulesAction.blow(1, 999.0))
	assert_bool(RulesFixture.first(events, &"game_over").is_empty()).is_false()


func test_a_teammate_on_their_feet_means_no_self_revive() -> void:
	_buy(1, &"tonic_swift_rescue")
	_rules.apply(RulesAction.blow(1, 999.0))
	# The perk was lost with the down (a teammate could have raised them), and nobody self-revives.
	assert_array(_rules.players[1].tonics).is_empty()
	var caused := RulesFixture.advance(_rules, _t.perks.self_revive_seconds + 1.0)
	assert_bool(RulesFixture.first(caused, &"self_revive_started").is_empty()).is_true()
	assert_bool(_rules.players[1].downed).is_true()


func test_a_perk_is_bought_once_and_the_limit_holds() -> void:
	_buy(1, &"tonic_hearty")
	assert_int(RulesFixture.buy(_rules, 1, &"tonic_hearty")).is_equal(
		GameRules.BuyResult.ALREADY_OWNED
	)
	_t.economy.max_tonics = 2
	var capped := RulesFixture.make_rules(1, 3, _t)
	RulesFixture.into_round_one(capped)
	capped.apply(RulesAction.grant_points(1, 20000))
	RulesFixture.buy(capped, 1, &"tonic_hearty")
	RulesFixture.buy(capped, 1, &"tonic_double_shot")
	assert_int(RulesFixture.buy(capped, 1, &"tonic_quick_load")).is_equal(
		GameRules.BuyResult.LIMIT_REACHED
	)


func test_the_snapshot_keeps_the_self_revives_and_a_restored_copy_agrees() -> void:
	var solo := RulesFixture.make_rules(1, 5, _t)
	RulesFixture.into_round_one(solo)
	solo.apply(RulesAction.grant_points(1, 20000))
	RulesFixture.buy(solo, 1, &"tonic_swift_rescue")
	solo.apply(RulesAction.blow(1, 999.0))
	RulesFixture.advance(solo, 1.0)
	var copy := RulesFixture.make_rules(0, 5, _t)
	assert_str(String(copy.from_dict(solo.to_dict()))).is_empty()
	assert_float(copy.players[1].self_revive_left).is_equal(solo.players[1].self_revive_left)
	assert_float(copy.players[1].self_revive_left).is_greater(0.0)
