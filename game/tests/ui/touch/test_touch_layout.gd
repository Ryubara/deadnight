# Where the touch controls sit: inside the safe area, big enough for a thumb, clear of each other
# and clear of the HUD cards that stay on screen, at every canvas a phone gives.
extends GdUnitTestSuite

## Canvases (canvas units) of a 16:9 phone, a 19.5:9 phone, a 20:9 phone and a browser with bars.
const CANVASES: Array[Vector2] = [
	Vector2(1920.0, 1080.0),
	Vector2(2340.0, 1080.0),
	Vector2(2400.0, 1080.0),
	Vector2(2340.0, 1080.0 * 0.8),
]
## The cards that never move and that the buttons must not cover.
## A right hand and a left hand (the layout flipped).
const HANDS: Array[bool] = [false, true]
const KEPT_PARTS: Array[StringName] = [
	&"ammo", &"prompt", &"health", &"perks", &"points", &"round_part", &"slots"
]
## The five buttons of the right thumb (#1277): one ring round Fire.
const RING: Array[StringName] = [
	TouchLayout.RELOAD, TouchLayout.AIM, TouchLayout.JUMP, TouchLayout.CROUCH
]
## A thumb needs 2 to 3 mm of air between neighbours: 2 mm is 12 CSS px, 33 units on a phone's night
## (0.36 CSS px a unit).
const LEAST_AIR := 30.0
## CSS pixels in a millimetre on a phone (the 6 of a 460 ppi, 3x phone), and what is a comfortable
## roll of the right thumb from where it rests on Fire, in millimetres.
const CSS_PX_PER_MM := 6.0
const RING_REACH_MM := 16.0
const INTERACT_REACH_MM := 30.0
## The CSS pixels of one unit on the two phone pages a night runs on (844 x 390 and 667 x 375).
const PAGE_UNITS := [0.361, 0.347]


func before_test() -> void:
	UIMotion.reduced = false


func _circles(
	canvas: Vector2, insets := Vector4.ZERO, touch_scale := 1.0, mirrored := false
) -> Dictionary:
	return TouchLayout.buttons(TouchLayout.safe_rect(canvas, insets), touch_scale, mirrored)


func test_every_button_is_inside_the_safe_area() -> void:
	var insets := Vector4(96.0, 0.0, 96.0, 24.0)
	for mirrored in HANDS:
		for canvas in CANVASES:
			var safe := TouchLayout.safe_rect(canvas, insets)
			var circles := TouchLayout.buttons(safe, 1.0, mirrored)
			for id: StringName in circles:
				var circle: Dictionary = circles[id]
				var box := Rect2(circle[&"centre"], Vector2.ZERO).grow(circle[&"radius"])
				(
					assert_bool(safe.encloses(box))
					. override_failure_message(
						"%s leaves %s on %s (mirrored %s)" % [id, safe, canvas, mirrored]
					)
					. is_true()
				)


func test_no_hit_area_is_smaller_than_a_thumb() -> void:
	for mirrored in HANDS:
		for scale_value in [0.8, 1.0, 1.4]:
			var circles := _circles(CANVASES[0], Vector4.ZERO, scale_value, mirrored)
			for id: StringName in circles:
				assert_float(circles[id][&"hit"]).is_greater_equal(TouchLayout.MIN_HIT)


func _air(a: Dictionary, b: Dictionary) -> float:
	var gap: float = (a[&"centre"] as Vector2).distance_to(b[&"centre"])
	return gap - float(a[&"radius"]) - float(b[&"radius"])


func test_the_right_thumbs_buttons_are_one_ring_round_fire_with_air_between_them() -> void:
	for mirrored in HANDS:
		for canvas in CANVASES:
			var circles := _circles(canvas, Vector4.ZERO, 1.0, mirrored)
			var fire: Dictionary = circles[TouchLayout.FIRE]
			for id in RING:
				# Round Fire at the same air (a few units for the whole numbers of the table).
				assert_float(_air(fire, circles[id])).is_equal_approx(TouchLayout.RING_GAP, 2.0)
			for i in RING.size():
				for j in range(i + 1, RING.size()):
					(
						assert_float(_air(circles[RING[i]], circles[RING[j]]))
						. override_failure_message("%s and %s are too close" % [RING[i], RING[j]])
						. is_greater_equal(LEAST_AIR)
					)
			# Interact, which shows at something to use, has air from every one of them too.
			for id in RING:
				assert_float(_air(circles[TouchLayout.INTERACT], circles[id])).is_greater_equal(
					LEAST_AIR
				)


