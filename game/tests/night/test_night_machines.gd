# What a player standing at the lot's two machines is offered and gets (docs/design/upgrades.md):
# the re-cut bench re-cuts the weapon in hand, the soda fountain pours the hearty tonic, both
# through the same `use` that buys a door, with the server deciding and every client seeing it.
extends GdUnitTestSuite

## What a re-cut costs, every time (#909).
const RECUT_PRICE := 5000


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 9000))
	NightFixture.run(night, 2)
	return night


func _spot(night: Night, kind: StringName) -> Vector3:
	for spot in night.world.shop_spots():
		if spot["kind"] == kind:
			return spot["position"]
	return Vector3.INF


func _stand_at(night: Night, at: Vector3) -> Dictionary:
	night.player().teleport(at + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 3)
	return night.state.me()["prompt"]


func _use(night: Night) -> void:
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)
	NightFixture.drink_down(night)  # a perk bought is had when its drink ends (#912)


func test_the_bench_offers_to_re_cut_the_revolver_in_hand_at_the_rules_price() -> void:
	var night := await _start()
	var prompt := _stand_at(night, _spot(night, &"upgrade"))
	assert_str(String(prompt["kind"])).is_equal("recut")
	assert_str(String(prompt["weapon"])).is_equal("pistol")
	assert_int(prompt["price"]).is_equal(night.server.rules.price_of(&"upgrade_weapon", 1))
	night.queue_free()


func test_a_press_re_cuts_the_weapon_charges_and_fills_it() -> void:
	var night := await _start()
	_stand_at(night, _spot(night, &"upgrade"))
	var before := night.state.points()
	var price := night.server.rules.price_of(&"upgrade_weapon", 1)
	var plain := WeaponCatalog.get_def(&"pistol")
	_use(night)
	assert_int(night.state.points()).is_equal(before - price)
	var state := night.server.combat.state_of(1, &"pistol")
	assert_int(state.tier()).is_equal(1)
	assert_float(state.def.damage).is_equal(
		plain.damage * night.server.rules.tuning.upgrade.profile_of(&"pistol").damage_multiplier
	)
	assert_int(state.ammo).is_equal(state.def.magazine_size)
	assert_int(state.reserve).is_equal(state.def.reserve_max)
	# The frame says so too, and the next prompt says it is done.
	assert_int(night.state.me()["arms"][&"pistol"][2]).is_equal(1)
	assert_str(String(night.state.me()["prompt"]["kind"])).is_equal("recut_done")
	night.queue_free()


func test_the_bench_asks_5000_for_the_first_the_second_and_the_third_weapon() -> void:
	# #909: the price did not grow with the weapons re-cut (1500, 3000, 4500 before).
	var night := await _start()
	night.server.rules.apply(RulesAction.grant_points(1, 20000))
	_stand_at(night, _spot(night, &"upgrade"))
	var held: Array[StringName] = [&"pistol", &"smg", &"shotgun"]
	for weapon in held:
		night.server.combat.apply(CombatAction.give_weapon(1, weapon))
		var prompt := _stand_at(night, _spot(night, &"upgrade"))
		assert_str(String(prompt["kind"])).is_equal("recut")
		assert_int(prompt["price"]).is_equal(RECUT_PRICE)
		var before := night.state.points()
		_use(night)
		assert_int(before - night.state.points()).is_equal(RECUT_PRICE)
		assert_int(night.server.combat.state_of(1, weapon).tier()).is_equal(1)
	night.queue_free()


func test_a_second_press_on_a_re_cut_weapon_is_refused_with_the_rule_and_costs_nothing() -> void:
	var night := await _start()
	_stand_at(night, _spot(night, &"upgrade"))
	_use(night)
	var prompt: Dictionary = night.state.me()["prompt"]
	assert_str(String(prompt["kind"])).is_equal("recut_done")
	var before := night.state.points()
	_use(night)
	_use(night)
	assert_int(night.state.points()).is_equal(before)
	assert_int(night.server.combat.state_of(1, &"pistol").tier()).is_equal(1)
	# The rules refuse it too, for a client that asks anyway.
	var events := night.server.buy(1, &"upgrade_weapon")
	assert_int(RulesFixture.first(events, &"purchase_denied")["result"]).is_equal(
		GameRules.BuyResult.ALREADY_OWNED
	)
	night.queue_free()


func test_a_re_cut_weapon_hurts_by_the_multiplier_in_the_real_combat() -> void:
	var night := await _start()
	_stand_at(night, _spot(night, &"upgrade"))
	_use(night)
	var def := night.server.combat.weapon_of(1).def
	assert_float(DamageModel.damage(def, 0.0, &"body")).is_equal(
		(
			WeaponCatalog.get_def(&"pistol").damage
			* night.server.rules.tuning.upgrade.profile_of(&"pistol").damage_multiplier
		)
	)
	night.queue_free()


func test_the_crowbar_has_nothing_to_re_cut_and_a_press_costs_nothing() -> void:
	var night := await _start()
	night.server.combat.apply(CombatAction.give_weapon(1, &"crowbar"))
	var prompt := _stand_at(night, _spot(night, &"upgrade"))
	assert_str(String(prompt["kind"])).is_equal("recut_none")
	var before := night.state.points()
	_use(night)
	assert_int(night.state.points()).is_equal(before)
	night.queue_free()


func test_without_the_points_the_bench_refuses_and_nothing_changes() -> void:
	var night := await _start()
	night.server.rules.apply(RulesAction.grant_points(1, 1))
	var rules := night.server.rules
	rules.players[1].points = 10
	_stand_at(night, _spot(night, &"upgrade"))
	_use(night)
	assert_int(night.server.combat.state_of(1, &"pistol").tier()).is_equal(0)
	assert_int(night.state.points()).is_equal(10)
	night.queue_free()


func test_the_fountain_offers_the_hearty_tonic_and_a_press_raises_the_health() -> void:
	var night := await _start()
	var prompt := _stand_at(night, _spot(night, &"perk"))
	assert_str(String(prompt["kind"])).is_equal("tonic")
	assert_int(prompt["price"]).is_equal(1000)
	var rules := night.server.rules
	var most := rules.max_health_of(1)
	_use(night)
	assert_float(rules.max_health_of(1)).is_equal(most + 50.0)
	assert_float(rules.health_of(1)).is_equal(most + 50.0)
	assert_str(String(night.state.me()["prompt"]["kind"])).is_equal("tonic_owned")
	night.queue_free()


func test_the_two_machines_are_not_in_reach_of_each_other_or_the_lockers() -> void:
	var night := await _start()
	var bench := _spot(night, &"upgrade")
	var fountain := _spot(night, &"perk")
	assert_float(Vector2(bench.x - fountain.x, bench.z - fountain.z).length()).is_greater(
		night.server.tuning.use_reach
	)
	night.queue_free()


func test_a_re_cut_plays_the_bench_and_a_tonic_plays_the_fountain_on_every_client() -> void:
	var night := await _start()
	var bench := get_tree().get_nodes_in_group(RecutMachine.GROUP)[0] as RecutMachine
	var fountain := get_tree().get_nodes_in_group(SodaFountain.GROUP)[0] as SodaFountain
	assert_bool(bench.is_playing()).is_false()
	_stand_at(night, _spot(night, &"upgrade"))
	_use(night)
	assert_bool(bench.is_playing()).is_true()
	assert_str(String(bench.shown_weapon())).is_equal("pistol")
	_stand_at(night, _spot(night, &"perk"))
	_use(night)
	assert_bool(fountain.is_playing()).is_true()
	night.queue_free()
