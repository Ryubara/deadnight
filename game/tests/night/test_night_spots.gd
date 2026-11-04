# What a player standing at a shop spot is offered and gets (docs/design/map.md, Shop spots): the
# weapon on a wall, the crane and the ammunition lockers, through the same `use` that buys a door.
# Also that nothing refills a weapon by itself any more, and that the crowbar is always there.
extends GdUnitTestSuite


func _start(tuning: RulesTuning = null) -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 5000))
	NightFixture.run(night, 2)
	return night


func _spot(night: Night, shop_id: StringName, kind: StringName = &"") -> Vector3:
	for spot in night.world.shop_spots():
		if (shop_id == &"" or spot["shop_id"] == shop_id) and (kind == &"" or spot["kind"] == kind):
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


func test_a_player_starts_with_the_pistol_alone_and_a_free_hand() -> void:
	var night := await _start()
	assert_str(String(night.state.me()["weapon"])).is_equal("house_pistol")
	# The crowbar was replaced by the quick melee (#411), which takes no slot.
	assert_array(night.server.combat.carried(1)).contains_exactly([&"house_pistol"])
	night.queue_free()


func test_the_shotgun_on_the_wall_is_offered_at_its_price_and_bought() -> void:
	var night := await _start()
	var prompt := _stand_at(night, _spot(night, &"weapon_shotgun"))
	assert_str(String(prompt["kind"])).is_equal("weapon")
	assert_str(String(prompt["weapon"])).is_equal("shotgun")
	assert_int(prompt["price"]).is_equal(900)
	var before := night.state.points()
	_use(night)
	assert_int(night.state.points()).is_equal(before - 900)
	assert_str(String(night.state.me()["weapon"])).is_equal("shotgun")
	assert_array(night.server.combat.carried(1)).contains([&"shotgun"])
	night.queue_free()


func test_a_wall_that_sold_its_weapon_sells_its_rounds() -> void:
	var night := await _start()
	var at := _spot(night, &"weapon_shotgun")
	_stand_at(night, at)
	_use(night)
	var shotgun := night.server.combat.state_of(1, &"shotgun")
	shotgun.reserve = 10
	var prompt := _stand_at(night, at)
	assert_str(String(prompt["kind"])).is_equal("ammo")
	assert_str(String(prompt["weapon"])).is_equal("shotgun")
	var item := night.server.rules.tuning.economy.ammo_item_for(&"shotgun")
	assert_int(prompt["rounds"]).is_equal(int(item.amount))
	assert_int(prompt["price"]).is_equal(item.price)
	var before := night.state.points()
	_use(night)
	assert_int(shotgun.reserve).is_equal(10 + int(item.amount))
	assert_int(night.state.points()).is_equal(before - item.price)
	night.queue_free()


func test_a_full_reserve_is_offered_nothing_at_the_wall_or_a_locker() -> void:
	var night := await _start()
	var at := _spot(night, &"weapon_shotgun")
	_stand_at(night, at)
	_use(night)
	var shotgun := night.server.combat.state_of(1, &"shotgun")
	shotgun.reserve = shotgun.def.reserve_max
	assert_dict(_stand_at(night, at)).is_empty()
	# The shotgun is in hand (it replaced the pistol), so the locker has nothing for it either.
	assert_dict(_stand_at(night, _spot(night, &"", &"ammo"))).is_empty()
	night.queue_free()


func test_a_locker_sells_rounds_for_the_gun_in_hand_and_charges_the_part_that_fits() -> void:
	var night := await _start()
	var pistol := night.server.combat.state_of(1, &"house_pistol")
	pistol.reserve = pistol.def.reserve_max - 5
	var prompt := _stand_at(night, _spot(night, &"", &"ammo"))
	assert_str(String(prompt["kind"])).is_equal("ammo")
	assert_str(String(prompt["weapon"])).is_equal("house_pistol")
	assert_int(prompt["rounds"]).is_equal(5)
	var item := night.server.rules.tuning.economy.ammo_item_for(&"house_pistol")
	assert_int(prompt["price"]).is_equal(item.ammo_price(night.server.rules.round_number, 5))
	var before := night.state.points()
	_use(night)
	assert_int(pistol.reserve).is_equal(pistol.def.reserve_max)
	assert_int(before - night.state.points()).is_equal(prompt["price"])
	night.queue_free()