func test_reload_is_right_next_to_fire_in_the_same_row() -> void:
	for mirrored in HANDS:
		var circles := _circles(CANVASES[1], Vector4.ZERO, 1.0, mirrored)
		var fire: Dictionary = circles[TouchLayout.FIRE]
		var reload: Dictionary = circles[TouchLayout.RELOAD]
		# Next to Fire: the same air the ring has, a thumb's width and no more.
		(
			assert_float(_air(fire, reload))
			. override_failure_message("Reload is not right next to Fire")
			. is_less_equal(TouchLayout.RING_GAP + 2.0)
		)
		var row: float = absf((fire[&"centre"] as Vector2).y - (reload[&"centre"] as Vector2).y)
		assert_float(row).is_less(float(reload[&"radius"]))
		# Toward the middle of the screen from Fire, the way a thumb slides along the row.
		var fire_x: float = (fire[&"centre"] as Vector2).x
		var reload_x: float = (reload[&"centre"] as Vector2).x
		assert_bool(reload_x > fire_x if mirrored else reload_x < fire_x).is_true()


func test_every_button_of_the_right_thumb_is_in_a_comfortable_reach_of_where_it_rests() -> void:
	# The thumb rests on Fire. On both phone pages, in millimetres of a phone (6 CSS px each).
	var circles := _circles(CANVASES[0])
	var fire: Vector2 = circles[TouchLayout.FIRE][&"centre"]
	for unit in PAGE_UNITS:
		for id in RING:
			var mm: float = fire.distance_to(circles[id][&"centre"]) * float(unit) / CSS_PX_PER_MM
			(
				assert_float(mm)
				. override_failure_message("%s is %.1f mm from Fire" % [id, mm])
				. is_less_equal(RING_REACH_MM)
			)
		var out: float = (
			fire.distance_to(circles[TouchLayout.INTERACT][&"centre"]) * float(unit) / CSS_PX_PER_MM
		)
		assert_float(out).is_less_equal(INTERACT_REACH_MM)


func test_every_button_of_the_table_is_a_right_button_that_looks_while_it_drags() -> void:
	for row in TouchLayout.BUTTONS:
		var id: StringName = row[0]
		(
			assert_bool(TouchLayout.looks_when_dragged(id))
			. override_failure_message("%s" % id)
			. is_true()
		)
	# The wheel is gone from the glass (#1286): the bots' order is a tag on the HUD.
	assert_bool(TouchLayout.buttons(Rect2(0, 0, 2337, 1080), 1.0).has(&"bot_wheel")).is_false()
	for id in [TouchLayout.PAUSE, TouchLayout.PING, TouchLayout.SCOREBOARD, &"nothing"]:
		assert_bool(TouchLayout.looks_when_dragged(id)).is_false()


func test_the_five_buttons_of_the_right_thumb_are_there() -> void:
	var circles := _circles(CANVASES[1])
	for id in [
		TouchLayout.FIRE, TouchLayout.AIM, TouchLayout.JUMP, TouchLayout.RELOAD, TouchLayout.CROUCH
	]:
		assert_bool(circles.has(id)).override_failure_message(str(id)).is_true()


func test_the_buttons_do_not_overlap_each_other() -> void:
	for mirrored in HANDS:
		for canvas in CANVASES:
			var circles := _circles(canvas, Vector4.ZERO, 1.0, mirrored)
			var ids := circles.keys()
			for i in ids.size():
				for j in range(i + 1, ids.size()):
					var a: Dictionary = circles[ids[i]]
					var b: Dictionary = circles[ids[j]]
					var gap: float = (a[&"centre"] as Vector2).distance_to(b[&"centre"])
					gap -= float(a[&"radius"]) + float(b[&"radius"])
					(
						assert_float(gap)
						. override_failure_message(
							"%s and %s touch on %s" % [ids[i], ids[j], canvas]
						)
						. is_greater(0.0)
					)


