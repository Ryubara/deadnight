extends GdUnitTestSuite
## The balance simulator plays with finite ammunition: a reserve that only shrinks by firing and
## grows by buying, the same reload the combat server does, a crowbar for when everything is dry.


func _night(
	tuning: RulesTuning, skill: StringName = SimSkill.AVERAGE, seed_value: int = 11
) -> NightSim:
	var sim := NightSim.new(tuning, SimSkill.named(skill), 1, seed_value, 0.25)
	sim.run(30)
	return sim


## The shipped table with every ammunition item priced out of reach.
func _no_ammo_for_sale() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	for item in tuning.economy.items:
		if item.kind == ShopItem.Kind.AMMO:
			item.price = 10_000_000
	return tuning


func test_a_player_starts_with_the_revolver_alone_and_the_reserve_the_weapon_gives() -> void:
	var sim := NightSim.new(RulesFixture.tuning(), SimSkill.named(SimSkill.AVERAGE), 1, 1, 0.25)
	var player: NightSim.SimPlayer = sim._players[1]
	# The crowbar was replaced by the quick melee (#411): the blow every player has, not an arm.
	assert_array(player.arms.keys()).contains_exactly([&"pistol"])
	assert_str(player.knife.id).is_equal("quick_melee")
	assert_str(player.weapon).is_equal("pistol")
	var pistol := WeaponCatalog.get_def(&"pistol")
	assert_int(player.arms[&"pistol"].mag).is_equal(pistol.magazine_size)
	assert_int(player.arms[&"pistol"].reserve).is_equal(pistol.reserve_start)


func test_a_reload_moves_what_the_combat_servers_reload_moves() -> void:
	var def := WeaponCatalog.get_def(&"rifle")
	for spec: Array in [[0, 32], [3, 32], [0, 5], [8, 0], [2, 1]]:
		var arm := NightSim.SimArm.of(&"rifle")
		arm.mag = spec[0]
		arm.reserve = spec[1]
		arm.reload()
		var state := WeaponState.new(def)
		state.ammo = spec[0]
		state.reserve = spec[1]
		state.start_reload()
		state.tick(def.reload_time + 0.1)
		assert_int(arm.mag).is_equal(state.ammo)
		assert_int(arm.reserve).is_equal(state.reserve)


func test_the_best_armed_weapon_skips_what_is_dry_and_falls_back_to_the_quick_melee() -> void:
	var arms: Dictionary[StringName, NightSim.SimArm] = {}
	for id in [&"pistol", &"smg", &"rifle"]:
		arms[id] = NightSim.SimArm.of(id)
	# The pick is sized against the walker the round sends. Without a health it is raw damage a
	# second, and the stepped-up rifle (#254) would now win; against round 1's 50 health the rate
	# of the submachine gun wins, as it does for the player.
	var health := RulesFixture.tuning().rounds.health_for_round(1)
	assert_str(SimWeapons.best_armed(arms, health)).is_equal("smg")
	arms[&"smg"].mag = 0
	arms[&"smg"].reserve = 0
	assert_str(SimWeapons.best_armed(arms, health)).is_equal("rifle")
	for id in [&"pistol", &"rifle"]:
		arms[id].mag = 0
		arms[id].reserve = 0
	assert_str(SimWeapons.best_armed(arms, health)).is_equal("quick_melee")
	assert_bool(SimWeapons.is_melee(&"quick_melee")).is_true()
	# A melee weapon carried is better than the free blow, when it kills faster.
	arms[&"fire_axe"] = NightSim.SimArm.of(&"fire_axe")
	assert_str(SimWeapons.best_armed(arms, health)).is_equal("fire_axe")


func test_reserves_stay_inside_their_limits_all_night() -> void:
	var sim := _night(RulesFixture.tuning(), SimSkill.STRONG)
	for player: NightSim.SimPlayer in sim._players.values():
		for arm: NightSim.SimArm in player.arms.values():
			assert_int(arm.reserve).is_between(0, arm.def().reserve_max)
			assert_int(arm.mag).is_between(0, arm.def().magazine_size)


func test_what_the_simulator_says_it_spent_is_what_the_rules_charged() -> void:
	var sim := _night(RulesFixture.tuning())
	var charged := 0
	for player: PlayerState in sim.rules.players.values():
		charged += player.points_spent
	var said := 0
	for item_id: StringName in sim._result["spent_on"]:
		said += sim._result["spent_on"][item_id]
	assert_int(said).is_equal(charged)


