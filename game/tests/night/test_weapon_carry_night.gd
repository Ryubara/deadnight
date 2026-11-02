# The carry limit in the real night (#410, docs/design/weapons.md "Carrying weapons"): a player
# holds two weapons; buying a third at the wall or taking one from the crane with the real use
# button replaces the weapon in hand, the card says so before the points are paid, the swap button
# cycles the two, the HUD and the hands follow, and the replaced weapon is a prize again.
extends GdUnitTestSuite

const EQUIP_FRAMES := 120


func _start(hud: Hud = null) -> Night:
	var night := await NightFixture.start(
		self, Night.Mode.MANUAL, RulesFixture.steady_crane_tuning(), 7, hud
	)
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 50000))
	NightFixture.run(night, 2)
	return night


func _hud() -> Hud:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	return hud


func _stand_at(night: Night, shop_id: StringName) -> Dictionary:
	for spot in night.world.shop_spots():
		if spot["shop_id"] == shop_id:
			night.player().teleport(spot["position"] + Vector3(0.0, 0.1, 0.0))
			break
	NightFixture.run(night, 3)
	return night.state.me()["prompt"]


func _press(night: Night, button: StringName) -> void:
	var command := NightCommand.new()
	command.set(button, true)
	NightFixture.run(night, 1, command)
	NightFixture.run(night, 3)


func _carried(night: Night) -> Array:
	return night.server.combat.carried(1)


func _held(night: Night) -> String:
	return String(night.state.me()["weapon"])


func _animation(night: Night) -> PlayerAnimation:
	return night.player().get_node("AnimationTree") as PlayerAnimation


func _wait_for_the_weapon(night: Night, model: String) -> void:
	var animation := _animation(night)
	for _i in EQUIP_FRAMES:
		var weapon := animation.weapon()
		if weapon != null and weapon.visible and weapon.scene_file_path == model:
			return
		await get_tree().process_frame


func test_a_player_starts_with_two_weapons_and_no_more_fit() -> void:
	var night := await _start()
	assert_array(_carried(night)).contains_exactly_in_any_order([&"crowbar", &"pistol"])
	assert_str(_held(night)).is_equal("pistol")
	night.queue_free()


func test_buying_a_third_weapon_at_the_wall_replaces_the_one_in_hand() -> void:
	var night := await _start()
	_stand_at(night, &"weapon_shotgun")
	var before := night.state.points()
	_press(night, &"use")
	assert_int(night.state.points()).is_equal(before - 900)
	assert_str(_held(night)).is_equal("shotgun")
	assert_array(_carried(night)).contains_exactly_in_any_order([&"crowbar", &"shotgun"])
	# The rules agree with the hands, and the pistol is back in the pool.
	assert_array(night.server.rules.players[1].weapons).contains_exactly(
		[&"weapon_crowbar", &"weapon_shotgun"]
	)
	night.queue_free()


func test_the_swap_button_cycles_the_two_weapons_after_a_replace() -> void:
	var night := await _start()
	_stand_at(night, &"weapon_shotgun")
	_press(night, &"use")
	var seen: Array[String] = []
	for _i in 3:
		_press(night, &"swap")
		seen.append(_held(night))
	assert_array(seen).is_equal(["crowbar", "shotgun", "crowbar"])
	night.queue_free()


func test_the_weapon_in_the_other_hand_is_the_one_that_is_replaced() -> void:
	var night := await _start()
	_press(night, &"swap")
	assert_str(_held(night)).is_equal("crowbar")
	_stand_at(night, &"weapon_rifle")
	_press(night, &"use")
	assert_array(_carried(night)).contains_exactly_in_any_order([&"pistol", &"rifle"])
	assert_str(_held(night)).is_equal("rifle")
	night.queue_free()


