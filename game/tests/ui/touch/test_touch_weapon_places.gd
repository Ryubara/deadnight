extends GdUnitTestSuite
## The HUD's weapons and grenades are the phone's weapon controls (Deadnight #1280): there is no
## Swap button and no Grenade button, a tap on a weapon's place in the HUD takes that weapon, a
## press and hold on the grenades' place cooks and the lift throws, and the places are a fingertip
## (44 CSS px) in each direction, clear of the stick and of the buttons for either hand, on the two
## phone pages (844 x 390 and 667 x 375 CSS px, a pixel ratio of 2) at every interface size. The
## HUD's nodes ignore the pointer and the touch layer takes every finger itself, so these are
## real touch events through the layer, as a browser would send them.

## Windows in pixels and the pixel ratio the browser reports.
const PAGES: Array[Vector3] = [Vector3(1688, 780, 2.0), Vector3(1334, 750, 2.0)]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
const HANDS: Array[bool] = [false, true]
## What a fingertip is, CSS px, and the slack a rounding up to whole units leaves.
const FINGER_CSS := 44.0
const SLACK_CSS := 0.05

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


## The page a player has: the window, the interface size and the ratio; the canvas it makes, the
## touch layer and the HUD laid out on it, in the hand asked for.
func _page(page: Vector3, ui_scale: float, left := false) -> void:
	var window := Vector2i(int(page.x), int(page.y))
	get_window().size = window
	get_window().content_scale_factor = ui_scale
	MenuScale.pixel_ratio = page.z
	var canvas := Vector2(window) / MenuScale.pixels_per_unit(window, ui_scale)
	_fixture = TouchFixture.make(self, canvas, null, false, true)
	if left:
		_fixture.left_handed(true)
	_fixture.controls.looked.connect(func(_motion: Vector2) -> void: _looks += 1)
	await _settle()


func _settle() -> void:
	for _i in 4:
		await get_tree().process_frame


func _css_per_unit(page: Vector3, ui_scale: float) -> float:
	var window := Vector2i(int(page.x), int(page.y))
	return MenuScale.pixels_per_unit(window, ui_scale) / page.z


func _rect_of(action: StringName) -> Rect2:
	for zone in _fixture.hud.slots.touch_zones():
		if zone[&"action"] == action:
			return zone[&"rect"]
	return Rect2()


func _every_page(check: Callable) -> void:
	for page in PAGES:
		for ui_scale in UI_SCALES:
			for left in HANDS:
				await _page(page, ui_scale, left)
				check.call(page, ui_scale, left)
				_fixture.free_all()
				_fixture = null


func _label(page: Vector3, ui_scale: float, left: bool, what: String) -> String:
	return "%s on %dx%d at %.2f, left hand %s" % [what, page.x, page.y, ui_scale, left]


func test_there_is_no_swap_button_and_no_grenade_button() -> void:
	for mirrored in HANDS:
		var circles := TouchLayout.buttons(Rect2(0, 0, 2337, 1080), 1.0, mirrored, 122.0)
		assert_bool(circles.has(&"swap_weapon")).is_false()
		assert_bool(circles.has(&"throw_grenade")).is_false()
	_fixture = TouchFixture.make(self, Vector2(2337, 1080), null, false, true)
	await _settle()
	assert_bool(_fixture.controls.circles().has(&"swap_weapon")).is_false()
	assert_bool(_fixture.controls.circles().has(&"throw_grenade")).is_false()


func test_a_place_for_each_weapon_and_one_for_the_grenades_with_their_count() -> void:
	await _page(PAGES[0], 1.0)
	var actions: Array[StringName] = []
	for zone in _fixture.hud.slots.touch_zones():
		actions.append(zone[&"action"])
	assert_array(actions).is_equal([&"weapon_slot_1", &"weapon_slot_2", &"throw_grenade"])
	_fixture.hud.state.apply_event({"type": &"grenade_count_changed", "player_id": 1, "count": 3})
	await _settle()
	var cell := _fixture.hud.slots.grenade_cell
	assert_int(cell.count).is_equal(3)
	assert_str(cell._number.text).is_equal("x3")