func test_players_buy_ammunition_with_the_shipped_prices() -> void:
	var sim := _night(RulesFixture.tuning())
	var ammo := 0
	for item_id: StringName in sim._result["spent_on"]:
		if String(item_id).begins_with("ammo_"):
			ammo += sim._result["spent_on"][item_id]
	assert_int(ammo).is_greater(0)


## Rounds reached over `seeds` by the same player, a pistol down to two rounds, on `tuning`.
func _mean_rounds_with_a_dry_pistol(tuning_of: Callable, seeds: Array[int]) -> float:
	var total := 0.0
	for seed_value in seeds:
		var sim := NightSim.new(
			tuning_of.call(), SimSkill.named(SimSkill.AVERAGE), 1, seed_value, 0.25
		)
		var player: NightSim.SimPlayer = sim._players[1]
		player.arms[&"pistol"].mag = 2
		player.arms[&"pistol"].reserve = 0
		sim.run(30)
		total += float(sim._result["rounds_reached"])
	return total / float(seeds.size())


func test_a_player_with_no_rounds_and_none_to_buy_fights_with_the_quick_melee() -> void:
	var sim := NightSim.new(_no_ammo_for_sale(), SimSkill.named(SimSkill.AVERAGE), 1, 11, 0.25)
	var player: NightSim.SimPlayer = sim._players[1]
	player.arms[&"pistol"].mag = 2
	player.arms[&"pistol"].reserve = 0
	sim.run(30)
	assert_int(sim._result["dry_rounds"]).is_greater(0)
	# One night's end is mostly chance (with the stepped-up weapons a single seed can go either
	# way), so the cost of the quick melee is read from the mean of eight seeded nights: the same
	# player with ammunition for sale goes further than the one who cannot buy any.
	var seeds: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
	assert_float(_mean_rounds_with_a_dry_pistol(_no_ammo_for_sale, seeds)).is_less(
		_mean_rounds_with_a_dry_pistol(RulesFixture.tuning, seeds)
	)


func test_the_same_player_with_ammunition_for_sale_buys_it_and_does_not_run_dry() -> void:
	var sim := NightSim.new(RulesFixture.tuning(), SimSkill.named(SimSkill.AVERAGE), 1, 11, 0.25)
	var player: NightSim.SimPlayer = sim._players[1]
	player.arms[&"pistol"].mag = 2
	player.arms[&"pistol"].reserve = 0
	sim.run(30)
	assert_int(sim._result["dry_rounds"]).is_equal(0)
	assert_int(sim._result["spent_on"].get(&"ammo_pistol", 0)).is_greater(0)


func test_a_night_with_ammunition_is_repeatable() -> void:
	var first := _night(RulesFixture.tuning(), SimSkill.AVERAGE, 5)
	var second := _night(RulesFixture.tuning(), SimSkill.AVERAGE, 5)
	assert_int(first._result["rounds_reached"]).is_equal(second._result["rounds_reached"])
	assert_dict(first._result["spent_on"]).is_equal(second._result["spent_on"])


func test_ammunition_is_bought_for_the_weapons_worth_shooting_only() -> void:
	var sim := NightSim.new(RulesFixture.tuning(), SimSkill.named(SimSkill.AVERAGE), 1, 1, 0.25)
	var player: NightSim.SimPlayer = sim._players[1]
	for id in [&"smg", &"flare_gun"]:
		player.arms[id] = NightSim.SimArm.of(id)
	# Worth is sized against the round's walker. Against round 1's 50 health the pistol (24, three
	# shots) falls under half of the submachine gun's rate, so it is no longer worth the rounds.
	sim.rules.round_number = 1
	var early := sim._useful(player)
	assert_array(early).contains([&"smg"])
	assert_bool(early.has(&"pistol")).is_false()
	# By round 10 (117 health) the submachine gun needs nine hits too and the pistol is back in.
	sim.rules.round_number = 10
	var useful := sim._useful(player)
	assert_array(useful).contains([&"smg", &"pistol"])
	assert_bool(useful.has(&"flare_gun")).is_false()
	assert_bool(useful.has(&"crowbar")).is_false()
	assert_str(useful[0]).is_equal("smg")
