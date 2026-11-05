extends GdUnitTestSuite
## A drag that starts on a button scrolls the card it is in, and a tap still presses (#1257).
##
## The page is a phone's: 844 x 390 CSS px, a canvas of 1688 x 780 window pixels at the menu's
## phone factor (1169 x 540 units, 0.72 CSS px a unit). The fingers are real touch events through
## the `Input` singleton, in window pixels, as the browser's runtime sends them, so the engine makes
## the emulated mouse of them too: a test of the mouse buttons alone passed while a phone could not
## scroll from a button.

const PAGE := Vector2(844.0, 390.0)
const WINDOW := Vector2i(1688, 780)
const PHONE_FACTOR := 2.0
## The card: three buttons under a line of words, taller than the card's view.
const VIEW := Vector2(600.0, 300.0)
const WORDS_HEIGHT := 60.0
const BUTTON_HEIGHT := 120.0
## The frames a finger's journey is sent in.
const STEPS := 8

var _saved_size: Vector2i
var _saved_factor: float
var _scroll: ScrollContainer
var _buttons: Array[UIButton] = []
var _pressed: Array[int] = [0, 0, 0]


func before_test() -> void:
	UIInputMode.reset()
	PageSize.css_override = PAGE
	_saved_size = get_window().size
	_saved_factor = get_window().content_scale_factor
	get_window().size = WINDOW
	get_window().content_scale_factor = PHONE_FACTOR
	Input.emulate_mouse_from_touch = true


func after_test() -> void:
	PageSize.css_override = null
	if is_instance_valid(_scroll):
		_scroll.free()
	get_window().size = _saved_size
	get_window().content_scale_factor = _saved_factor
	UIInputMode.reset()
	_release_mouse()


## A card of `kind` (`UIScroll`, or the plain `ScrollContainer` the lobby and the shop build), with
## the words above three buttons.
func _card(kind: String) -> void:
	_scroll = UIScroll.new() if kind == "ui" else ScrollContainer.new()
	if kind == "plain":
		UIScroll.use_slip(_scroll)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = VIEW
	_scroll.size = VIEW
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var words := Label.new()
	words.text = "Words"
	words.custom_minimum_size.y = WORDS_HEIGHT
	column.add_child(words)
	_buttons.clear()
	_pressed = [0, 0, 0]
	for index in 3:
		var button := UIButton.new()
		button.text = "Button %d" % index
		button.custom_minimum_size.y = BUTTON_HEIGHT
		button.pressed.connect(func() -> void: _pressed[index] += 1)
		column.add_child(button)
		_buttons.append(button)
	_scroll.add_child(column)
	add_child(_scroll)
	_scroll.position = Vector2(100.0, 100.0)
	await get_tree().process_frame
	await get_tree().process_frame


## The slip a finger has, in units, at this page.
func _slip() -> float:
	return TouchSlop.units(get_window())