func test_the_wall_card_says_what_it_will_replace_before_the_points_are_paid() -> void:
	var hud := _hud()
	var night := await _start(hud)
	var prompt := _stand_at(night, &"weapon_shotgun")
	assert_str(String(prompt["replaces"])).is_equal("pistol")
	assert_str(hud.prompt.title_text).is_equal("PUMP SHOTGUN")
	assert_str(hud.prompt.detail_text).contains("REPLACES")
	assert_str(hud.prompt.detail_text).contains(
		String(hud.state.weapon_names[&"pistol"]).to_upper()
	)
	# Nothing was paid for the look.
	assert_int(night.state.points()).is_equal(50200)
	night.queue_free()
	hud.queue_free()


func test_the_hud_follows_the_replace_the_kept_weapon_is_the_one_put_away() -> void:
	var hud := _hud()
	var night := await _start(hud)
	_stand_at(night, &"weapon_shotgun")
	_press(night, &"use")
	assert_str(String(hud.state.weapon_id)).is_equal("shotgun")
	assert_str(String(hud.state.holstered_id)).is_equal("crowbar")
	assert_str(hud.state.equipment_name).is_not_equal(String(hud.state.weapon_names[&"pistol"]))
	night.queue_free()
	hud.queue_free()


func test_the_hands_follow_the_replace_the_new_model_is_in_the_hand() -> void:
	var night := await _start()
	_stand_at(night, &"weapon_shotgun")
	_press(night, &"use")
	var hold := WeaponHoldMap.hold_for(&"shotgun")
	await _wait_for_the_weapon(night, hold.scene)
	var weapon := _animation(night).weapon()
	assert_object(weapon).is_not_null()
	assert_str(weapon.scene_file_path).is_equal(hold.scene)
	night.queue_free()


func test_a_crane_prize_replaces_the_weapon_in_hand_and_the_card_says_so() -> void:
	var hud := _hud()
	var night := await _start(hud)
	_stand_at(night, &"crane_play")
	_press(night, &"use")
	NightFixture.run(night, 300)
	var prompt: Dictionary = night.state.me()["prompt"]
	assert_str(String(prompt["kind"])).is_equal("crane_take")
	assert_str(String(prompt["replaces"])).is_equal("pistol")
	assert_str(hud.prompt.detail_text).contains("REPLACES")
	var prize := WeaponCatalog.catalog_id(prompt["weapon"])
	_press(night, &"use")
	assert_str(_held(night)).is_equal(String(prize))
	assert_array(_carried(night)).has_size(2)
	assert_array(_carried(night)).not_contains([&"pistol"])
	assert_array(_carried(night)).contains([&"crowbar"])
	night.queue_free()
	hud.queue_free()


func test_a_weapon_given_up_comes_back_from_the_crane_and_the_wall() -> void:
	var night := await _start()
	_stand_at(night, &"weapon_shotgun")
	_press(night, &"use")
	# The pistol was replaced: of everything the crane holds, it is on offer again.
	var item := night.server.rules.tuning.economy.item(&"crane_play")
	var owned: Array[StringName] = night.server.rules.players[1].weapons
	assert_array(item.pool_without(owned)).contains([&"weapon_pistol"])
	# And the shotgun, bought again after it was replaced, is sold again.
	_stand_at(night, &"weapon_rifle")
	_press(night, &"use")
	assert_array(_carried(night)).contains_exactly_in_any_order([&"crowbar", &"rifle"])
	var prompt := _stand_at(night, &"weapon_shotgun")
	assert_str(String(prompt["kind"])).is_equal("weapon")
	_press(night, &"use")
	assert_str(_held(night)).is_equal("shotgun")
	night.queue_free()


func test_a_weapon_already_carried_is_offered_its_rounds_not_a_replace() -> void:
	var night := await _start()
	_stand_at(night, &"weapon_shotgun")
	_press(night, &"use")
	night.server.combat.state_of(1, &"shotgun").reserve = 5
	var prompt := _stand_at(night, &"weapon_shotgun")
	assert_str(String(prompt["kind"])).is_equal("ammo")
	night.queue_free()
