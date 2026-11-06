extends GdUnitTestSuite
## The bots' order on a phone is a tag in the HUD's players' column (Deadnight #1286): it shows the
## standing order (a word and its colour) only while the room has bots, it is at least a fingertip
## (44 CSS px) in each direction on the two phone pages (844 x 390 and 667 x 375 CSS px, a pixel
## ratio of 2) at every interface size and for either hand, a tap on it presses `bot_order_next`
## and never starts the stick or a look, it keeps its taps where another place is laid over it, and
## the first-run hint says what it does. The wheel's button is gone from the glass. Real touch
## events through the layer, as a browser sends them; what the order does in the night is
## `test_bot_wheel_input.gd`.

## Windows in pixels and the pixel ratio the browser reports.
const PAGES: Array[Vector3] = [Vector3(1688, 780, 2.0), Vector3(1334, 750, 2.0)]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
const HANDS: Array[bool] = [false, true]
const FINGER_CSS := 44.0
const SLACK_CSS := 0.05
const BOT_ID := 101

var _window_size := Vector2i.ZERO
var _window_factor := 1.0
var _fixture: TouchFixture
var _looks := 0


func before_test() -> void:
	_window_size = get_window().size
	_window_factor = get_window().content_scale_factor
	_looks = 0
	UIMotion.reduced = false


func after_test() -> void:
	if _fixture != null:
		_fixture.free_all()
		_fixture = null
	get_window().size = _window_size
	get_window().content_scale_factor = _window_factor
	MenuScale.pixel_ratio = -1.0
	UIMotion.reduced = false
	await get_tree().process_frame


## The page a player has, the HUD of a room with `bots` bots (and one person) laid out on it, in the
## hand asked for.
func _page(page: Vector3, ui_scale: float, left := false, bots := 1) -> void:
	var window := Vector2i(int(page.x), int(page.y))
	get_window().size = window
	get_window().content_scale_factor = ui_scale
	MenuScale.pixel_ratio = page.z
	var canvas := Vector2(window) / MenuScale.pixels_per_unit(window, ui_scale)
	_fixture = TouchFixture.make(self, canvas, null, false, true)
	if left:
		_fixture.left_handed(true)
	_fixture.controls.looked.connect(func(_motion: Vector2) -> void: _looks += 1)
	var state := _fixture.hud.state
	state.set_player_name(1, "Ruby")
	state.apply_event({"type": &"player_added", "player_id": 1})
	for i in bots:
		state.apply_event({"type": &"player_added", "player_id": BOT_ID + i, "bot": true})
	await _settle()


func _settle() -> void:
	for _i in 4:
		await get_tree().process_frame


func _css_per_unit(page: Vector3, ui_scale: float) -> float:
	var window := Vector2i(int(page.x), int(page.y))
	return MenuScale.pixels_per_unit(window, ui_scale) / page.z


func _tag() -> Rect2:
	return _fixture.controls.zone_rect(HudBotOrder.ACTION)


func _every_page(check: Callable, bots := 1) -> void:
	for page in PAGES:
		for ui_scale in UI_SCALES:
			for left in HANDS:
				await _page(page, ui_scale, left, bots)
				check.call(page, ui_scale, left)
				_fixture.free_all()
				_fixture = null


func _label(page: Vector3, ui_scale: float, left: bool, what: String) -> String:
	return "%s on %dx%d at %.2f, left hand %s" % [what, page.x, page.y, ui_scale, left]


# --- What is there ---


func test_the_wheels_button_is_gone_from_the_glass() -> void:
	await _page(PAGES[0], 1.0)
	assert_bool(_fixture.controls.circles().has(&"bot_wheel")).is_false()
	assert_bool(TouchLayout.buttons(Rect2(0, 0, 2337, 1080), 1.0).has(&"bot_wheel")).is_false()


func test_the_tag_is_there_only_while_the_room_has_bots() -> void:
	await _page(PAGES[0], 1.0, false, 0)
	assert_bool(_tag().has_area()).is_false()
	assert_bool(_fixture.hud.slots.bot_tag.is_visible_in_tree()).is_false()
	assert_bool(_fixture.controls.button_boxes().has(_tag())).is_false()
	_fixture.hud.state.apply_event({"type": &"player_added", "player_id": BOT_ID, "bot": true})
	await _settle()
	assert_bool(_tag().has_area()).is_true()
	assert_bool(_fixture.controls.button_boxes().has(_tag())).is_true()
	_fixture.hud.state.apply_event({"type": &"player_removed", "player_id": BOT_ID})
	await _settle()
	assert_bool(_tag().has_area()).is_false()