func test_every_place_is_at_least_a_fingertip_wide_and_high() -> void:
	await _every_page(
		func(page: Vector3, ui_scale: float, left: bool) -> void:
			var css := _css_per_unit(page, ui_scale)
			for zone in _fixture.hud.slots.touch_zones():
				var rect: Rect2 = zone[&"rect"]
				var wide := rect.size.x * css
				var high := rect.size.y * css
				(
					assert_float(minf(wide, high))
					. override_failure_message(
						(
							_label(page, ui_scale, left, str(zone[&"action"]))
							+ ": %.1f x %.1f CSS px" % [wide, high]
						)
					)
					. is_greater_equal(FINGER_CSS - SLACK_CSS)
				)
	)


func test_the_places_are_on_the_screen_and_clear_of_the_buttons_the_stick_and_the_cards() -> void:
	await _every_page(
		func(page: Vector3, ui_scale: float, left: bool) -> void:
			var controls := _fixture.controls
			var screen := Rect2(Vector2.ZERO, _fixture.host.size)
			var rest := TouchLayout.stick_rest(controls.safe_rect(), 1.0, left)
			var cards: Array[Control] = [
				_fixture.hud.ammo, _fixture.hud.prompt, _fixture.hud.health, _fixture.hud.points
			]
			for zone in _fixture.hud.slots.touch_zones():
				var rect: Rect2 = zone[&"rect"]
				var what := _label(page, ui_scale, left, str(zone[&"action"]))
				assert_bool(screen.encloses(rect)).override_failure_message(what).is_true()
				for id: StringName in controls.circles():
					var circle: Dictionary = controls.circles()[id]
					var reach := (circle[&"centre"] as Vector2).distance_to(
						(circle[&"centre"] as Vector2).clamp(rect.position, rect.end)
					)
					(
						assert_float(reach)
						. override_failure_message("%s touches the %s button" % [what, id])
						. is_greater(float(circle[&"hit"]))
					)
				var ring := rest.distance_to(rest.clamp(rect.position, rect.end))
				(
					assert_float(ring)
					. override_failure_message("%s touches the stick's ring" % what)
					. is_greater(TouchLayout.STICK_RADIUS)
				)
				for card in cards:
					(
						assert_bool(rect.intersects(card.get_global_rect()))
						. override_failure_message("%s is over the %s card" % [what, card.name])
						. is_false()
					)
	)


func test_the_boxes_world_markers_keep_clear_of_hold_every_place() -> void:
	await _page(PAGES[0], 1.0)
	var boxes := _fixture.controls.button_boxes()
	for zone in _fixture.hud.slots.touch_zones():
		(
			assert_bool(boxes.has(zone[&"rect"]))
			. override_failure_message(str(zone[&"action"]))
			. is_true()
		)
	# The buttons that are drawn (Interact only with a prompt, Strike only with a dead in reach) and
	# every place of the HUD: the three of the strip, and the players' column when there is a player
	# (#1287).
	var hidden := 0
	hidden += 1 if _fixture.controls.interact_verb() == "" else 0
	hidden += 0 if _fixture.controls.strike_up else 1
	assert_int(_fixture.hud.touch_zones().size()).is_equal(3)
	assert_int(boxes.size()).is_equal(_fixture.controls.circles().size() - hidden + 3)


func test_a_tap_on_a_weapon_presses_its_slot_and_never_fires_or_looks() -> void:
	await _page(PAGES[0], 1.0)
	for slot in 2:
		var action := WeaponSlots.ACTIONS[slot]
		var centre := _fixture.zone_centre(action)
		await _fixture.touch(0, centre)
		assert_bool(Input.is_action_pressed(action)).is_true()
		# The finger wanders off the place, as a thumb does: the view does not turn, nothing fires.
		var at := centre
		for _i in 6:
			at += Vector2(30.0, -10.0)
			await _fixture.drag(0, at, Vector2(30.0, -10.0), 600.0)
		await _fixture.settle_look()
		assert_int(_looks).is_equal(0)
		assert_bool(Input.is_action_pressed(&"fire")).is_false()
		assert_bool(Input.is_action_pressed(&"aim")).is_false()
		assert_bool(_fixture.controls.is_stick_down()).is_false()
		await _fixture.lift(0, at)
		await await_millis(250)
		assert_bool(Input.is_action_pressed(action)).is_false()


