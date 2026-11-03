# The first-run touch hints and the key hints on a phone, driven by real touch events: a hint shows
# until its control is used, then goes for good; the prompt card shows a tap mark, never a keycap;
# and the labels keep clear of the buttons and the HUD cards at every phone canvas.
extends GdUnitTestSuite

## Canvases (canvas units) of a 16:9 phone, a 19.5:9 phone, a 20:9 phone and a browser with bars.
const CANVASES: Array[Vector2] = [
	Vector2(1920.0, 1080.0),
	Vector2(2340.0, 1080.0),
	Vector2(2400.0, 1080.0),
	Vector2(2340.0, 1080.0 * 0.8),
]
const KEPT_PARTS: Array[StringName] = [
	&"ammo", &"prompt", &"health", &"perks", &"points", &"round_part"
]
const ON_THE_STICK := Vector2(300.0, 760.0)
const ON_THE_LOOK_AREA := Vector2(1700.0, 330.0)

var _fixture: TouchFixture


func before_test() -> void:
	UIMotion.reduced = false
	UIInputMode.reset()


func after_test() -> void:
	if _fixture != null:
		_fixture.free_all()
		_fixture = null


func _start(state: HudState = null, persist := false) -> void:
	_fixture = TouchFixture.make(self, TouchFixture.PHONE, state, persist)
	await await_idle_frame()


func _hints() -> TouchHints:
	return _fixture.controls.hints


func _frames(count := 2) -> void:
	for _i in count:
		await await_idle_frame()


# --- When they show, and when they go ---


func test_a_new_player_sees_move_and_look_and_interact_waits_for_a_prompt() -> void:
	var state := HudState.new()
	await _start(state)
	assert_array(_hints().showing()).is_equal([TouchHints.MOVE, TouchHints.LOOK])
	state.set_prompt(&"buy_door", "Concession door", 350)
	await _frames()
	assert_array(_hints().showing()).is_equal(TouchHints.ORDER)
	assert_str(_hints().text_for(TouchHints.INTERACT)).is_equal("TAP TO USE")
	state.clear_prompt()
	await _frames()
	assert_array(_hints().showing()).is_equal([TouchHints.MOVE, TouchHints.LOOK])


func test_the_move_hint_goes_when_the_stick_is_used_and_the_others_stay() -> void:
	await _start()
	await _fixture.touch(0, ON_THE_STICK)
	assert_bool(_hints().is_seen(TouchHints.MOVE)).is_true()
	assert_array(_hints().showing()).is_equal([TouchHints.LOOK])
	await _fixture.lift(0)
	assert_array(_hints().showing()).is_equal([TouchHints.LOOK])


func test_the_look_hint_goes_on_the_first_look_drag_not_on_a_touch_alone() -> void:
	await _start()
	await _fixture.touch(0, ON_THE_LOOK_AREA)
	assert_bool(_hints().is_seen(TouchHints.LOOK)).is_false()
	await _fixture.drag(0, ON_THE_LOOK_AREA + Vector2(40.0, 0.0), Vector2(40.0, 0.0))
	assert_bool(_hints().is_seen(TouchHints.LOOK)).is_true()
	assert_array(_hints().showing()).is_equal([TouchHints.MOVE])
	await _fixture.lift(0)


func test_a_look_started_on_fire_also_ends_the_look_hint() -> void:
	await _start()
	var fire := _fixture.at(TouchLayout.FIRE)
	await _fixture.touch(0, fire)
	await _fixture.drag(0, fire + Vector2(30.0, 0.0), Vector2(30.0, 0.0))
	assert_bool(_hints().is_seen(TouchHints.LOOK)).is_true()
	await _fixture.lift(0)


func test_the_interact_hint_goes_when_the_button_is_pressed_and_a_hold_says_hold() -> void:
	var state := HudState.new()
	await _start(state)
	state.set_prompt(&"repair", "Broken fence", 0)
	await _frames()
	assert_str(_hints().text_for(TouchHints.INTERACT)).is_equal("HOLD TO REPAIR")
	await _fixture.touch(0, _fixture.at(TouchLayout.INTERACT))
	assert_bool(_hints().is_seen(TouchHints.INTERACT)).is_true()
	assert_array(_hints().showing()).is_equal([TouchHints.MOVE, TouchHints.LOOK])
	await _fixture.lift(0)