func test_the_tag_says_the_standing_order_in_a_word_and_a_colour_of_its_own() -> void:
	await _page(PAGES[0], 1.0)
	var tag := _fixture.hud.slots.bot_tag
	var words := {}
	var colours := []
	for order in BotWheel.ORDERS:
		_fixture.hud.state.set_bot_order(order)
		await _settle()
		assert_str(tag.word()).is_equal(BotWheel.NAMES[order])
		words[tag.word()] = true
		colours.append(tag.colour_of(order))
	assert_int(words.size()).is_equal(3)
	(
		assert_bool(
			colours[0] != colours[1] and colours[1] != colours[2] and colours[0] != colours[2]
		)
		. is_true()
	)
	# A word is never the whole answer to a colour-blind eye: the three also differ in light.
	var lights := colours.map(func(c: Color) -> float: return snappedf(c.get_luminance(), 0.05))
	assert_int(lights.size()).is_equal(3)
	(
		assert_bool(lights[0] != lights[1] and lights[1] != lights[2] and lights[0] != lights[2])
		. is_true()
	)


## The word of the order is the thing to read at a glance (the capture of #1286 read dim beside the
## HUD's other words): larger than the caption above it, and each order's colour keeps AAA contrast
## against the ticket, lit by a finger or not.
func test_the_word_of_the_order_is_larger_than_its_caption_and_keeps_its_contrast() -> void:
	await _page(PAGES[1], 1.0)
	var tag := _fixture.hud.slots.bot_tag
	var tokens := UITokens.active()
	assert_int(tag.word_px()).is_greater(tag.caption_px())
	var lit := tokens.surface_raised.lerp(tokens.accent_bright, 0.16)
	for order in BotWheel.ORDERS:
		var ink := tag.colour_of(order)
		for case: Array in [
			[tokens.surface_raised, HudBotOrder.WORD_CONTRAST], [lit, HudBotOrder.WORD_CONTRAST_LIT]
		]:
			var ratio := HudPlayerBox.contrast(ink, case[0])
			(
				assert_float(ratio)
				. override_failure_message("%s on %s: %.2f" % [order, case[0], ratio])
				. is_greater_equal(case[1])
			)
	# The caption keeps the HUD's AA.
	assert_float(HudPlayerBox.contrast(tokens.ink_muted, tokens.surface_raised)).is_greater_equal(
		4.5
	)
	# Two lines of it fit the tag at every interface size.
	for ui_scale in UI_SCALES:
		await _page(PAGES[1], ui_scale)
		var box := _fixture.hud.slots.bot_tag
		assert_float(box.lines_height()).is_less(box.size.y)


func test_the_tag_is_a_fingertip_wide_and_high_on_the_screen_clear_of_the_rest() -> void:
	await _every_page(
		func(page: Vector3, ui_scale: float, left: bool) -> void:
			var css := _css_per_unit(page, ui_scale)
			var rect := _tag()
			var what := _label(page, ui_scale, left, "the tag")
			assert_bool(rect.has_area()).override_failure_message(what).is_true()
			(
				assert_float(minf(rect.size.x, rect.size.y) * css)
				. override_failure_message(
					"%s is %.1f x %.1f CSS px" % [what, rect.size.x * css, rect.size.y * css]
				)
				. is_greater_equal(FINGER_CSS - SLACK_CSS)
			)
			var controls := _fixture.controls
			(
				assert_bool(Rect2(Vector2.ZERO, _fixture.host.size).encloses(rect))
				. override_failure_message(what)
				. is_true()
			)
			for id: StringName in controls.circles():
				var circle: Dictionary = controls.circles()[id]
				var centre: Vector2 = circle[&"centre"]
				(
					assert_float(centre.distance_to(centre.clamp(rect.position, rect.end)))
					. override_failure_message("%s touches the %s button" % [what, id])
					. is_greater(float(circle[&"hit"]))
				)
			# The stick's ring at rest, and the places of the weapons.
			var rest := TouchLayout.stick_rest(controls.safe_rect(), 1.0, left)
			(
				assert_float(rest.distance_to(rest.clamp(rect.position, rect.end)))
				. override_failure_message("%s touches the stick's ring" % what)
				. is_greater(TouchLayout.STICK_RADIUS)
			)
			for zone in _fixture.hud.slots.touch_zones():
				if zone[&"action"] == HudBotOrder.ACTION:
					continue
				(
					assert_bool(rect.intersects(zone[&"rect"]))
					. override_failure_message("%s is over the %s place" % [what, zone[&"action"]])
					. is_false()
				)
			# The cards of the column, and the ones that keep a place of their own.
			for card: Control in [_fixture.hud.health, _fixture.hud.points, _fixture.hud.ammo]:
				(
					assert_bool(rect.intersects(card.get_global_rect()))
					. override_failure_message("%s is over the %s card" % [what, card.name])
					. is_false()
				)
	)


