# Ping stands under Pause with a thumb's room between them (Deadnight #1289). On the top edge they
# were 27 CSS px apart, a thumb's width: a tap meant for one could pause the night. What the tests
# hold, on the two pages a phone has (844 x 390 and 667 x 375 CSS px at a pixel ratio of 2), at the
# three interface sizes and with either hand:
#   - Ping is straight under Pause, 54 CSS px (9 mm) or more from its centre, with 2 mm or more of
#     air between the rims of the drawn buttons and between the hit areas;
#   - Pause is the only other control on the top edge;
#   - Ping is clear of the HUD's cards (the round card, the objective, the popup lane) and the
#     stick's zone starts below its hit area;
#   - a finger on either never presses the other, edge to edge.
extends GdUnitTestSuite

## 844 x 390 and 667 x 375 CSS px pages at a pixel ratio of 2: the windows the browser gives.
const PAGES: Array[Vector2i] = [Vector2i(1688, 780), Vector2i(1334, 750)]
const RATIO := 2.0
const INTERFACE_SIZES: Array[float] = [0.8, 1.0, 1.25]
const TOUCH_SIZES: Array[float] = [0.8, 1.0, 1.4]
const HANDS: Array[bool] = [false, true]
## 9 mm on a phone (6 CSS px a millimetre) and the 2 mm of air a thumb needs between neighbours.
const LEAST_CENTRES_CSS := 54.0
const LEAST_AIR_CSS := 12.0
## A pixel's tolerance: a rounded-up unit count can still be a hair under in pixels.
const SLACK := 0.3
## The notch of the wider phone, CSS px at each side (an 844 x 390 phone's is 47 in landscape), the
## 667 x 375 phone has none, and the home bar's 12 CSS px at the bottom of both.
const NOTCH_CSS := 47.0
const BAR_CSS := 12.0

var _saved_size := Vector2i.ZERO
var _saved_scale := 1.0
var _fixture: TouchFixture
var _host: Control


func before_test() -> void:
	_saved_size = get_window().size
	_saved_scale = get_window().content_scale_factor
	MenuScale.pixel_ratio = RATIO
	TouchMode.device_is_touch = true


func after_test() -> void:
	if _fixture != null:
		_fixture.free_all()
		_fixture = null
	if is_instance_valid(_host):
		_host.free()
	get_window().size = _saved_size
	get_window().content_scale_factor = _saved_scale
	MenuScale.pixel_ratio = -1.0
	TouchMode.device_is_touch = null


## The page's window and interface size, then its canvas in units.
func _page(window: Vector2i, ui_scale: float) -> Vector2:
	get_window().size = window
	get_window().content_scale_factor = ui_scale
	return Vector2(window) / MenuScale.pixels_per_unit(window, ui_scale)


func _css(window: Vector2i, ui_scale: float) -> float:
	return MenuScale.pixels_per_unit(window, ui_scale) / RATIO


## The insets of the page in canvas units (the window is already on the page's size and scale).
func _insets(window: Vector2i, ui_scale: float) -> Vector4:
	var notch := NOTCH_CSS if window == PAGES[0] else 0.0
	var css := _css(window, ui_scale)
	return Vector4(notch, 0.0, notch, BAR_CSS) / css


func _circles(canvas: Vector2, touch_scale: float, mirrored: bool) -> Dictionary:
	var finger := MenuScale.tap_units(get_window(), true)
	var safe := TouchLayout.safe_rect(
		canvas, _insets(get_window().size, get_window().content_scale_factor)
	)
	return TouchLayout.buttons(safe, touch_scale, mirrored, finger)


func _gap(a: Dictionary, b: Dictionary, key: StringName) -> float:
	var apart: float = (a[&"centre"] as Vector2).distance_to(b[&"centre"])
	return apart - float(a[key]) - float(b[key])