func test_an_unused_interact_hint_comes_back_with_the_next_prompt() -> void:
	var state := HudState.new()
	await _start(state)
	state.set_prompt(&"buy_door", "Concession door", 350)
	await _frames()
	state.clear_prompt()
	await _frames()
	assert_bool(_hints().is_seen(TouchHints.INTERACT)).is_false()
	state.set_prompt(&"buy_weapon", "Shotgun", 500)
	await _frames()
	assert_array(_hints().showing()).contains([TouchHints.INTERACT])


func test_a_used_hint_leaves_nothing_drawn_once_it_has_faded() -> void:
	await _start()
	await await_millis(100)
	assert_bool(_hints().is_painted()).is_true()
	for id in TouchHints.ORDER:
		_hints().mark_used(id)
	await await_millis(600)
	assert_array(_hints().showing()).is_empty()
	assert_bool(_hints().is_painted()).is_false()


func test_no_hint_shows_while_a_menu_has_the_controls_down() -> void:
	await _start()
	_fixture.controls.live = false
	assert_array(_hints().showing()).is_empty()
	_fixture.controls.live = true
	assert_array(_hints().showing()).is_not_empty()


func test_a_used_hint_stays_gone_in_the_next_session() -> void:
	var settings: SettingsService = get_tree().root.get_node("Settings")
	var before: Variant = settings.get_value(SettingsService.TOUCH_HINTS_SEEN)
	settings.set_value(SettingsService.TOUCH_HINTS_SEEN, 0)
	await _start(null, true)
	assert_array(_hints().showing()).contains([TouchHints.MOVE, TouchHints.LOOK])
	await _fixture.touch(0, ON_THE_STICK)
	await _fixture.lift(0)
	assert_int(int(settings.get_value(SettingsService.TOUCH_HINTS_SEEN))).is_equal(1)
	_fixture.free_all()
	await _start(null, true)
	assert_array(_hints().showing()).is_equal([TouchHints.LOOK])
	_hints().reset()
	assert_array(_hints().showing()).is_equal([TouchHints.MOVE, TouchHints.LOOK])
	assert_int(int(settings.get_value(SettingsService.TOUCH_HINTS_SEEN))).is_equal(0)
	settings.set_value(SettingsService.TOUCH_HINTS_SEEN, before)


func test_using_a_control_does_not_lay_the_buttons_out_again() -> void:
	await _start(null, true)
	var settings: SettingsService = get_tree().root.get_node("Settings")
	var before: Variant = settings.get_value(SettingsService.TOUCH_HINTS_SEEN)
	settings.set_value(SettingsService.TOUCH_HINTS_SEEN, 0)
	var layouts := [0]
	_fixture.controls.safe_insets_changed.connect(func(_i: Vector4) -> void: layouts[0] += 1)
	_fixture.controls.insets_override = Vector4(10.0, 0.0, 0.0, 0.0)
	_fixture.controls.refresh()
	assert_int(layouts[0]).is_equal(1)
	await _fixture.touch(0, ON_THE_STICK)
	await _fixture.lift(0)
	assert_int(layouts[0]).is_equal(1)
	settings.set_value(SettingsService.TOUCH_HINTS_SEEN, before)


# --- The prompt card on a phone ---


func test_the_prompt_card_shows_a_tap_mark_not_a_keycap_once_a_finger_plays() -> void:
	var host: Control = auto_free(Control.new())
	host.size = TouchFixture.PHONE
	add_child(host)
	var hud := HudFixture.make(host).hud
	hud.state.set_prompt(&"buy_door", "Concession door", 350)
	await _frames()
	assert_str(hud.prompt.glyph_caption).is_equal("E")
	assert_bool(hud.prompt.glyph_is_tap_mark).is_false()
	# The controls come up and a finger lands on the stick; the HUD never sees that touch itself.
	await _start(hud.state)
	await _fixture.touch(0, ON_THE_STICK)
	await _frames()
	assert_str(hud.prompt.glyph_caption).is_equal("")
	assert_bool(hud.prompt.glyph_is_tap_mark).is_true()
	# The look goes out as mouse motion: that is the finger, not a mouse being picked up.
	await _fixture.lift(0)
	await _fixture.touch(0, ON_THE_LOOK_AREA)
	await _fixture.drag(0, ON_THE_LOOK_AREA + Vector2(40.0, 0.0), Vector2(40.0, 0.0))
	await _frames()
	assert_bool(UIInputMode.touch).is_true()
	assert_bool(hud.prompt.glyph_is_tap_mark).is_true()
	await _fixture.lift(0)