func test_the_tag_stands_on_the_hand_s_side_for_both_hands() -> void:
	await _page(PAGES[0], 1.0)
	assert_float(_tag().get_center().x).is_less(_fixture.host.size.x * 0.5)
	_fixture.left_handed(true)
	await _settle()
	assert_float(_tag().get_center().x).is_greater(_fixture.host.size.x * 0.5)
	_fixture.left_handed(false)
	await _settle()
	assert_float(_tag().get_center().x).is_less(_fixture.host.size.x * 0.5)


func test_a_keyboard_hud_has_no_tag_at_all() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var fixture := HudFixture.make(host, 1, 1958, false, 3)
	await _settle()
	assert_object(fixture.hud.slots.bot_tag).is_null()
	assert_array(fixture.hud.slots.touch_zones()).is_empty()


# --- A finger ---


func test_a_tap_presses_the_action_and_a_lift_lets_it_go() -> void:
	await _page(PAGES[0], 1.0)
	await _fixture.touch(0, _tag().get_center())
	assert_bool(Input.is_action_pressed(HudBotOrder.ACTION)).is_true()
	assert_array(Array(_fixture.controls.held_buttons())).contains([String(HudBotOrder.ACTION)])
	await _fixture.lift(0, _tag().get_center())
	await await_millis(250)
	assert_bool(Input.is_action_pressed(HudBotOrder.ACTION)).is_false()


func test_a_quick_tap_lasts_long_enough_for_a_frame_to_see() -> void:
	await _page(PAGES[0], 1.0)
	await _fixture.tap(_tag().get_center())
	assert_bool(Input.is_action_pressed(HudBotOrder.ACTION)).is_true()
	await await_millis(300)
	assert_bool(Input.is_action_pressed(HudBotOrder.ACTION)).is_false()


## The double tap that changes shoulder starts only from free ground (#1288): two quick taps on the
## tag are two taps of the tag (an order, or one under the server's half second), never a shoulder
## swap, and a tag tap between two free taps ends the pair. With the tag on the screen the double
## tap on free ground still works.
func test_two_taps_on_the_tag_are_never_a_shoulder_swap() -> void:
	await _page(PAGES[0], 1.0)
	var swaps := [0]
	_fixture.controls.shoulder_swapped.connect(func() -> void: swaps[0] += 1)
	_fixture.controls.clock = func() -> float: return _fixture.now
	var tag := _tag().get_center()
	var free := _fixture.controls.size * Vector2(0.62, 0.25)
	assert_str(String(_fixture.controls.zone_at(free))).is_empty()
	assert_str(String(TouchLayout.button_at(free, _fixture.controls.circles()))).is_empty()
	for _i in 2:
		await _fixture.touch(0, tag)
		_fixture.pass_time(0.08)
		await _fixture.lift(0, tag)
		_fixture.pass_time(0.1)
	assert_int(swaps[0]).is_equal(0)
	# A tag tap between two free taps ends the pair; the next free tap pairs with the one after it.
	for at in [free, tag, free]:
		await _fixture.touch(0, at)
		_fixture.pass_time(0.08)
		await _fixture.lift(0, at)
		_fixture.pass_time(0.1)
	assert_int(swaps[0]).is_equal(0)
	await _fixture.touch(0, free)
	_fixture.pass_time(0.08)
	await _fixture.lift(0, free)
	assert_int(swaps[0]).is_equal(1)


func test_a_finger_on_the_tag_never_starts_the_stick_or_a_look() -> void:
	await _page(PAGES[0], 1.0)
	var centre := _tag().get_center()
	await _fixture.touch(0, centre)
	var at := centre
	for _i in 8:
		at += Vector2(30.0, -12.0)
		await _fixture.drag(0, at, Vector2(30.0, -12.0), 600.0)
	await _fixture.settle_look()
	assert_bool(_fixture.controls.is_stick_down()).is_false()
	assert_int(_looks).is_equal(0)
	assert_bool(Input.is_action_pressed(&"fire")).is_false()
	assert_bool(Input.is_action_pressed(&"aim")).is_false()
	await _fixture.lift(0, at)
	await await_millis(250)


func test_a_finger_beside_the_tag_still_moves_or_looks_as_before() -> void:
	await _page(PAGES[0], 1.0)
	var rect := _tag()
	# Just above the tag, on the points' side of it: not the tag, so the stick's zone.
	var above := Vector2(rect.get_center().x, rect.position.y - 20.0)
	assert_str(String(_fixture.controls.zone_at(above))).is_not_equal(String(HudBotOrder.ACTION))
	await _fixture.touch(0, above)
	assert_bool(Input.is_action_pressed(HudBotOrder.ACTION)).is_false()
	await _fixture.lift(0, above)