func test_the_buttons_leave_the_kept_hud_cards_alone_for_either_hand() -> void:
	for mirrored in HANDS:
		for canvas in CANVASES:
			var host: Control = auto_free(Control.new())
			host.size = canvas
			add_child(host)
			var fixture := HudFixture.make(host, NightHost.MAX_PLAYERS)
			# A left hand flips the HUD's corner columns with the buttons.
			fixture.hud.mirrored = mirrored
			fixture.hud.touch_layout = true
			fixture.into_round_one()
			fixture.give_perks(4)
			var state := fixture.hud.state
			state.set_ammo(30, 150, "Shotgun")
			state.set_area("The Concession Stand", "Light the booth to open the back lot")
			state.set_prompt(&"buy_door", "Projection booth door", 750)
			await await_idle_frame()
			await await_idle_frame()
			var circles := _circles(canvas, Vector4.ZERO, 1.0, mirrored)
			for part_name in KEPT_PARTS:
				var part: Control = fixture.hud.get(part_name)
				var rect := part.get_global_rect()
				(
					assert_float(rect.size.x)
					. override_failure_message("%s not laid out" % part_name)
					. is_greater(100.0)
				)
				for id: StringName in circles:
					var circle: Dictionary = circles[id]
					var centre: Vector2 = circle[&"centre"]
					var nearest := centre.clamp(rect.position, rect.end)
					(
						assert_float(nearest.distance_to(centre))
						. override_failure_message(
							(
								"%s covers the %s card on %s (mirrored %s)"
								% [id, part_name, canvas, mirrored]
							)
						)
						. is_greater(float(circle[&"radius"]))
					)


func test_the_left_hand_layout_is_the_right_hand_one_flipped_in_the_safe_area() -> void:
	var insets := Vector4(96.0, 0.0, 40.0, 24.0)
	for canvas in CANVASES:
		var safe := TouchLayout.safe_rect(canvas, insets)
		var right := TouchLayout.buttons(safe, 1.0)
		var left := TouchLayout.buttons(safe, 1.0, true)
		assert_array(left.keys()).contains_exactly_in_any_order(right.keys())
		for id: StringName in right:
			var was: Vector2 = right[id][&"centre"]
			var now: Vector2 = left[id][&"centre"]
			assert_float(now.x).is_equal_approx(safe.position.x + safe.end.x - was.x, 0.01)
			assert_float(now.y).is_equal_approx(was.y, 0.01)
			assert_float(left[id][&"radius"]).is_equal(right[id][&"radius"])
		var rest := TouchLayout.stick_rest(safe, 1.0)
		var rest_left := TouchLayout.stick_rest(safe, 1.0, true)
		assert_float(rest_left.x).is_equal_approx(safe.position.x + safe.end.x - rest.x, 0.01)
		var zone := TouchLayout.stick_zone(safe)
		var zone_left := TouchLayout.stick_zone(safe, true)
		assert_float(zone_left.position.x).is_equal_approx(safe.end.x - zone.size.x, 0.01)
		assert_float(zone_left.end.x).is_equal_approx(safe.end.x, 0.01)
		assert_float(zone.position.x).is_equal_approx(safe.position.x, 0.01)


func test_the_melee_button_is_on_screen_clear_of_fire_on_a_phones_540_unit_canvas() -> void:
	# The menu's phone factor halves the canvas to 540 units high and stays on in the night.
	var phone := Vector2(1168.5, 540.0)
	for mirrored in HANDS:
		var safe := TouchLayout.safe_rect(phone, Vector4.ZERO)
		var circles := TouchLayout.buttons(safe, 1.0, mirrored)
		var melee: Dictionary = circles[TouchLayout.MELEE]
		var fire: Dictionary = circles[TouchLayout.FIRE]
		var box := Rect2(melee[&"centre"], Vector2.ZERO).grow(melee[&"radius"])
		(
			assert_bool(safe.encloses(box))
			. override_failure_message(
				"melee leaves %s (mirrored %s): %s" % [safe, mirrored, melee]
			)
			. is_true()
		)
		var gap: float = (melee[&"centre"] as Vector2).distance_to(fire[&"centre"])
		assert_float(gap).is_greater(float(melee[&"radius"]) + float(fire[&"radius"]))


