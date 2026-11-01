extends GdUnitTestSuite
## Rounds put into a reserve from outside (the shop), and the swap between carried weapons.

var _server: CombatServer


func before_test() -> void:
	_server = WeaponsFixture.make_server()
	_server.apply(CombatAction.give_weapon(1, &"pistol"))


func test_ammo_goes_into_the_reserve_and_is_reported() -> void:
	_server.state_of(1, &"pistol").reserve = 10
	var events := _server.apply(CombatAction.add_ammo(1, &"pistol", 20))
	var added := WeaponsFixture.of(events, &"ammo_added")[0]
	assert_int(added["added"]).is_equal(20)
	assert_int(added["reserve"]).is_equal(30)
	assert_int(_server.state_of(1, &"pistol").reserve).is_equal(30)


func test_the_reserve_never_passes_the_weapons_limit() -> void:
	var def := WeaponsFixture.def(&"pistol")
	_server.state_of(1, &"pistol").reserve = def.reserve_max - 3
	var added := (
		WeaponsFixture.of(_server.apply(CombatAction.add_ammo(1, &"pistol", 50)), &"ammo_added")[0]
	)
	assert_int(added["added"]).is_equal(3)
	assert_int(_server.state_of(1, &"pistol").reserve).is_equal(def.reserve_max)


func test_ammo_for_a_weapon_not_carried_is_refused() -> void:
	var events := _server.apply(CombatAction.add_ammo(1, &"rifle", 10))
	assert_array(WeaponsFixture.of(events, &"ammo_added")).is_empty()
	assert_str(WeaponsFixture.of(events, &"action_rejected")[0]["reason"]).is_equal("not_carried")


func test_a_crowbar_takes_no_ammo() -> void:
	_server.apply(CombatAction.give_weapon(1, &"crowbar"))
	var added := (
		WeaponsFixture.of(_server.apply(CombatAction.add_ammo(1, &"crowbar", 10)), &"ammo_added")[0]
	)
	assert_int(added["added"]).is_equal(0)


func test_ammo_does_not_fill_the_magazine_only_a_reload_does() -> void:
	var state := _server.state_of(1, &"pistol")
	state.ammo = 2
	state.reserve = 0
	_server.apply(CombatAction.add_ammo(1, &"pistol", 8))
	assert_int(state.ammo).is_equal(2)
	assert_int(state.reserve).is_equal(8)


func test_swap_goes_to_the_next_weapon_and_round_again() -> void:
	_server.apply(CombatAction.give_weapon(1, &"shotgun"))
	assert_str(_server.weapon_of(1).def.id).is_equal("shotgun")
	var events := _server.apply(CombatAction.swap(1))
	assert_str(WeaponsFixture.of(events, &"weapon_equipped")[0]["weapon_id"]).is_equal("pistol")
	_server.apply(CombatAction.give_weapon(1, &"rifle"))
	var seen: Array = []
	for _i in 3:
		_server.apply(CombatAction.swap(1))
		seen.append(_server.weapon_of(1).def.id)
	assert_array(seen).contains_exactly([&"pistol", &"shotgun", &"rifle"])


func test_swap_with_one_weapon_does_nothing() -> void:
	var events := _server.apply(CombatAction.swap(1))
	assert_array(events).is_empty()
	assert_str(_server.weapon_of(1).def.id).is_equal("pistol")


func test_swap_puts_away_a_reload_in_progress() -> void:
	_server.apply(CombatAction.give_weapon(1, &"shotgun"))
	var shotgun := _server.weapon_of(1)
	shotgun.ammo = 0
	_server.apply(CombatAction.reload_weapon(1))
	assert_bool(shotgun.is_reloading()).is_true()
	_server.apply(CombatAction.swap(1))
	assert_bool(shotgun.is_reloading()).is_false()


func test_swap_for_a_player_with_nothing_does_nothing() -> void:
	assert_array(_server.apply(CombatAction.swap(9))).is_empty()
