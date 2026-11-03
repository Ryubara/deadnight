# What a person buys on the second map, with real use presses at the real spots: every weapon on a
# wall at its price (and its rounds once carried), the cabinet's rifle, the ammunition lockers, and
# the box (our crane): one place in the side room, a play for a price, a prize that is not a weapon
# already carried, and a box that never moves however often it is played.
extends GdUnitTestSuite

var _night: Night


func after_test() -> void:
	if _night != null:
		_night.queue_free()
		_night = null


func _start() -> Night:
	_night = await SmallMapNight.start(self)
	SmallMapNight.run(_night, 30)
	_night.server.rules.apply(RulesAction.grant_points(1, 50000))
	return _night


func _spots(kind: StringName) -> Array[Dictionary]:
	return _night.world.shop_spots().filter(
		func(spot: Dictionary) -> bool: return spot["kind"] == kind
	)


func _price(item_id: StringName) -> int:
	return _night.server.rules.tuning.economy.item(item_id).price


## Opens every link, so each room can be walked to.
func _open_all() -> void:
	for item in _night.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			RulesFixture.buy(_night.server.rules, 1, item.id)
	await SmallMapNight.map_reaches(_night, Vector3(5.0, 3.4, -4.0))


func test_every_wall_weapon_is_offered_at_its_price_and_bought_with_use() -> void:
	await _start()
	var rules := _night.server.rules
	for spot in _spots(&"wall"):
		var id: StringName = spot["shop_id"]
		# Both hands free for the test: the player starts with the revolver alone.
		rules.players[1].weapons.assign([&"weapon_pistol"])
		if id == &"weapon_pistol":
			continue
		SmallMapNight.stand_at(_night, spot["position"])
		var prompt: Dictionary = _night.state.me()["prompt"]
		(
			assert_str(String(prompt.get("id", "")))
			. override_failure_message(
				"%s: nothing offered at %s (%s)" % [id, spot["position"], prompt]
			)
			. is_equal(String(id))
		)
		assert_int(int(prompt["price"])).is_equal(_price(id))
		var before := rules.points_of(1)
		SmallMapNight.press_use(_night)
		assert_int(before - rules.points_of(1)).override_failure_message(String(id)).is_equal(
			_price(id)
		)
		assert_array(rules.players[1].weapons).contains([id])


func test_a_wall_sells_the_rounds_of_a_weapon_already_carried() -> void:
	await _start()
	var rules := _night.server.rules
	var spot := (
		_spots(&"wall").filter(func(s: Dictionary) -> bool: return s["shop_id"] == &"weapon_shotgun")[0]
		as Dictionary
	)
	SmallMapNight.stand_at(_night, spot["position"])
	SmallMapNight.press_use(_night)
	assert_array(rules.players[1].weapons).contains([&"weapon_shotgun"])
	# Spend some rounds, then the same wall sells them back.
	var state := _night.server.combat.state_of(1, &"shotgun")
	state.reserve = 0
	_night.server.rules.apply(RulesAction.grant_points(1, 0))
	SmallMapNight.run(_night, 6)
	var prompt: Dictionary = _night.state.me()["prompt"]
	assert_str(String(prompt.get("kind", ""))).is_equal("ammo")


func test_the_cabinet_sells_the_rifle_upstairs_and_not_to_a_player_below_it() -> void:
	await _start()
	await _open_all()
	var cabinet := (
		_spots(&"wall").filter(func(s: Dictionary) -> bool: return s["shop_id"] == &"weapon_rifle")[0]
		as Dictionary
	)
	assert_float(cabinet["position"].y).is_equal_approx(3.4, 0.01)
	# A player on the floor below the cabinet is offered nothing for it.
	SmallMapNight.stand_at(_night, Vector3(cabinet["position"].x, 0.0, cabinet["position"].z))
	assert_str(String(_night.state.me()["prompt"].get("id", ""))).is_not_equal("weapon_rifle")
	# Upstairs it is offered at its price and bought.
	SmallMapNight.stand_at(_night, cabinet["position"])
	assert_str(String(_night.state.me()["prompt"].get("id", ""))).is_equal("weapon_rifle")
	SmallMapNight.press_use(_night)
	assert_array(_night.server.rules.players[1].weapons).contains([&"weapon_rifle"])


func test_a_locker_sells_the_rounds_of_the_weapon_in_hand() -> void:
	await _start()
	var lockers := _spots(&"ammo")
	assert_int(lockers.size()).is_equal(4)
	var rules := _night.server.rules
	var state := _night.server.combat.state_of(1, &"pistol")
	state.reserve = 0
	SmallMapNight.stand_at(_night, lockers[0]["position"])
	var prompt: Dictionary = _night.state.me()["prompt"]
	assert_str(String(prompt.get("kind", ""))).is_equal("ammo")
	var before := rules.points_of(1)
	SmallMapNight.press_use(_night)
	assert_int(rules.points_of(1)).is_less(before)
	assert_int(state.reserve).is_greater(0)


func test_the_box_is_played_for_its_price_and_gives_a_weapon_not_already_carried() -> void:
	await _start()
	var rules := _night.server.rules
	var box := _spots(&"crane")[0] as Dictionary
	SmallMapNight.stand_at(_night, box["position"])
	var prompt: Dictionary = _night.state.me()["prompt"]
	assert_str(String(prompt.get("kind", ""))).is_equal("crane")
	assert_int(int(prompt["price"])).is_equal(_price(&"crane_play"))
	var before := rules.points_of(1)
	SmallMapNight.press_use(_night)
	assert_int(before - rules.points_of(1)).is_equal(_price(&"crane_play"))
	# The prize turns up after the spin; the buyer takes it.
	for _i in 600:
		SmallMapNight.run(_night, 1)
		if rules.crane.stage == CraneState.Stage.GRAB:
			break
	assert_int(rules.crane.stage).is_equal(CraneState.Stage.GRAB)
	assert_bool(rules.players[1].weapons.has(rules.crane.weapon)).is_false()
	var prize := rules.crane.weapon
	SmallMapNight.press_use(_night)
	assert_array(rules.players[1].weapons).contains([prize])


func test_the_box_never_moves_however_often_it_is_played() -> void:
	await _start()
	var rules := _night.server.rules
	# Played a hundred times by seeded draws of the rules alone: the lot's crane would have left.
	for play in 100:
		rules.players[1].weapons.assign([&"weapon_pistol"])
		var result := RulesFixture.buy(rules, 1, &"crane_play")
		if result != GameRules.BuyResult.OK:
			# Still busy with the last play: let it run out.
			RulesFixture.run(rules, 40.0)
			result = RulesFixture.buy(rules, 1, &"crane_play")
		assert_int(result).is_equal(GameRules.BuyResult.OK)
		RulesFixture.run(rules, 40.0)
		assert_int(rules.crane.spot).is_equal(0)
	assert_int(rules.crane.plays).is_greater(50)