func test_the_grenade_rack_sells_the_grenades_that_fit_the_pack() -> void:
	var night := await _start()
	var rules := night.server.rules
	var rack := _spot(night, &"grenades", &"rack")
	assert_bool(rack != Vector3.INF).is_true()
	# A full pack is offered nothing.
	rules._set_grenades(rules.players[1], rules.tuning.explosives.max_grenades, &"test")
	assert_dict(_stand_at(night, rack)).is_empty()
	# Three of room: two to a purchase, the price a whole purchase's.
	rules._set_grenades(rules.players[1], rules.tuning.explosives.max_grenades - 3, &"test")
	var prompt := _stand_at(night, rack)
	var item := rules.tuning.economy.item(&"grenades")
	assert_str(String(prompt["kind"])).is_equal("grenades")
	assert_int(prompt["count"]).is_equal(int(item.amount))
	assert_int(prompt["price"]).is_equal(item.price_at(rules.round_number))
	var before := night.state.points()
	var held := rules.grenades_of(1)
	_use(night)
	assert_int(rules.grenades_of(1)).is_equal(held + int(item.amount))
	assert_int(before - night.state.points()).is_equal(prompt["price"])
	# One of room: one grenade, at its share of the price.
	var room := rules.tuning.explosives.max_grenades - rules.grenades_of(1)
	assert_int(room).is_equal(1)
	prompt = _stand_at(night, rack)
	assert_int(prompt["count"]).is_equal(1)
	assert_int(prompt["price"]).is_equal(
		ceili(float(item.price_at(rules.round_number)) / item.amount)
	)
	_use(night)
	assert_int(rules.grenades_of(1)).is_equal(rules.tuning.explosives.max_grenades)
	night.queue_free()


func test_a_locker_has_nothing_for_the_crowbar() -> void:
	var night := await _start()
	night.server.combat.apply(CombatAction.give_weapon(1, &"crowbar"))
	assert_dict(_stand_at(night, _spot(night, &"", &"ammo"))).is_empty()
	night.queue_free()


func test_the_crane_never_runs_dry_for_a_player_with_two_hands() -> void:
	var night := await _start(RulesFixture.steady_crane_tuning())
	var at := _spot(night, &"crane_play")
	var prompt := _stand_at(night, at)
	assert_str(String(prompt["kind"])).is_equal("crane")
	assert_int(prompt["price"]).is_equal(night.server.rules.price_of(&"crane_play"))
	var pool := night.server.rules.tuning.economy.item(&"crane_play").pool.size()
	for _i in pool:
		night.server.rules.apply(RulesAction.grant_points(1, 600))
		_use(night)
		# The claw digs, then the weapon is held out for the buyer to take.
		assert_str(String(night.state.me()["prompt"]["kind"])).is_equal("crane_busy")
		NightFixture.run(night, 300)
		assert_str(String(night.state.me()["prompt"]["kind"])).is_equal("crane_take")
		_use(night)
	assert_int(night.server.combat.carried(1).size()).is_equal(WeaponCatalog.CARRY_LIMIT)
	assert_str(String(_stand_at(night, at)["kind"])).is_equal("crane")
	night.queue_free()


func test_the_crane_shows_only_where_it_stands() -> void:
	var night := await _start()
	night.server.rules.crane.spot = 2
	assert_dict(_stand_at(night, _spot(night, &"crane_play"))).is_empty()
	var field := Vector3.INF
	for spot in night.world.shop_spots():
		if spot["kind"] == &"crane" and spot["crane_spot"] == 2:
			field = spot["position"]
	assert_str(String(_stand_at(night, field)["kind"])).is_equal("crane")
	night.queue_free()


func test_away_from_every_spot_there_is_nothing_to_use() -> void:
	var night := await _start()
	assert_dict(_stand_at(night, Vector3(0.0, 0.0, -43.0))).is_empty()
	night.queue_free()


func test_nothing_refills_a_weapon_when_a_round_ends() -> void:
	var night := await _start()
	var pistol := night.server.combat.state_of(1, &"house_pistol")
	pistol.reserve = 3
	NightFixture.first_zombie(night)
	night.server.rules._plan.clear()
	for zombie_id in night.server.rules.zombie_ids():
		night.server.rules.apply(RulesAction.zombie_gone(zombie_id))
	NightFixture.run(night, 5)
	assert_int(night.state.round_number()).is_equal(1)
	assert_int(night.server.rules.phase).is_equal(GameRules.Phase.BREAK)
	assert_int(pistol.reserve).is_equal(3)
	night.queue_free()


func test_the_crowbar_in_hand_swings_and_pays_the_melee_kill() -> void:
	var night := await _start()
	var zombie_id := NightFixture.first_zombie(night)
	var body: ZombieBody = night.server.sim.zombies[zombie_id]
	night.server.combat.apply(CombatAction.give_weapon(1, &"crowbar"))
	NightFixture.run(night, 3)
	assert_str(String(night.state.me()["weapon"])).is_equal("crowbar")
	var heard: Array[Dictionary] = []
	night.state.event_received.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"damage_dealt":
				heard.append(e)
	)
	var spot := night.state.position() + Vector3(0.0, 0.0, -1.2)
	for _i in 40:
		body.position = spot
		body.velocity = Vector3.ZERO
		NightFixture.run(night, 1, NightFixture.shoot_at(night, spot))
	assert_array(heard).is_not_empty()
	assert_bool(heard[0]["melee"]).is_true()
	night.queue_free()