func test_the_tag_keeps_its_taps_where_another_place_is_laid_over_it() -> void:
	await _page(PAGES[0], 1.0)
	var hud := _fixture.hud
	# A place over the whole column (what a hold on the players' column will be), listed after the
	# tag: the first zone that holds a point wins, so the tag is not lost to it.
	var column := Rect2(Vector2.ZERO, _fixture.host.size)
	_fixture.controls.zones = func() -> Array[Dictionary]:
		var found := hud.slots.touch_zones()
		found.append({&"action": &"scoreboard", &"rect": column})
		return found
	assert_str(String(_fixture.controls.zone_at(_tag().get_center()))).is_equal(
		String(HudBotOrder.ACTION)
	)
	await _fixture.touch(0, _tag().get_center())
	assert_bool(Input.is_action_pressed(HudBotOrder.ACTION)).is_true()
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_false()
	await _fixture.lift(0, _tag().get_center())
	await await_millis(250)
	# And off the tag the column's own place takes the finger, as it should.
	var elsewhere := Vector2(_fixture.host.size.x * 0.5, 40.0)
	assert_str(String(_fixture.controls.zone_at(elsewhere))).is_equal("scoreboard")


# --- The first-run hint ---


func test_the_hint_says_what_the_tag_does_the_first_time_bots_are_in_the_room() -> void:
	await _page(PAGES[0], 1.0, false, 0)
	var hints := _fixture.controls.hints
	assert_array(hints.showing()).not_contains([TouchHints.BOTS])
	_fixture.hud.state.apply_event({"type": &"player_added", "player_id": BOT_ID, "bot": true})
	await _settle()
	assert_array(hints.showing()).contains([TouchHints.BOTS])
	assert_str(hints.text_for(TouchHints.BOTS)).is_equal("TAP TO ORDER BOTS")
	var rect := hints.rect_of(TouchHints.BOTS)
	assert_bool(rect.intersects(_tag())).is_false()
	assert_bool(Rect2(Vector2.ZERO, _fixture.host.size).encloses(rect)).is_true()
	# It is read from the tag's side of the screen's middle, beside the tag.
	assert_float(absf(rect.get_center().y - _tag().get_center().y)).is_less(1.0)
	await _fixture.tap(_tag().get_center())
	assert_bool(hints.is_seen(TouchHints.BOTS)).is_true()
	await await_millis(500)
	assert_array(hints.showing()).not_contains([TouchHints.BOTS])
	# Gone for good: a second room with bots does not bring it back.
	_fixture.hud.state.apply_event({"type": &"player_removed", "player_id": BOT_ID})
	_fixture.hud.state.apply_event({"type": &"player_added", "player_id": BOT_ID, "bot": true})
	await _settle()
	assert_array(hints.showing()).not_contains([TouchHints.BOTS])


func test_the_hint_waits_while_a_prompt_is_up_so_it_never_covers_the_prompt_card() -> void:
	await _page(PAGES[0], 1.0)
	var hints := _fixture.controls.hints
	assert_array(hints.showing()).contains([TouchHints.BOTS])
	_fixture.hud.state.set_prompt(&"buy_door", "Concession door", 350)
	await _settle()
	assert_array(hints.showing()).not_contains([TouchHints.BOTS])
	_fixture.hud.state.clear_prompt()
	await _settle()
	assert_array(hints.showing()).contains([TouchHints.BOTS])


func test_the_hint_keeps_clear_of_the_tag_the_buttons_and_the_other_hints() -> void:
	await _every_page(
		func(page: Vector3, ui_scale: float, left: bool) -> void:
			var hints := _fixture.controls.hints
			var what := _label(page, ui_scale, left, "the bots hint")
			var rect := hints.rect_of(TouchHints.BOTS)
			(
				assert_bool(rect.intersects(_tag()))
				. override_failure_message(what + " covers the tag")
				. is_false()
			)
			(
				assert_bool(_fixture.controls.safe_rect().encloses(rect))
				. override_failure_message(what + " leaves the screen")
				. is_true()
			)
			for id: StringName in _fixture.controls.circles():
				var circle: Dictionary = _fixture.controls.circles()[id]
				var centre: Vector2 = circle[&"centre"]
				(
					assert_float(centre.distance_to(centre.clamp(rect.position, rect.end)))
					. override_failure_message("%s covers the %s button" % [what, id])
					. is_greater(float(circle[&"radius"]))
				)
			for id in [TouchHints.MOVE, TouchHints.LOOK]:
				(
					assert_bool(rect.intersects(hints.rect_of(id)))
					. override_failure_message("%s covers the %s hint" % [what, id])
					. is_false()
				)
	)
