# The touch layer's hit areas are a fingertip, and which button wins a touch where they overlap is
# decided on purpose (Deadnight #1217). A phone's page is 844 x 390 CSS px at a pixel ratio of 2,
# a 1688 x 780 window; a night runs at the interface size alone, so at 0.8 one unit is 0.29 CSS px
# and the 66 unit hit areas of Pause, Ping, Scoreboard, Bot wheel and Melee were 38 to 39 CSS px.
# The rule these tests hold (`TouchLayout.button_at`):
#   1. Where two buttons' old areas overlap, the first in order wins, as it always did.
#   2. The margin added to reach a fingertip belongs to the nearest centre and takes nothing from
#      an old area.
extends GdUnitTestSuite

const PHONE_WINDOW := Vector2i(1688, 780)
const PHONE_RATIO := 2.0
const INTERFACE_SIZES: Array[float] = [0.8, 1.0, 1.25]
const TOUCH_SIZES: Array[float] = [0.8, 1.0, 1.4]
const HANDS: Array[bool] = [false, true]
## A pixel's tolerance: a rounded-up unit count can still be a hair under in pixels.
const SLACK := 0.5
## The buttons that grow at the default touch size and the smallest interface size.
const SMALL: Array[StringName] = [
	TouchLayout.PAUSE,
	TouchLayout.PING,
	TouchLayout.SCOREBOARD,
	TouchLayout.BOT_WHEEL,
]
## Where a point's step is checked on the grid sweep, in canvas units.
const GRID_STEP := 7.0

var _saved_size := Vector2i.ZERO
var _saved_scale := 1.0
var _fixture: TouchFixture
var _looks: Array[Vector2] = []


func before_test() -> void:
	_saved_size = get_window().size
	_saved_scale = get_window().content_scale_factor
	MenuScale.pixel_ratio = PHONE_RATIO
	TouchMode.device_is_touch = true


func after_test() -> void:
	if _fixture != null:
		_fixture.free_all()
		_fixture = null
	get_window().size = _saved_size
	get_window().content_scale_factor = _saved_scale
	MenuScale.pixel_ratio = -1.0
	TouchMode.device_is_touch = null


## The units of a fingertip in a night at this interface size on the phone's page.
func _finger(ui_scale: float) -> float:
	get_window().size = PHONE_WINDOW
	get_window().content_scale_factor = ui_scale
	return MenuScale.tap_units(get_window(), true)


## CSS pixels in one canvas unit of the phone's page at this interface size.
func _css(ui_scale: float) -> float:
	return MenuScale.pixels_per_unit(PHONE_WINDOW, ui_scale) / PHONE_RATIO


func _canvas(ui_scale: float) -> Vector2:
	return Vector2(PHONE_WINDOW) / MenuScale.pixels_per_unit(PHONE_WINDOW, ui_scale)


func _circles(
	ui_scale: float, touch_scale := 1.0, mirrored := false, floor_on := true
) -> Dictionary:
	var finger := _finger(ui_scale) if floor_on else 0.0
	var safe := Rect2(Vector2.ZERO, _canvas(ui_scale))
	return TouchLayout.buttons(safe, touch_scale, mirrored, finger)


## A fixture over the phone page's canvas at this interface size, with the night's finger rule.
func _controls(ui_scale: float, mirrored := false) -> TouchFixture:
	var finger := _finger(ui_scale)
	if _fixture != null:
		_fixture.free_all()
	_fixture = TouchFixture.make(self, _canvas(ui_scale))
	if mirrored:
		_fixture.left_handed()
	_fixture.controls.finger_units = func() -> float: return finger
	_fixture.controls.refresh()
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: _looks.append(relative))
	_looks.clear()
	return _fixture


func _centre(id: StringName) -> Vector2:
	return _fixture.controls.button_circle(id)[&"centre"]


func _hit(id: StringName) -> float:
	return _fixture.controls.button_circle(id)[&"hit"]


func _was(id: StringName) -> float:
	return _fixture.controls.button_circle(id)[&"was"]


## A finger down on `point` and lifted: the button it pressed (`TouchLayout.PAUSE`, ...), or "" when
## it is the stick's or the look's. The finger is lifted again.
func _press(point: Vector2) -> StringName:
	await _fixture.touch(0, point)
	var found := &""
	var held := _fixture.controls.held_buttons()
	if held.size() == 1:
		found = StringName(held[0])
	await _fixture.lift(0, point)
	await get_tree().process_frame
	return found


func test_a_hit_area_is_a_fingertip_at_every_interface_and_touch_size_and_hand() -> void:
	var faults: Array[String] = []
	for ui_scale in INTERFACE_SIZES:
		for touch_scale in TOUCH_SIZES:
			for mirrored in HANDS:
				var circles := _circles(ui_scale, touch_scale, mirrored)
				for id: StringName in circles:
					var css: float = float(circles[id][&"hit"]) * 2.0 * _css(ui_scale)
					if css < MenuScale.TAP_PIXELS - SLACK:
						faults.append(
							"%s at %s, size %s: %.1f CSS px" % [id, ui_scale, touch_scale, css]
						)
	assert_array(faults).is_empty()