func test_ping_is_under_pause_a_thumb_apart_at_every_page_size_and_hand() -> void:
	var faults: Array[String] = []
	for window in PAGES:
		for ui_scale in INTERFACE_SIZES:
			var canvas := _page(window, ui_scale)
			var css := _css(window, ui_scale)
			for touch_scale in TOUCH_SIZES:
				for mirrored in HANDS:
					var circles := _circles(canvas, touch_scale, mirrored)
					var pause: Dictionary = circles[TouchLayout.PAUSE]
					var ping: Dictionary = circles[TouchLayout.PING]
					var where := (
						"%s at %s, size %s%s"
						% [window, ui_scale, touch_scale, ", mirrored" if mirrored else ""]
					)
					var drop: Vector2 = ping[&"centre"] - pause[&"centre"]
					if absf(drop.x) > 0.01 or drop.y <= 0.0:
						faults.append("%s: Ping is not straight under Pause: %s" % [where, drop])
					var centres := drop.length() * css
					if centres < LEAST_CENTRES_CSS - SLACK:
						faults.append("%s: %.1f CSS px from Pause's centre" % [where, centres])
					var rims := _gap(pause, ping, &"radius") * css
					if rims < LEAST_AIR_CSS - SLACK:
						faults.append("%s: %.1f CSS px of air between the rims" % [where, rims])
					var hits := _gap(pause, ping, &"hit") * css
					if hits < LEAST_AIR_CSS * 0.5 - SLACK:
						faults.append("%s: %.1f CSS px between the hit areas" % [where, hits])
	assert_array(faults).is_empty()


func test_where_no_fingertip_is_known_ping_is_still_a_thumb_from_pause() -> void:
	# A desktop window and every test that asks for no fingertip rule: the fallback is 54 CSS px at
	# the default page's 0.36 CSS px a unit.
	var safe := TouchLayout.safe_rect(Vector2(2340.0, 1080.0), Vector4.ZERO)
	var circles := TouchLayout.buttons(safe, 1.0)
	var gap: float = (circles[TouchLayout.PING][&"centre"] as Vector2).distance_to(
		circles[TouchLayout.PAUSE][&"centre"]
	)
	assert_float(gap).is_equal(TouchLayout.PING_DROP)
	assert_float(gap * 0.36).is_greater_equal(LEAST_CENTRES_CSS - 1.0)


func test_pause_is_the_only_other_control_on_the_top_edge() -> void:
	var faults: Array[String] = []
	for window in PAGES:
		for ui_scale in INTERFACE_SIZES:
			var canvas := _page(window, ui_scale)
			for mirrored in HANDS:
				var circles := _circles(canvas, 1.0, mirrored)
				var pause: Dictionary = circles[TouchLayout.PAUSE]
				for id: StringName in circles:
					var circle: Dictionary = circles[id]
					var on_the_edge := (
						absf(circle[&"centre"].y - pause[&"centre"].y) < float(pause[&"hit"])
					)
					if on_the_edge and id != TouchLayout.PAUSE:
						faults.append("%s is on the top edge at %s, %s" % [id, window, ui_scale])
				if (
					circles[TouchLayout.PING][&"centre"].y
					< pause[&"centre"].y + float(pause[&"hit"])
				):
					faults.append("Ping is not under Pause at %s, %s" % [window, ui_scale])
	assert_array(faults).is_empty()


