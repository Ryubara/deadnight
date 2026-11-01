# The prompt, the interact key and the world markers: input simulated, devices switched, a refused
# purchase, an off-screen objective.
extends GdUnitTestSuite

var _host: Control
var _fixture: HudFixture
var _hud: Hud


func before_test() -> void:
	UIMotion.reduced = false
	UIInputMode.reset()
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func after_test() -> void:
	UIMotion.reduced = false
	UIInputMode.reset()
	Input.action_release(&"interact")


func _start(players := 1) -> void:
	_fixture = HudFixture.make(_host, players)
	_hud = _fixture.hud


# --- Prompt and input ---


func test_the_prompt_names_the_thing_and_its_price() -> void:
	_start()
	var prompt := _hud.prompt
	assert_bool(prompt.visible).is_false()
	_hud.state.set_prompt(&"buy_door", "Concession door", 350)
	assert_bool(prompt.visible).is_true()
	assert_str(prompt.title_text).is_equal("CONCESSION DOOR")
	assert_str(prompt.detail_text).is_equal("OPENS THE NEXT PART OF THE LOT")
	assert_str(prompt.price_text).is_equal("NEED 350 POINTS")
	_fixture.act(RulesAction.grant_points(1, 200))
	assert_str(prompt.price_text).is_equal("350 POINTS")
	_hud.state.set_prompt(&"repair", "Boards", 0)
	assert_str(prompt.detail_text).is_equal("HOLD TO NAIL BOARDS UP")
	_hud.state.clear_prompt()
	assert_bool(prompt.visible).is_false()


func test_a_prompt_for_each_kind_has_words() -> void:
	_start()
	for kind in HudPrompt.DETAILS:
		_hud.state.set_prompt(kind, "Thing", 10)
		assert_str(_hud.prompt.detail_text).is_not_empty()


func test_holding_the_interact_key_presses_the_keycap() -> void:
	_start()
	_hud.state.set_prompt(&"buy_door", "Concession door", 350)
	await await_idle_frame()
	assert_bool(_hud.prompt.glyph_pressed).is_false()
	assert_str(_hud.prompt.glyph_caption).is_equal("E")
	Input.action_press(&"interact")
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_hud.prompt.glyph_pressed).is_true()
	Input.action_release(&"interact")
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_hud.prompt.glyph_pressed).is_false()


func test_the_glyph_follows_the_last_device_used() -> void:
	_start()
	_hud.state.set_prompt(&"buy_door", "Concession door", 350)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	UIInputMode.track(pad)
	await await_idle_frame()
	await await_idle_frame()
	assert_str(_hud.prompt.glyph_caption).is_equal("Y")
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	UIInputMode.track(key)
	await await_idle_frame()
	await await_idle_frame()
	assert_str(_hud.prompt.glyph_caption).is_equal("E")
	UIInputMode.track(InputEventMouseMotion.new())
	assert_bool(UIInputMode.gamepad).is_false()


func test_a_rebound_key_shows_on_the_keycap() -> void:
	_start()
	var before := InputMap.action_get_events(&"interact").duplicate()
	InputMap.action_erase_events(&"interact")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	InputMap.action_add_event(&"interact", key)
	assert_str(HudGlyph.caption_for(&"interact", false)).is_equal("F")
	InputMap.action_erase_events(&"interact")
	for event in before:
		InputMap.action_add_event(&"interact", event)
	assert_str(HudGlyph.caption_for(&"interact", false)).is_equal("E")


func test_a_refused_purchase_says_why_and_shakes_the_card() -> void:
	_start()
	_fixture.into_round_one()
	_hud.state.set_prompt(&"buy_door", "Projection booth door", 750)
	_fixture.act(RulesAction.grant_points(1, 800))
	_fixture.act(RulesAction.buy(1, &"door_booth"))
	assert_str(_hud.prompt.price_text).is_equal("NOT YET: OPEN THE ONE BEFORE")
	assert_float(_hud.prompt.denied_left).is_greater(0.0)
	_hud.prompt.denied_left = 0.0
	_hud.prompt.refresh()
	assert_str(_hud.prompt.price_text).is_equal("750 POINTS")


func test_buying_clears_the_prompt() -> void:
	_start()
	_fixture.into_round_one()
	_fixture.act(RulesAction.grant_points(1, 200))
	_hud.state.set_prompt(&"buy_door", "Concession door", 350)
	_fixture.act(RulesAction.buy(1, &"door_concession"))
	assert_bool(_hud.prompt.visible).is_false()


# --- Markers ---


func _marker(id: StringName, kind: StringName, x: float, y: float, key := false) -> Dictionary:
	return {"id": id, "kind": kind, "x": x, "y": y, "distance": 30.0, "label": "", "important": key}


func test_an_off_screen_important_marker_pins_to_the_edge_inside_the_screen() -> void:
	_start()
	await await_idle_frame()
	var list: Array[Dictionary] = [
		_marker(&"door", &"objective", 1.6, 0.4, true),
		_marker(&"far", &"objective", -0.3, 0.9),
		_marker(&"moe", &"ally", 0.4, 0.5),
		_marker(&"behind", &"objective", 0.5, 2.0, true),
	]
	_hud.state.set_markers(list)
	var rect := Rect2(Vector2.ZERO, _hud.markers.size)
	var door := _hud.markers.marker_at(&"door")
	assert_bool(door["pinned"]).is_true()
	assert_bool(rect.grow(-HudMarkers.EDGE_INSET + 1.0).has_point(door["at"])).is_true()
	assert_float(door["at"].x).is_greater(rect.size.x * 0.8)
	assert_dict(_hud.markers.marker_at(&"far")).is_empty()
	assert_bool(_hud.markers.marker_at(&"moe")["pinned"]).is_false()
	var behind := _hud.markers.marker_at(&"behind")
	assert_float(behind["at"].y).is_greater(rect.size.y * 0.8)


func test_shaking_with_reduced_motion_is_a_valid_empty_tween() -> void:
	UIMotion.reduced = true
	var control: Control = auto_free(Control.new())
	_host.add_child(control)
	var tween := UIMotion.shake(control)
	assert_bool(tween.is_valid()).is_true()
	assert_vector(control.position).is_equal(Vector2.ZERO)