func test_the_ping_button_is_on_screen_clear_of_the_rest_on_the_smallest_phone_canvas() -> void:
	# A night runs at the interface size alone (#1192): the least canvas is the 667 x 375 page at
	# 1.25, 1536 x 864 units (it was the menu's 540 unit phone factor, which a night no longer has).
	var phone := Vector2(1536.0, 864.0)
	for mirrored in HANDS:
		var safe := TouchLayout.safe_rect(phone, Vector4.ZERO)
		var circles := TouchLayout.buttons(safe, 1.0, mirrored)
		for id in [TouchLayout.PING]:
			var circle: Dictionary = circles[id]
			var box := Rect2(circle[&"centre"], Vector2.ZERO).grow(circle[&"radius"])
			(
				assert_bool(safe.encloses(box))
				. override_failure_message("%s leaves %s (mirrored %s)" % [id, safe, mirrored])
				. is_true()
			)
			# Clear of every other button.
			for other: StringName in circles:
				if other == id:
					continue
				var gap: float = (circle[&"centre"] as Vector2).distance_to(
					circles[other][&"centre"]
				)
				gap -= float(circle[&"radius"]) + float(circles[other][&"radius"])
				(
					assert_float(gap)
					. override_failure_message("%s touches %s on %s" % [id, other, phone])
					. is_greater(0.0)
				)
			# Off the view: outside the middle 40 percent of the width that stays clear (the ping,
			# under Pause, #1289: it was on the top band before).
			var centre: Vector2 = circle[&"centre"]
			var clear := phone.x * (0.2 if id == TouchLayout.PING else 0.4)
			(
				assert_bool(absf(centre.x - phone.x * 0.5) > clear)
				. override_failure_message("%s is over the view on %s" % [id, phone])
				. is_true()
			)


func test_the_shoulder_button_sits_clear_of_the_thumb_arc_and_the_look_area_stays_free() -> void:
	for mirrored in HANDS:
		var circles := _circles(CANVASES[1], Vector4.ZERO, 1.0, mirrored)
		var side: Dictionary = circles[TouchLayout.SHOULDER]
		var centre: Vector2 = side[&"centre"]
		# Not in the middle 40 percent of the width, which is the view.
		assert_float(absf(centre.x - CANVASES[1].x * 0.5)).is_greater(CANVASES[1].x * 0.2)


func test_a_notch_moves_the_buttons_in_with_the_safe_area() -> void:
	var flat := _circles(CANVASES[1])
	var notched := _circles(CANVASES[1], Vector4(100.0, 0.0, 100.0, 30.0))
	var fire_flat: Vector2 = flat[TouchLayout.FIRE][&"centre"]
	var fire_notched: Vector2 = notched[TouchLayout.FIRE][&"centre"]
	assert_vector(fire_flat - fire_notched).is_equal(Vector2(100.0, 30.0))


func test_insets_come_from_the_platform_safe_rectangle() -> void:
	# A 2340 x 1080 pixel screen, 132 px notch on the left, 66 px on the right, 63 px home bar.
	var insets := TouchLayout.insets_from(
		Rect2i(132, 0, 2142, 1017), Vector2i(2340, 1080), Vector2(2340.0, 1080.0)
	)
	assert_vector(Vector2(insets.x, insets.y)).is_equal(Vector2(132.0, 0.0))
	assert_float(insets.z).is_equal(66.0)
	assert_float(insets.w).is_equal(63.0)
	assert_object(TouchLayout.insets_from(Rect2i(), Vector2i(2340, 1080), Vector2.ONE)).is_equal(
		Vector4.ZERO
	)


func test_a_larger_touch_scale_grows_the_buttons_from_the_thumb_corner() -> void:
	var small := _circles(CANVASES[0], Vector4.ZERO, 1.0)
	var big := _circles(CANVASES[0], Vector4.ZERO, 1.3)
	assert_float(big[TouchLayout.FIRE][&"radius"]).is_equal_approx(130.0, 0.001)
	var corner := Vector2(1920.0, 1080.0)
	var from_small: float = (small[TouchLayout.FIRE][&"centre"] as Vector2).distance_to(corner)
	var from_big: float = (big[TouchLayout.FIRE][&"centre"] as Vector2).distance_to(corner)
	assert_float(from_big / from_small).is_equal_approx(1.3, 0.001)
