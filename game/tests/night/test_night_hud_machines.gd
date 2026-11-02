# The HUD at the lot's two machines: the card says what a re-cut gives and costs, the ammo card
# takes the re-cut weapon's name and its bigger magazine and reserve, and a late HUD names it from
# the frame alone (docs/design/upgrades.md).
extends GdUnitTestSuite


func _start() -> Dictionary:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var night := await NightFixture.start(self, Night.Mode.MANUAL, null, 7, hud)
	NightFixture.run(night, 30)
	night.server.rules.apply(RulesAction.grant_points(1, 9000))
	NightFixture.run(night, 2)
	return {"night": night, "hud": hud}


func _finish(night: Night, hud: Hud) -> void:
	night.queue_free()
	hud.queue_free()


func _stand_at(night: Night, kind: StringName) -> void:
	for spot in night.world.shop_spots():
		if spot["kind"] == kind:
			night.player().teleport(spot["position"] + Vector3(0.0, 0.1, 0.0))
			break
	NightFixture.run(night, 3)


func _use(night: Night) -> void:
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)


func test_the_card_at_the_bench_names_the_weapon_the_price_and_what_it_gives() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	_stand_at(night, &"upgrade")
	var prompt := hud.state.prompt
	assert_str(String(prompt["kind"])).is_equal("buy_recut")
	assert_str(prompt["label"]).is_equal("Re-cut: Revolver")
	assert_int(prompt["cost"]).is_equal(night.server.rules.price_of(&"upgrade_weapon", 1))
	var spec := night.server.rules.tuning.upgrade
	assert_str(prompt["detail"]).is_equal(
		"DAMAGE x%s, ROUNDS x%s" % [spec.damage_multiplier, spec.magazine_multiplier]
	)
	_finish(night, hud)


func test_the_ammo_card_takes_the_new_name_and_the_bigger_magazine() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	var plain := WeaponCatalog.get_def(&"pistol")
	assert_str(hud.state.weapon_name).is_equal(plain.display_name)
	_stand_at(night, &"upgrade")
	_use(night)
	var state := night.server.combat.state_of(1, &"pistol")
	assert_str(hud.state.weapon_name).is_equal("Re-Cut " + plain.display_name)
	assert_int(hud.state.ammo_reserve).is_equal(state.def.reserve_max)
	assert_int(hud.state.ammo_magazine).is_equal(state.def.magazine_size)
	assert_str(String(hud.state.prompt["kind"])).is_equal("recut_info")
	_finish(night, hud)


func test_a_hud_that_joins_late_names_the_re_cut_weapon_from_the_frame() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	_stand_at(night, &"upgrade")
	_use(night)
	var late := HudState.new()
	late.local_player_id = 1
	late.weapon_names[&"pistol"] = "Revolver"
	HudLoadout.sync(night.state.me(), late)
	assert_str(HudLoadout.name_of(&"pistol", late)).is_equal("Re-Cut Revolver")
	_finish(night, hud)


func test_the_card_at_the_fountain_says_the_health_it_gives() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	_stand_at(night, &"perk")
	assert_str(String(hud.state.prompt["kind"])).is_equal("buy_tonic")
	assert_str(hud.state.prompt["detail"]).is_equal("+50 MOST HEALTH")
	assert_int(hud.state.prompt["cost"]).is_equal(1000)
	_use(night)
	assert_str(String(hud.state.prompt["kind"])).is_equal("tonic_info")
	# The health bar reads the new most.
	assert_float(hud.state.max_health).is_equal(150.0)
	_finish(night, hud)


func test_a_crowbar_in_hand_says_there_is_nothing_to_re_cut() -> void:
	var made := await _start()
	var night: Night = made["night"]
	var hud: Hud = made["hud"]
	night.server.combat.apply(CombatAction.equip(1, &"crowbar"))
	_stand_at(night, &"upgrade")
	assert_str(hud.state.prompt["detail"]).is_equal("NOTHING TO RE-CUT IN YOUR HAND")
	_finish(night, hud)
