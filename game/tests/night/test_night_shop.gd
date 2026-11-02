extends GdUnitTestSuite
## What the shop gives in the night: the weapon bought is in the player's hands, ammunition fills
## the reserve of what they carry (and only what fits), and `swap` changes the weapon in hand.


## A night with 5000 points. `tuning` replaces the shipped table (a crane test that is not about
## breakdowns asks for the steady crane: with six prizes the plays run past the safe ones).
func _start(tuning: RulesTuning = null) -> Night:
	# Both hands full from the start, so what a purchase replaces is the suite's subject.
	var night := await NightFixture.start(self, Night.Mode.MANUAL, RulesFixture.full_hands(tuning))
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 5000))
	NightFixture.run(night, 2)
	return night


func _swap(night: Night) -> void:
	var command := NightCommand.new()
	command.swap = true
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 2)


func test_a_wall_weapon_bought_through_the_rules_is_carried_and_in_hand() -> void:
	var night := await _start()
	night.server.rules.apply(RulesAction.buy(1, &"weapon_shotgun"))
	NightFixture.run(night, 2)
	assert_array(night.server.combat.carried(1)).contains([&"shotgun"])
	assert_str(String(night.state.me()["weapon"])).is_equal("shotgun")
	night.queue_free()


func test_every_crane_prize_reaches_the_players_hands() -> void:
	var night := await _start(RulesFixture.steady_crane_tuning())
	var item := night.server.rules.tuning.economy.item(&"crane_play")
	# Two hands (#410): each prize replaces the weapon in hand, and the hands follow the rules.
	for _i in item.pool.size():
		night.server.buy(1, &"crane_play")
		NightFixture.run(night, 300)
		var prize := WeaponCatalog.catalog_id(night.server.rules.crane.weapon)
		night.server.rules.apply(RulesAction.crane_take(1, night.state.me()["weapon"]))
		NightFixture.run(night, 2)
		assert_array(night.server.combat.carried(1)).has_size(WeaponCatalog.CARRY_LIMIT)
		assert_array(night.server.combat.carried(1)).contains([prize])
		assert_str(String(night.state.me()["weapon"])).is_equal(String(prize))
	night.queue_free()


func test_ammunition_fills_the_reserve_and_costs_the_price() -> void:
	var night := await _start()
	var state := night.server.combat.state_of(1, &"pistol")
	state.reserve = 0
	var item := night.server.rules.tuning.economy.item(&"ammo_pistol")
	var before := night.state.points()
	night.server.buy(1, &"ammo_pistol")
	NightFixture.run(night, 2)
	assert_int(state.reserve).is_equal(int(item.amount))
	assert_int(night.state.points()).is_equal(before - item.price)
	assert_int(night.state.me()["reserve"]).is_equal(int(item.amount))
	night.queue_free()


func test_a_reserve_with_little_room_pays_for_little() -> void:
	var night := await _start()
	var state := night.server.combat.state_of(1, &"pistol")
	state.reserve = state.def.reserve_max - 5
	var item := night.server.rules.tuning.economy.item(&"ammo_pistol")
	var before := night.state.points()
	night.server.buy(1, &"ammo_pistol")
	NightFixture.run(night, 2)
	assert_int(state.reserve).is_equal(state.def.reserve_max)
	assert_int(before - night.state.points()).is_equal(ceili(float(item.price) * 5.0 / item.amount))
	night.queue_free()


func test_a_full_reserve_is_refused_and_costs_nothing() -> void:
	var night := await _start()
	var state := night.server.combat.state_of(1, &"pistol")
	state.reserve = state.def.reserve_max
	var before := night.state.points()
	var events := night.server.buy(1, &"ammo_pistol")
	NightFixture.run(night, 2)
	assert_int(night.state.points()).is_equal(before)
	assert_str(events[0]["type"]).is_equal("purchase_denied")
	assert_int(events[0]["result"]).is_equal(GameRules.BuyResult.AMMO_FULL)
	night.queue_free()


func test_ammunition_for_a_weapon_not_carried_is_refused() -> void:
	var night := await _start()
	var before := night.state.points()
	night.server.buy(1, &"ammo_rifle")
	NightFixture.run(night, 2)
	assert_int(night.state.points()).is_equal(before)
	night.queue_free()


func test_ammunition_goes_to_the_weapon_named_not_the_one_in_hand() -> void:
	var night := await _start()
	night.server.rules.apply(RulesAction.buy(1, &"weapon_shotgun", -1, &"crowbar"))
	NightFixture.run(night, 2)
	var pistol := night.server.combat.state_of(1, &"pistol")
	pistol.reserve = 0
	var shotgun := night.server.combat.state_of(1, &"shotgun")
	var shotgun_before := shotgun.reserve
	night.server.buy(1, &"ammo_pistol")
	NightFixture.run(night, 2)
	assert_int(pistol.reserve).is_greater(0)
	assert_int(shotgun.reserve).is_equal(shotgun_before)
	night.queue_free()


func test_swap_changes_the_weapon_in_hand_and_the_frame_lists_the_arms() -> void:
	var night := await _start()
	night.server.buy(1, &"weapon_rifle")
	NightFixture.run(night, 2)
	assert_str(String(night.state.me()["weapon"])).is_equal("rifle")
	var arms: Dictionary = night.state.me()["arms"]
	# The rifle replaced the pistol in hand (#410).
	assert_array(arms.keys()).contains_exactly_in_any_order([&"crowbar", &"rifle"])
	# Magazine, reserve and the tier (0: not re-cut).
	var rifle := WeaponCatalog.get_def(&"rifle")
	assert_array(arms[&"rifle"]).is_equal([rifle.magazine_size, rifle.reserve_start, 0])
	for expected in ["crowbar", "rifle", "crowbar"]:
		_swap(night)
		assert_str(String(night.state.me()["weapon"])).is_equal(expected)
	night.queue_free()


func test_swap_survives_the_wire() -> void:
	var command := NightCommand.new()
	command.swap = true
	assert_bool(NightCommand.from_dict(command.to_dict()).swap).is_true()
	assert_bool(NightCommand.from_dict({}).swap).is_false()