func test_a_key_or_a_pad_brings_the_keycap_back_and_a_finger_takes_it_again() -> void:
	await _start()
	assert_bool(UIInputMode.touch).is_true()
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	UIInputMode.track(key)
	assert_bool(UIInputMode.touch).is_false()
	await _fixture.touch(0, ON_THE_STICK)
	assert_bool(UIInputMode.touch).is_true()
	await _fixture.lift(0)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	UIInputMode.track(pad)
	assert_bool(UIInputMode.touch).is_false()
	assert_bool(UIInputMode.gamepad).is_true()


# --- Where the labels sit ---


func test_the_labels_keep_clear_of_the_buttons_and_the_hud_for_either_hand() -> void:
	var insets := Vector4(96.0, 0.0, 96.0, 24.0)
	for mirrored in [false, true]:
		for canvas in CANVASES:
			var host: Control = auto_free(Control.new())
			host.size = canvas
			host.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(host)
			var hud_fixture := HudFixture.make(host, 4)
			hud_fixture.hud.mirrored = mirrored
			hud_fixture.into_round_one()
			var state := hud_fixture.hud.state
			state.set_ammo(30, 150, "Shotgun")
			state.set_area("The Concession Stand", "Light the booth to open the back lot")
			state.set_prompt(&"buy_door", "Projection booth door", 750)
			hud_fixture.give_perks(4)
			var fixture := TouchFixture.make(self, canvas, state)
			if mirrored:
				fixture.left_handed()
			fixture.controls.insets_override = insets
			fixture.controls.refresh()
			# The HUD keeps inside the notch as it does in the night screen.
			hud_fixture.hud.offset_left = insets.x
			hud_fixture.hud.offset_top = insets.y
			hud_fixture.hud.offset_right = -insets.z
			hud_fixture.hud.offset_bottom = -insets.w
			await _frames()
			var hints := fixture.controls.hints
			var safe := fixture.controls.safe_rect()
			assert_array(hints.showing()).is_equal(TouchHints.ORDER)
			var circles := TouchLayout.buttons(safe, 1.0, mirrored)
			var rects := {}
			for id in hints.showing():
				var rect := hints.rect_of(id)
				rects[id] = rect
				var message := "%s on %s (mirrored %s)" % [id, canvas, mirrored]
				(
					assert_bool(safe.encloses(rect))
					. override_failure_message("%s leaves the safe area %s" % [message, safe])
					. is_true()
				)
				for button: StringName in circles:
					var centre: Vector2 = circles[button][&"centre"]
					(
						assert_float(centre.clamp(rect.position, rect.end).distance_to(centre))
						. override_failure_message("%s covers %s" % [message, button])
						. is_greater(float(circles[button][&"radius"]))
					)
				for part_name in KEPT_PARTS:
					var card: Rect2 = (hud_fixture.hud.get(part_name) as Control).get_global_rect()
					(
						assert_bool(rect.intersects(card))
						. override_failure_message(
							"%s covers the %s card %s" % [message, part_name, card]
						)
						. is_false()
					)
			var ids := rects.keys()
			for i in ids.size():
				for j in range(i + 1, ids.size()):
					assert_bool((rects[ids[i]] as Rect2).intersects(rects[ids[j]])).is_false()
			fixture.free_all()


func test_only_a_real_mouse_click_ends_touch_mode_not_motion_or_the_engine_copy_of_a_tap() -> void:
	await _start()
	UIInputMode.track(InputEventMouseMotion.new())
	assert_bool(UIInputMode.touch).is_true()
	var copy := InputEventMouseButton.new()
	copy.device = InputEvent.DEVICE_ID_EMULATION
	UIInputMode.track(copy)
	assert_bool(UIInputMode.touch).is_true()
	UIInputMode.track(InputEventMouseButton.new())
	assert_bool(UIInputMode.touch).is_false()
	assert_bool(UIInputMode.pointer).is_true()