func _window_point(units: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * units


func _centre(button: Control) -> Vector2:
	return button.get_global_rect().get_center()


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame


func _touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = _window_point(at)
	event.pressed = pressed
	await _send(event)


func _move(from: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = _window_point(from + relative)
	event.relative = get_viewport().get_final_transform().basis_xform(relative)
	await _send(event)


## A finger down at `start`, moved by `travel` in `STEPS` equal steps and held there. Returns where
## it is.
func _finger_down_and_along(start: Vector2, travel: Vector2) -> Vector2:
	await _touch(start, true)
	var at := start
	for step in STEPS:
		await _move(at, travel / STEPS)
		at += travel / STEPS
	return at


func _lift(at: Vector2) -> void:
	await _touch(at, false)


func _release_mouse() -> void:
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if Input.is_mouse_button_pressed(button):
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = false
			Input.parse_input_event(event)
	Input.flush_buffered_events()


## What the card's own `gui_input` saw of the finger: the engine scrolls a card from the touch
## events that reach it, and only when the device is a touch screen (`DisplayServer`), which a
## headless run is not, so this is where the test stops and `tools/web_smoke/phone_drag.py` begins.
func _watch() -> Dictionary:
	var seen := {"touch": 0, "drag": 0, "mouse": 0}
	_scroll.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventScreenTouch:
				seen["touch"] += 1
			elif event is InputEventScreenDrag:
				seen["drag"] += 1
			elif event is InputEventMouseButton or event is InputEventMouseMotion:
				seen["mouse"] += 1
	)
	return seen


func test_a_drag_that_starts_on_a_button_reaches_the_card(
	kind: String, test_parameters := [["ui"], ["plain"]]  # gdlint: ignore=unused-argument
) -> void:
	await _card(kind)
	var seen := _watch()
	var end := await _finger_down_and_along(_centre(_buttons[0]), Vector2(0.0, -90.0))
	await _lift(end)
	# Both ends of the touch and every step of the drag, as when it starts on the words.
	assert_int(seen["touch"]).is_equal(2)
	assert_int(seen["drag"]).is_equal(STEPS)


func test_a_drag_that_starts_on_the_words_reaches_the_card_the_same_way() -> void:
	await _card("ui")
	var seen := _watch()
	var words := (_scroll.get_child(0) as Control).get_child(0) as Control
	var end := await _finger_down_and_along(_centre(words), Vector2(0.0, -90.0))
	await _lift(end)
	assert_int(seen["touch"]).is_equal(2)
	assert_int(seen["drag"]).is_equal(STEPS)


func test_a_button_that_stops_the_touch_leaves_the_card_nothing() -> void:
	# What every button did before: the same drag, the button's filter put back to stop.
	await _card("ui")
	_buttons[0].mouse_filter = Control.MOUSE_FILTER_STOP
	var seen := _watch()
	var end := await _finger_down_and_along(_centre(_buttons[0]), Vector2(0.0, -90.0))
	await _lift(end)
	assert_int(seen["touch"] + seen["drag"]).is_equal(0)


func test_a_tap_on_a_button_presses_it_once(
	kind: String, test_parameters := [["ui"], ["plain"]]  # gdlint: ignore=unused-argument
) -> void:
	await _card(kind)
	var at := _centre(_buttons[1])
	await _touch(at, true)
	var after_press := _scroll.scroll_vertical  # a `UIScroll` shows a focused button's ring
	await _touch(at, false)
	assert_array(_pressed).is_equal([0, 1, 0])
	assert_int(_scroll.scroll_vertical).is_equal(after_press)


func test_a_press_that_slips_under_the_slop_still_presses(
	kind: String, test_parameters := [["ui"], ["plain"]]  # gdlint: ignore=unused-argument
) -> void:
	await _card(kind)
	var start := _centre(_buttons[1])
	# Just under the slop, in small steps: a thumb that rolls.
	var slip := _slip() * 0.8
	await _touch(start, true)
	await _move(start, Vector2(0.0, slip * 0.5))
	await _move(start + Vector2(0.0, slip * 0.5), Vector2(0.0, slip * 0.5))
	assert_int(_scroll.scroll_deadzone).is_greater(int(slip))
	await _lift(start + Vector2(0.0, slip))
	assert_array(_pressed).is_equal([0, 1, 0])


func test_the_slop_is_ten_css_pixels_on_the_phone_page() -> void:
	# 1688 x 780 at the phone factor: 0.72 CSS px a unit, so 10 CSS px are 14 units.
	assert_float(TouchSlop.units(get_window())).is_between(13.5, 14.2)
	await _card("ui")
	await _touch(_centre(_buttons[0]), true)
	assert_int(_scroll.scroll_deadzone).is_equal(14)
	await _touch(_centre(_buttons[0]), false)


func test_a_drag_that_starts_off_the_buttons_scrolls_at_once() -> void:
	await _card("ui")
	var words := (_scroll.get_child(0) as Control).get_child(0) as Control
	await _touch(_centre(words), true)
	assert_int(_scroll.scroll_deadzone).is_equal(0)
	await _touch(_centre(words), false)
	# And after a press on a button the next touch off it is back to 0.
	await _touch(_centre(_buttons[0]), true)
	await _touch(_centre(_buttons[0]), false)
	await _touch(_centre(words), true)
	assert_int(_scroll.scroll_deadzone).is_equal(0)
	await _touch(_centre(words), false)


func test_the_slop_follows_the_scale_the_window_runs_at() -> void:
	# A night runs at the interface size alone: a unit is half the CSS px it is in the menu.
	get_window().content_scale_factor = 1.0
	assert_float(TouchSlop.units(get_window())).is_between(27.0, 28.5)
	# A desktop at the design size: one unit is one CSS pixel.
	PageSize.css_override = null
	get_window().size = Vector2i(1920, 1080)
	assert_float(TouchSlop.units(get_window())).is_equal_approx(10.0, 0.01)
	# A window too small to press anything does not ask for a slip wider than itself.
	get_window().size = Vector2i(64, 64)
	assert_float(TouchSlop.units(get_window())).is_less_equal(TouchSlop.MAX_UNITS)


func test_the_mouse_presses_a_button_in_a_scroll_as_before() -> void:
	Input.emulate_mouse_from_touch = false
	await _card("ui")
	var at := _window_point(_centre(_buttons[0]))
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		await _send(event)
	assert_array(_pressed).is_equal([1, 0, 0])


func test_a_mouse_drag_across_a_button_scrolls_nothing() -> void:
	Input.emulate_mouse_from_touch = false
	await _card("ui")
	var start := _window_point(_centre(_buttons[0]))
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = start
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	await _send(down)
	var after_press := _scroll.scroll_vertical
	for step in STEPS:
		var move := InputEventMouseMotion.new()
		move.position = start + Vector2(0.0, -12.0 * (step + 1))
		move.relative = Vector2(0.0, -12.0)
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		await _send(move)
	assert_int(_scroll.scroll_vertical).is_equal(after_press)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = start + Vector2(0.0, -12.0 * STEPS)
	await _send(up)


func test_the_wheel_over_a_button_scrolls_the_card() -> void:
	Input.emulate_mouse_from_touch = false
	await _card("ui")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.factor = 1.0
	event.position = _window_point(_centre(_buttons[0]))
	await _send(event)
	assert_int(_scroll.scroll_vertical).is_greater(0)


func test_a_controller_presses_the_focused_button() -> void:
	await _card("ui")
	_buttons[1].grab_focus()
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = &"ui_accept"
		event.pressed = pressed
		await _send(event)
	assert_array(_pressed).is_equal([0, 1, 0])


func test_every_button_the_menus_scroll_past_lets_a_drag_through() -> void:
	# The classes whose buttons sit in a scrolling card: none may stop the touch.
	var made: Array[Control] = [
		UIButton.new(),
		UICheckBox.new(),
		UIToggle.new(),
		MapCard.new(),
		NightRow.new(),
		ChallengeRow.new(),
		MenuItemButton.new(),
		PosterSetView.new(),
		WardrobeCell.new(),
	]
	for control in made:
		(
			assert_int(control.mouse_filter)
			. override_failure_message("%s stops a drag" % control.get_script().get_global_name())
			. is_equal(Control.MOUSE_FILTER_PASS)
		)
		control.free()


func test_every_scroll_area_the_game_builds_waits_for_the_slip() -> void:
	# A plain `ScrollContainer.new()` has a deadzone of 0: a button's press would be lost to a
	# hair of movement. Each one built in the game's own code asks for the slip.
	var bare: Array[String] = []
	for folder in ["res://ui", "res://addons/gds_ui/components"]:
		for path in _scripts_under(folder):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for index in lines.size():
				if lines[index].contains("ScrollContainer.new()"):
					var near := "\n".join(lines.slice(index, index + 3))
					if not near.contains("UIScroll.use_slip"):
						bare.append("%s:%d" % [path, index + 1])
	assert_array(bare).is_empty()


func _scripts_under(folder: String) -> Array[String]:
	var found: Array[String] = []
	for name in DirAccess.get_files_at(folder):
		if name.ends_with(".gd"):
			found.append(folder.path_join(name))
	for name in DirAccess.get_directories_at(folder):
		found.append_array(_scripts_under(folder.path_join(name)))
	return found
