# The weapon slot strip (#682): the weapons carried by number with the one in hand lit, kept true by
# the weapons' events and by the server's frame, with a place left for a third slot. The look at
# 720p, 1080p, 1440p, in the browser and on a phone is `tests/captures/weapon_slots_tour.gd`.
extends GdUnitTestSuite

var _host: Control
var _fixture: HudFixture


func before_test() -> void:
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)
	_fixture = HudFixture.make(_host)
	_fixture.into_round_one()


func _state() -> HudState:
	return _fixture.hud.state


func _cells() -> Array[HudSlotCell]:
	return _fixture.hud.slots.cells()


func _frame(held: StringName, carried: Array) -> Dictionary:
	var arms := {}
	for id: StringName in carried:
		arms[id] = [6, 24, 0]
	return {"weapon": held, "ammo": 6, "reserve": 24, "reloading": false, "arms": arms}


func _equipped(id: StringName) -> Dictionary:
	return {"type": &"weapon_equipped", "player_id": 1, "weapon_id": id, "ammo": 6, "reserve": 24}


func test_the_strip_has_a_numbered_place_for_every_slot_with_the_weapon_in_hand_lit() -> void:
	HudLoadout.sync(_frame(&"pistol", [&"crowbar", &"pistol"]), _state())
	var cells := _cells()
	assert_int(cells.size()).is_equal(WeaponSlots.count())
	assert_int(cells[0].number).is_equal(1)
	assert_int(cells[1].number).is_equal(2)
	assert_str(String(cells[0].weapon_id)).is_equal("crowbar")
	assert_str(String(cells[1].weapon_id)).is_equal("pistol")
	assert_bool(cells[0].held).is_false()
	assert_bool(cells[1].held).is_true()


func test_the_lit_place_follows_the_weapon_in_hand() -> void:
	HudLoadout.sync(_frame(&"pistol", [&"crowbar", &"pistol"]), _state())
	HudLoadout.sync(_frame(&"crowbar", [&"crowbar", &"pistol"]), _state())
	assert_bool(_cells()[0].held).is_true()
	assert_bool(_cells()[1].held).is_false()
	assert_int(_state().slot_held).is_equal(1)


func test_one_place_is_lit_and_it_reads_differently_from_the_rest() -> void:
	HudLoadout.sync(_frame(&"pistol", [&"crowbar", &"pistol"]), _state())
	var lit := _cells().filter(func(c: HudSlotCell) -> bool: return c.held)
	assert_int(lit.size()).is_equal(1)
	var tokens := UITokens.active()
	assert_that(lit[0].ink_colour()).is_equal(tokens.ink_on_accent)
	assert_that(_cells()[0].ink_colour()).is_equal(tokens.ink)


func test_an_empty_place_is_the_number_alone_and_dim() -> void:
	HudLoadout.sync(_frame(&"pistol", [&"pistol"]), _state())
	assert_str(String(_cells()[1].weapon_id)).is_equal("")
	assert_bool(_cells()[1].held).is_false()
	assert_bool(_cells()[1].shows_picture()).is_false()
	assert_that(_cells()[1].ink_colour()).is_equal(UITokens.active().ink_disabled)
	assert_int(_cells()[1].number).is_equal(2)


func test_the_events_alone_fill_the_strip_in_the_order_they_were_taken() -> void:
	_state().apply_event(_equipped(&"crowbar"))
	_state().apply_event(_equipped(&"pistol"))
	assert_array(_state().slot_ids).is_equal([&"crowbar", &"pistol"])
	assert_int(_state().slot_held).is_equal(2)
	_state().apply_event(_equipped(&"crowbar"))
	assert_array(_state().slot_ids).is_equal([&"crowbar", &"pistol"])
	assert_int(_state().slot_held).is_equal(1)


func test_a_replacing_weapon_sits_in_the_slot_of_the_one_it_replaces() -> void:
	_state().apply_event(_equipped(&"crowbar"))
	_state().apply_event(_equipped(&"pistol"))
	_state().apply_event(
		{"type": &"weapon_replaced", "player_id": 1, "dropped": &"pistol", "weapon_id": &"rifle"}
	)
	# Between the two events the pistol's place is empty, not taken over by the crowbar.
	assert_array(_state().slot_ids).is_equal([&"crowbar", &""])
	assert_array(_cells().map(func(c: HudSlotCell) -> bool: return c.held)).is_equal([false, false])
	_state().apply_event(_equipped(&"rifle"))
	assert_array(_state().slot_ids).is_equal([&"crowbar", &"rifle"])
	assert_int(_state().slot_held).is_equal(2)