func test_the_stick_zone_starts_below_pings_hit_area() -> void:
	var faults: Array[String] = []
	for window in PAGES:
		for ui_scale in INTERFACE_SIZES:
			var canvas := _page(window, ui_scale)
			for mirrored in HANDS:
				var controls := _controls(canvas, mirrored)
				var ping := controls.button_circle(TouchLayout.PING)
				var bottom: float = (ping[&"centre"] as Vector2).y + float(ping[&"hit"])
				# A finger just inside the zone's top corner beside Ping starts the stick, one on the
				# button's edge does not start it.
				var zone := controls._stick_zone()
				if zone.position.y < bottom - 0.01:
					faults.append(
						(
							"%s, %s: the zone starts at %s, Ping ends at %s"
							% [window, ui_scale, zone.position.y, bottom]
						)
					)
				var plain := TouchLayout.stick_zone(controls.safe_rect(), mirrored)
				if zone.position.y < plain.position.y or not zone.end.is_equal_approx(plain.end):
					faults.append("%s, %s: the zone was moved but for its top" % [window, ui_scale])
				_free_controls()
	assert_array(faults).is_empty()


func test_a_finger_never_presses_the_other_of_pause_and_ping_edge_to_edge() -> void:
	var faults: Array[String] = []
	for window in PAGES:
		for ui_scale in INTERFACE_SIZES:
			var canvas := _page(window, ui_scale)
			for mirrored in HANDS:
				var controls := _controls(canvas, mirrored)
				var pause := controls.button_circle(TouchLayout.PAUSE)
				var ping := controls.button_circle(TouchLayout.PING)
				var from: Vector2 = pause[&"centre"]
				var to: Vector2 = ping[&"centre"]
				var toward := (to - from).normalized()
				# Every point of the line from one centre to the other (past both): the button
				# under it is the one whose hit area holds it.
				var at := -float(pause[&"hit"]) * 0.5
				var end := from.distance_to(to) + float(ping[&"hit"]) * 0.5
				while at <= end:
					var point := from + toward * at
					var got := TouchLayout.button_at(point, controls.circles())
					var in_pause := point.distance_to(from) <= float(pause[&"hit"])
					var in_ping := point.distance_to(to) <= float(ping[&"hit"])
					var want := &""
					if in_pause:
						want = TouchLayout.PAUSE
					elif in_ping:
						want = TouchLayout.PING
					if in_pause and in_ping:
						faults.append("the hit areas meet at %s, %s" % [window, ui_scale])
					if got != want and want != &"":
						faults.append(
							"%s at %s, %s: %s pressed %s" % [point, window, ui_scale, want, got]
						)
					at += 3.0
				_free_controls()
	assert_array(faults.slice(0, 6)).is_empty()


## The same with real touches: a finger lands on each button's hit edge facing the other and on the
## gap between them, and the game holds the one it is on and nothing else.
func test_real_touches_on_the_facing_edges_press_their_own_button_and_the_gap_none() -> void:
	for window in PAGES:
		for ui_scale in INTERFACE_SIZES:
			var canvas := _page(window, ui_scale)
			for mirrored in HANDS:
				var controls := _controls(canvas, mirrored)
				var pause := controls.button_circle(TouchLayout.PAUSE)
				var ping := controls.button_circle(TouchLayout.PING)
				var pause_edge: Vector2 = (
					pause[&"centre"] + Vector2.DOWN * (float(pause[&"hit"]) - 2.0)
				)
				var ping_edge: Vector2 = ping[&"centre"] + Vector2.UP * (float(ping[&"hit"]) - 2.0)
				var gap_middle: Vector2 = pause_edge.lerp(ping_edge, 0.5)
				var where := "%s at %s%s" % [window, ui_scale, ", mirrored" if mirrored else ""]
				await _fixture.touch(0, pause_edge)
				(
					assert_array(controls.held_buttons())
					. override_failure_message("%s: Pause's edge" % where)
					. contains_exactly([&"pause"])
				)
				await _fixture.lift(0, pause_edge)
				await _fixture.touch(0, ping_edge)
				(
					assert_array(controls.held_buttons())
					. override_failure_message("%s: Ping's edge" % where)
					. contains_exactly([&"ping"])
				)
				await _fixture.lift(0, ping_edge)
				await _fixture.touch(0, gap_middle)
				(
					assert_array(controls.held_buttons())
					. override_failure_message("%s: the gap" % where)
					. is_empty()
				)
				await _fixture.lift(0, gap_middle)
				_free_controls()