func test_a_quick_tap_on_a_weapon_lasts_long_enough_for_a_tick_to_see() -> void:
	await _page(PAGES[0], 1.0)
	await _fixture.tap(_fixture.zone_centre(&"weapon_slot_2"))
	assert_bool(Input.is_action_pressed(&"weapon_slot_2")).is_true()
	await await_millis(300)
	assert_bool(Input.is_action_pressed(&"weapon_slot_2")).is_false()


func test_a_finger_on_the_grenades_holds_the_throw_looks_while_it_drags_and_lets_go_on_the_lift(
) -> void:
	await _page(PAGES[0], 1.0)
	var centre := _fixture.zone_centre(&"throw_grenade")
	await _fixture.touch(0, centre)
	assert_bool(Input.is_action_pressed(&"throw_grenade")).is_true()
	await await_millis(300)
	# Still held while the finger rests: the pin stays out for as long as the thumb is down.
	assert_bool(Input.is_action_pressed(&"throw_grenade")).is_true()
	assert_array(Array(_fixture.controls.held_buttons())).contains(["throw_grenade"])
	var at := centre
	for _i in 8:
		at += Vector2(20.0, 0.0)
		await _fixture.drag(0, at, Vector2(20.0, 0.0), 600.0)
	await _fixture.settle_look()
	assert_int(_looks).is_greater(0)
	assert_bool(Input.is_action_pressed(&"throw_grenade")).is_true()
	await _fixture.lift(0, at)
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"throw_grenade")).is_false()


func test_the_grenades_place_is_lit_while_the_pin_is_out() -> void:
	await _page(PAGES[0], 1.0)
	var cell := _fixture.hud.slots.grenade_cell
	assert_bool(cell.held).is_false()
	await _fixture.touch(0, _fixture.zone_centre(&"throw_grenade"))
	await _settle()
	assert_bool(cell.held).is_true()
	await _fixture.lift(0)
	await await_millis(250)
	await _settle()
	assert_bool(cell.held).is_false()


func test_a_tap_beside_the_places_still_moves_or_looks_as_before() -> void:
	await _page(PAGES[0], 1.0)
	var places := _rect_of(&"weapon_slot_1")
	# Just above the strip, on the health card's side of it: not a place, so the stick's zone.
	var above := Vector2(places.get_center().x, places.position.y - 30.0)
	assert_str(String(_fixture.controls.zone_at(above))).is_equal("")
	await _fixture.touch(0, above)
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	await _fixture.lift(0)


func test_the_places_move_to_the_other_corner_for_a_left_hand_and_back() -> void:
	await _page(PAGES[0], 1.0)
	var right_handed := _rect_of(&"weapon_slot_1")
	assert_float(right_handed.get_center().x).is_less(_fixture.host.size.x * 0.5)
	_fixture.left_handed(true)
	await _settle()
	var left_handed := _rect_of(&"weapon_slot_1")
	assert_float(left_handed.get_center().x).is_greater(_fixture.host.size.x * 0.5)
	assert_bool(_fixture.controls.button_boxes().has(left_handed)).is_true()
	_fixture.left_handed(false)
	await _settle()
	assert_that(_rect_of(&"weapon_slot_1")).is_equal(right_handed)


func test_a_desktop_hud_keeps_its_strip_and_has_no_grenade_place() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var fixture := HudFixture.make(host)
	await _settle()
	var slots := fixture.hud.slots
	assert_bool(slots.touch).is_false()
	assert_object(slots.grenade_cell).is_null()
	assert_array(slots.touch_zones()).is_empty()
	assert_float(slots.get_global_rect().size.y).is_equal(HudSlots.HEIGHT)
	assert_bool(slots.get_parent() == fixture.hud.ammo.get_parent()).is_true()


func test_a_window_that_is_no_phones_never_makes_the_places_fill_the_screen() -> void:
	# A test's 64 pixel window asks `tap_units` for a fifth of the screen's height.
	get_window().size = Vector2i(64, 64)
	MenuScale.pixel_ratio = 1.0
	_fixture = TouchFixture.make(self, Vector2(1920.0, 1080.0), null, false, true)
	await _settle()
	var most := 1080.0 * Hud.FINGER_SHARE_MAX
	for zone in _fixture.hud.slots.touch_zones():
		var rect: Rect2 = zone[&"rect"]
		assert_float(rect.size.y).is_less_equal(most + 1.0)
		assert_float(rect.size.x).is_less_equal(most * HudSlots.TOUCH_WIDE + 1.0)