func test_the_frame_orders_the_slots_as_the_server_carries_them() -> void:
	HudLoadout.sync(_frame(&"rifle", [&"rifle", &"crowbar"]), _state())
	assert_array(_state().slot_ids).is_equal([&"rifle", &"crowbar"])
	assert_int(_state().slot_held).is_equal(1)


func test_a_third_slot_gets_a_place_and_the_three_share_the_strip() -> void:
	HudLoadout.sync(_frame(&"pistol", [&"crowbar", &"pistol"]), _state())
	_state().set_slot_count(3)
	var cells := _cells()
	assert_int(cells.size()).is_equal(3)
	assert_int(cells[2].number).is_equal(3)
	assert_str(String(cells[2].weapon_id)).is_equal("")
	await get_tree().process_frame
	await get_tree().process_frame
	var strip := _fixture.hud.slots.get_global_rect()
	for cell in cells:
		assert_bool(strip.encloses(cell.get_global_rect())).is_true()
	assert_float(cells[0].size.x).is_equal_approx(HudSlots.cell_width(3), 1.0)
	# A third weapon carried fills it.
	HudLoadout.sync(_frame(&"rifle", [&"crowbar", &"pistol", &"rifle"]), _state())
	assert_str(String(_cells()[2].weapon_id)).is_equal("rifle")
	assert_bool(_cells()[2].held).is_true()


func test_the_strip_sits_above_the_ammo_card_inside_the_column() -> void:
	HudLoadout.sync(_frame(&"pistol", [&"crowbar", &"pistol"]), _state())
	await get_tree().process_frame
	await get_tree().process_frame
	var strip := _fixture.hud.slots.get_global_rect()
	var ammo := _fixture.hud.ammo.get_global_rect()
	assert_float(strip.end.y).is_less_equal(ammo.position.y)
	assert_float(strip.end.x).is_equal_approx(ammo.end.x, 1.0)
	assert_float(strip.size.x).is_equal_approx(HudAmmo.WIDTH, 1.0)
	# The numbers are the only text on it: no rounds (the ammo card is their one home).
	for cell in _cells():
		assert_bool(cell.number_rect().size.x > 0.0).is_true()


func test_every_catalogue_weapon_has_a_model_to_draw_its_silhouette_from() -> void:
	assert_array(WeaponHoldMap.no_model()).is_empty()
	var drawn := WeaponSilhouettes.new()
	auto_free(drawn)
	add_child(drawn)
	WeaponSilhouettes.live = true
	for id in WeaponCatalog.IDS:
		(
			assert_object(drawn.texture_of(id))
			. override_failure_message("%s has no silhouette" % id)
			. is_not_null()
		)
	WeaponSilhouettes.live = false


func test_a_longer_weapon_is_drawn_wider_and_none_fills_the_whole_picture() -> void:
	var rifle := WeaponHoldMap.hold_for(&"rifle")
	var pistol := WeaponHoldMap.hold_for(&"pistol")
	var rifle_share := WeaponSilhouettes.width_share(rifle)
	var pistol_share := WeaponSilhouettes.width_share(pistol)
	assert_float(pistol_share).is_less(rifle_share)
	assert_float(pistol_share).is_greater_equal(
		WeaponSilhouettes.SMALLEST_SHARE * WeaponSilhouettes.FILL.x - 0.001
	)
	for id in WeaponCatalog.IDS:
		var share := WeaponSilhouettes.width_share(WeaponHoldMap.hold_for(id))
		assert_float(share).is_less_equal(WeaponSilhouettes.FILL.x + 0.001)


func test_with_the_touch_controls_up_the_strip_sits_under_the_health_card_as_wide_as_it() -> void:
	for mirrored in [false, true]:
		var hud := _fixture.hud
		hud.mirrored = mirrored
		hud.touch_layout = true
		HudLoadout.sync(_frame(&"pistol", [&"crowbar", &"pistol"]), _state())
		await get_tree().process_frame
		await get_tree().process_frame
		var strip := hud.slots.get_global_rect()
		var health := hud.health.get_global_rect()
		assert_float(strip.position.y).is_greater_equal(health.end.y)
		assert_float(strip.position.x).is_equal_approx(health.position.x, 1.0)
		assert_float(strip.size.x).is_equal_approx(health.size.x, 1.0)
		# The right thumb's corner is the ammo card's alone.
		assert_bool(hud.slots.get_parent() == hud.ammo.get_parent()).is_false()
	_fixture.hud.touch_layout = false
	await get_tree().process_frame
	assert_bool(_fixture.hud.slots.get_parent() == _fixture.hud.ammo.get_parent()).is_true()