func test_the_interface_size_that_was_short_is_short_without_the_rule() -> void:
	# The reproduction on main: with no fingertip rule the four small buttons are 38 to 39 CSS px.
	var circles := _circles(0.8, 1.0, false, false)
	for id in SMALL:
		var css: float = float(circles[id][&"hit"]) * 2.0 * _css(0.8)
		assert_float(css).is_between(37.0, 40.0)


func test_the_drawn_buttons_are_the_size_they_were() -> void:
	var with_rule := _circles(0.8)
	var without := _circles(0.8, 1.0, false, false)
	for id: StringName in with_rule:
		assert_float(with_rule[id][&"radius"]).is_equal(without[id][&"radius"])
		assert_vector(with_rule[id][&"centre"]).is_equal(without[id][&"centre"])
		assert_float(with_rule[id][&"was"]).is_equal(without[id][&"hit"])


func test_fire_aim_and_the_big_buttons_keep_their_hit_areas_at_the_default_touch_size() -> void:
	for ui_scale in INTERFACE_SIZES:
		var with_rule := _circles(ui_scale)
		var without := _circles(ui_scale, 1.0, false, false)
		for id: StringName in [
			TouchLayout.FIRE,
			TouchLayout.AIM,
			TouchLayout.INTERACT,
			TouchLayout.JUMP,
			TouchLayout.RELOAD,
		]:
			assert_float(with_rule[id][&"hit"]).is_equal(without[id][&"hit"])


## The rule over every point of the page: a touch that pressed a button before presses the same
## button now, and a touch that pressed nothing presses a button only inside a grown margin.
func test_a_touch_that_pressed_a_button_presses_the_same_button_and_the_rest_is_margin() -> void:
	var faults: Array[String] = []
	var gained := 0
	for ui_scale in INTERFACE_SIZES:
		for mirrored in HANDS:
			var after := _circles(ui_scale, 1.0, mirrored)
			var before := _circles(ui_scale, 1.0, mirrored, false)
			var canvas := _canvas(ui_scale)
			var y := 0.0
			while y < canvas.y:
				var x := 0.0
				while x < canvas.x:
					var point := Vector2(x, y)
					var was := TouchLayout.button_at(point, before)
					var now := TouchLayout.button_at(point, after)
					if was != &"" and now != was:
						faults.append("%s at %s: %s became %s" % [point, ui_scale, was, now])
					if was == &"" and now != &"":
						gained += 1
						var gap: float = point.distance_to(after[now][&"centre"])
						if gap > float(after[now][&"hit"]) or gap <= float(after[now][&"was"]):
							faults.append(
								"%s at %s: %s is not in %s's margin" % [point, ui_scale, now, now]
							)
					x += GRID_STEP
				y += GRID_STEP
	assert_array(faults.slice(0, 5)).is_empty()
	# And the margin is real: at 0.8 a ring is gained round each of the four.
	assert_int(gained).is_greater(200)


## Ping and Scoreboard: no old overlap, a new one in the margin. The nearest centre wins there.
func test_in_the_new_margin_between_ping_and_scoreboard_the_nearest_centre_wins() -> void:
	_controls(0.8)
	var ping := _centre(TouchLayout.PING)
	var board := _centre(TouchLayout.SCOREBOARD)
	var middle := ping.lerp(board, 0.5)
	# Both hit areas reach the middle, neither old one did.
	assert_float(middle.distance_to(ping)).is_less(_hit(TouchLayout.PING))
	assert_float(middle.distance_to(ping)).is_greater(_was(TouchLayout.PING))
	assert_object(await _press(ping.lerp(board, 0.45))).is_equal(TouchLayout.PING)
	assert_object(await _press(ping.lerp(board, 0.55))).is_equal(TouchLayout.SCOREBOARD)


