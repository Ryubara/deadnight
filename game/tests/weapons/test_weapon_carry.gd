extends GdUnitTestSuite
## The carry limit (#410): a player holds two weapons, melee ones included; a third replaces the one
## in hand (or the one named), with its rounds, and says so. The weapon is gone, not dropped.

var _server: CombatServer


func before_test() -> void:
	_server = WeaponsFixture.make_server()
	_server.apply(CombatAction.give_weapon(1, &"crowbar"))
	_server.apply(CombatAction.give_weapon(1, &"pistol"))


func _ids() -> Array:
	return _server.carried(1)


func test_two_weapons_are_carried_without_any_replace() -> void:
	assert_array(_ids()).contains_exactly([&"crowbar", &"pistol"])


func test_a_third_weapon_replaces_the_one_in_hand_and_says_so() -> void:
	var events := _server.apply(CombatAction.give_weapon(1, &"shotgun"))
	assert_array(_ids()).contains_exactly([&"crowbar", &"shotgun"])
	var replaced := WeaponsFixture.of(events, &"weapon_replaced")
	assert_int(replaced.size()).is_equal(1)
	assert_str(replaced[0]["dropped"]).is_equal("pistol")
	assert_str(replaced[0]["weapon_id"]).is_equal("shotgun")
	assert_str(_server.weapon_of(1).def.id).is_equal("shotgun")
	assert_str(WeaponsFixture.of(events, &"weapon_equipped")[0]["weapon_id"]).is_equal("shotgun")


func test_the_replace_comes_before_the_new_weapon_is_equipped() -> void:
	var events := _server.apply(CombatAction.give_weapon(1, &"shotgun"))
	var types := events.map(func(e: Dictionary) -> StringName: return e["type"])
	assert_int(types.find(&"weapon_replaced")).is_less(types.find(&"weapon_equipped"))


func test_the_replaced_weapon_is_gone_with_its_rounds_and_cannot_be_equipped() -> void:
	_server.state_of(1, &"pistol").reserve = 77
	_server.apply(CombatAction.give_weapon(1, &"shotgun"))
	assert_object(_server.state_of(1, &"pistol")).is_null()
	var events := _server.apply(CombatAction.equip(1, &"pistol"))
	assert_str(WeaponsFixture.of(events, &"action_rejected")[0]["reason"]).is_equal("not_carried")
	# Taken again later it is a fresh weapon, not the one with 77 rounds.
	_server.apply(CombatAction.give_weapon(1, &"rifle"))
	_server.apply(CombatAction.give_weapon(1, &"pistol"))
	assert_int(_server.state_of(1, &"pistol").reserve).is_equal(
		WeaponsFixture.def(&"pistol").reserve_start
	)


func test_a_weapon_named_to_replace_goes_instead_of_the_one_in_hand() -> void:
	_server.apply(CombatAction.give_weapon(1, &"shotgun", &"crowbar"))
	assert_array(_ids()).contains_exactly([&"pistol", &"shotgun"])
	assert_str(_server.weapon_of(1).def.id).is_equal("shotgun")


func test_the_one_kept_is_the_one_put_away_and_the_swap_cycles_the_two() -> void:
	_server.apply(CombatAction.give_weapon(1, &"shotgun"))
	var seen: Array = []
	for _i in 3:
		_server.apply(CombatAction.swap(1))
		seen.append(_server.weapon_of(1).def.id)
	assert_array(seen).is_equal([&"crowbar", &"shotgun", &"crowbar"])


func test_the_replace_works_while_the_other_weapon_is_in_hand() -> void:
	_server.apply(CombatAction.swap(1))
	assert_str(_server.weapon_of(1).def.id).is_equal("crowbar")
	var events := _server.apply(CombatAction.give_weapon(1, &"rifle"))
	assert_str(WeaponsFixture.of(events, &"weapon_replaced")[0]["dropped"]).is_equal("crowbar")
	assert_array(_ids()).contains_exactly([&"pistol", &"rifle"])


func test_a_melee_weapon_takes_a_slot_like_a_gun() -> void:
	_server.apply(CombatAction.give_weapon(1, &"fire_axe"))
	assert_array(_ids()).contains_exactly([&"crowbar", &"fire_axe"])
	var events := _server.apply(CombatAction.give_weapon(1, &"smg"))
	assert_str(WeaponsFixture.of(events, &"weapon_replaced")[0]["dropped"]).is_equal("fire_axe")


func test_a_weapon_already_carried_tops_up_and_replaces_nothing() -> void:
	_server.state_of(1, &"pistol").reserve = 0
	var events := _server.apply(CombatAction.give_weapon(1, &"pistol"))
	assert_array(WeaponsFixture.of(events, &"weapon_replaced")).is_empty()
	assert_array(_ids()).contains_exactly([&"crowbar", &"pistol"])
	assert_int(_server.state_of(1, &"pistol").reserve).is_greater(0)


func test_a_replace_puts_away_a_reload_in_progress() -> void:
	_server.apply(CombatAction.give_weapon(1, &"shotgun"))
	var shotgun := _server.weapon_of(1)
	shotgun.ammo = 0
	_server.apply(CombatAction.reload_weapon(1))
	assert_bool(shotgun.is_reloading()).is_true()
	_server.apply(CombatAction.give_weapon(1, &"rifle"))
	assert_array(_ids()).contains_exactly([&"crowbar", &"rifle"])
	assert_bool(_server.weapon_of(1).is_reloading()).is_false()