## A touch layer over this page's canvas with the night's finger rule, and the hand.
func _controls(canvas: Vector2, mirrored: bool) -> TouchControls:
	var finger := MenuScale.tap_units(get_window(), true)
	_fixture = TouchFixture.make(self, canvas)
	if mirrored:
		_fixture.left_handed()
	_fixture.controls.insets_override = _insets(
		get_window().size, get_window().content_scale_factor
	)
	_fixture.controls.finger_units = func() -> float: return finger
	_fixture.controls.refresh()
	return _fixture.controls


func _free_controls() -> void:
	_fixture.free_all()
	_fixture = null


## The busiest top of the night: a late round with four players, a boss, a banner, a prompt and
## three cards on the lane. Ping's hit area never meets a card, a part of the HUD or the popups.
func test_ping_is_clear_of_the_cards_and_the_popup_lane_on_the_busiest_hud() -> void:
	var faults: Array[String] = []
	for window in PAGES:
		for ui_scale in INTERFACE_SIZES:
			for mirrored in HANDS:
				faults.append_array(await _clear_of_the_hud(window, ui_scale, mirrored))
	assert_array(faults).is_empty()


func _clear_of_the_hud(window: Vector2i, ui_scale: float, mirrored: bool) -> Array[String]:
	var canvas := _page(window, ui_scale)
	var insets := _insets(window, ui_scale)
	_host = Control.new()
	_host.size = canvas
	add_child(_host)
	var fixture := HudFixture.make(_host, 4)
	var hud := fixture.hud
	hud.popups.process_mode = Node.PROCESS_MODE_DISABLED
	fixture.fill_late_round()
	hud.touch_layout = true
	hud.mirrored = mirrored
	hud.offset_left = insets.x
	hud.offset_top = insets.y
	hud.offset_right = -insets.z
	hud.offset_bottom = -insets.w
	hud.state.set_prompt(&"buy_door", "Projection booth door", 750)
	hud.banner.show_banner("ROUND 24 SURVIVED", "CATCH YOUR BREATH", HudBanner.Rank.ROUND)
	var boss := {
		"type": &"zombie_spawn_requested",
		"zombie_id": 901,
		"zombie_type": &"headliner",
		"boss": true,
		"health": 1000.0,
	}
	hud.state.apply_event(boss)
	(
		hud
		. feed(
			[
				{"type": &"level_up", "player_id": 1, "level": 12, "total": 0},
				{
					"type": &"unlock_earned",
					"player_id": 1,
					"level": 12,
					"slot": &"top",
					"item": &"letter_jacket",
				},
			]
		)
	)
	for _i in 40:
		await await_idle_frame()
		hud.popups.advance(0.05)
	var circles := _circles(canvas, 1.0, mirrored)
	var found: Array[String] = []
	var where := "%s at %s%s" % [window, ui_scale, ", mirrored" if mirrored else ""]
	if hud.popups.cards().is_empty():
		found.append("%s: no popup card stands" % where)
	var rects: Dictionary = {}
	for part in hud.boxed_parts():
		if part.is_visible_in_tree():
			rects[String(part.name)] = Rect2(part.get_global_rect())
	for card in hud.popups.cards():
		rects["popup card %d" % rects.size()] = Rect2(card.get_global_rect())
	for id in [TouchLayout.PING, TouchLayout.PAUSE]:
		var circle: Dictionary = circles[id]
		var centre: Vector2 = circle[&"centre"]
		for part_name: String in rects:
			var rect: Rect2 = rects[part_name]
			if rect.size.x < 1.0:
				continue
			if centre.clamp(rect.position, rect.end).distance_to(centre) <= float(circle[&"hit"]):
				found.append("%s: the %s hit area meets %s %s" % [where, id, part_name, rect])
	_host.free()
	_host = null
	return found