## Where old areas overlapped, the first in the order wins, as before: Pause over Ping over
## Scoreboard, and Interact over Strike, whatever the nearest centre.
func test_where_old_areas_overlap_the_first_in_order_still_wins() -> void:
	_controls(0.8)
	var pause := _centre(TouchLayout.PAUSE)
	var ping := _centre(TouchLayout.PING)
	var board := _centre(TouchLayout.SCOREBOARD)
	# Inside Pause's old area and nearer to Ping's centre: Pause.
	var toward_ping := pause + (ping - pause).normalized() * (_was(TouchLayout.PAUSE) - 4.0)
	assert_float(toward_ping.distance_to(ping)).is_less(toward_ping.distance_to(pause))
	assert_object(await _press(toward_ping)).is_equal(TouchLayout.PAUSE)
	# Pause and Scoreboard: the middle of the two is Pause's.
	assert_object(await _press(pause.lerp(board, 0.5))).is_equal(TouchLayout.PAUSE)
	# The centres themselves are their own.
	assert_object(await _press(ping)).is_equal(TouchLayout.PING)
	assert_object(await _press(board)).is_equal(TouchLayout.SCOREBOARD)
	# Interact over Strike, the two contextual buttons: a point inside both old areas and nearer
	# Strike's centre is Interact's while it is up, and Strike's when it is not.
	var circles := _fixture.controls.circles()
	var interact := _centre(TouchLayout.INTERACT)
	var strike := _centre(TouchLayout.STRIKE)
	var toward_strike := (
		interact + (strike - interact).normalized() * (_was(TouchLayout.INTERACT) - 4.0)
	)
	assert_float(toward_strike.distance_to(strike)).is_less(toward_strike.distance_to(interact))
	assert_float(toward_strike.distance_to(strike)).is_less(_was(TouchLayout.STRIKE))
	assert_object(TouchLayout.button_at(toward_strike, circles)).is_equal(TouchLayout.INTERACT)
	var without_interact := TouchLayout.button_at(toward_strike, circles, [TouchLayout.INTERACT])
	assert_object(without_interact).is_equal(TouchLayout.STRIKE)


## A finger on the new margin of each of the four presses it; with no rule the same touch was the
## look or the stick.
func test_a_finger_in_the_margin_of_a_small_button_presses_it() -> void:
	for mirrored in HANDS:
		_controls(0.8, mirrored)
		var before := _circles(0.8, 1.0, mirrored, false)
		for id in SMALL:
			var spot := _free_direction_spot(id)
			(
				assert_object(await _press(spot))
				. override_failure_message("%s (mirrored %s) at %s" % [id, mirrored, spot])
				. is_equal(id)
			)
			assert_object(TouchLayout.button_at(spot, before)).is_equal(&"")


## A point in `id`'s margin, in the direction with the most room from every other old area.
func _free_direction_spot(id: StringName) -> Vector2:
	var circle: Dictionary = _fixture.controls.button_circle(id)
	var radius: float = (float(circle[&"was"]) + float(circle[&"hit"])) * 0.5
	var best := Vector2.ZERO
	var best_room := -INF
	var canvas := _canvas(0.8)
	for step in 24:
		var spot: Vector2 = circle[&"centre"] + Vector2.RIGHT.rotated(TAU * step / 24.0) * radius
		if spot.x < 0.0 or spot.y < 0.0 or spot.x > canvas.x or spot.y > canvas.y:
			continue
		var room := INF
		for other: StringName in _fixture.controls.circles():
			if other != id:
				var theirs: Dictionary = _fixture.controls.circles()[other]
				room = minf(room, spot.distance_to(theirs[&"centre"]) - float(theirs[&"hit"]))
		if room > best_room:
			best_room = room
			best = spot
	return best


## Just outside the margin a drag is a look again; just inside it presses and does not look.
func test_a_look_that_starts_just_outside_a_margin_still_looks() -> void:
	_controls(0.8)
	var ping := _centre(TouchLayout.PING)
	var inside := ping + Vector2.RIGHT * (_hit(TouchLayout.PING) - 3.0)
	var outside := ping + Vector2.RIGHT * (_hit(TouchLayout.PING) + 3.0)
	await _fixture.touch(0, inside)
	await _fixture.drag(0, inside + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
	await _fixture.lift(0)
	assert_array(_looks).is_empty()
	await _fixture.touch(0, outside)
	await _fixture.drag(0, outside + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
	await _fixture.lift(0)
	assert_int(_looks.size()).is_equal(1)
	assert_float(_looks[0].x).is_greater(0.0)


## The stick starts where it did: anywhere in its zone that no hit area holds.
func test_the_stick_starts_where_it_did_and_fire_keeps_its_edge() -> void:
	_controls(0.8)
	var rest := TouchLayout.stick_rest(_fixture.controls.safe_rect(), 1.0)
	await _fixture.touch(0, rest)
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	await _fixture.drag(0, rest + Vector2(90.0, 0.0), Vector2(90.0, 0.0))
	(
		assert_float(Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back").x)
		. is_greater(0.6)
	)
	await _fixture.lift(0)
	# Fire's edge: 123 units from its centre presses, 125 does not (its area is not grown).
	var fire := _centre(TouchLayout.FIRE)
	assert_float(_hit(TouchLayout.FIRE)).is_equal(124.0)
	assert_object(await _press(fire + Vector2.DOWN * 123.0)).is_equal(TouchLayout.FIRE)
	assert_object(await _press(fire + Vector2.DOWN * 125.0)).is_equal(&"")
