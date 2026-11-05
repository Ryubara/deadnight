extends GdUnitTestSuite
## A button goes back to its resting look once a finger has lifted from it and its press feedback
## has run (#1268). A lifting finger sends no mouse exit, so the engine kept the button lit
## (hovered) until the next touch. The page is a phone's (844 x 390 CSS px, 1688 x 780 window
## pixels at the menu's phone factor) and the fingers are real touch events through the `Input`
## singleton, the mouse the engine makes of them included. A tap in a card is in
## `test_button_scroll_drag.gd`; `tools/web_smoke/phone_drag.py` measures the look in the web
## export.

const PAGE := Vector2(844.0, 390.0)
const WINDOW := Vector2i(1688, 780)
const PHONE_FACTOR := 2.0

var _saved_size: Vector2i
var _saved_factor: float
var _host: Control
var _buttons: Array[UIButton] = []
var _pressed := 0


func before_test() -> void:
	UIInputMode.reset()
	PageSize.css_override = PAGE
	_saved_size = get_window().size
	_saved_factor = get_window().content_scale_factor
	get_window().size = WINDOW
	get_window().content_scale_factor = PHONE_FACTOR
	Input.emulate_mouse_from_touch = true
	_pressed = 0


func after_test() -> void:
	PageSize.css_override = null
	if is_instance_valid(_host):
		_host.free()
	get_window().size = _saved_size
	get_window().content_scale_factor = _saved_factor
	UIInputMode.reset()
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if Input.is_mouse_button_pressed(button):
			var event := InputEventMouseButton.new()
			event.button_index = button
			event.pressed = false
			Input.parse_input_event(event)
	Input.flush_buffered_events()


## Two buttons side by side in a plain host, under no scroll area (so each stops the pointer), or
## in a scroll area that takes the touch (so each passes it).
func _page(in_card := false) -> void:
	_host = Control.new()
	_host.size = Vector2(900.0, 400.0)
	var row := HBoxContainer.new()
	row.size = Vector2(900.0, 120.0)
	row.position = Vector2(50.0, 100.0)
	_buttons.clear()
	for index in 2:
		var button := UIButton.new()
		button.text = "Button %d" % index
		button.custom_minimum_size = Vector2(300.0, 100.0)
		button.pressed.connect(func() -> void: _pressed += 1)
		row.add_child(button)
		_buttons.append(button)
	if in_card:
		var scroll := UIScroll.new()
		scroll.size = _host.size
		scroll.add_child(row)
		_host.add_child(scroll)
	else:
		_host.add_child(row)
	add_child(_host)
	await get_tree().process_frame
	await get_tree().process_frame


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


func _tap(button: Control) -> void:
	await _touch(_centre(button), true)
	await _touch(_centre(button), false)


## The time a tap's press feedback needs and a little more, in time (a spring is read after it has
## run its course, not after a count of frames).
func _after_the_press_feedback() -> void:
	await get_tree().create_timer(UITouchRest.REST_DELAY_S + 0.15).timeout


func _mouse(button: BaseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = _window_point(_centre(button))
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	await _send(event)


func test_a_tap_on_a_button_outside_a_card_leaves_it_at_rest(
	in_card: bool, test_parameters := [[false], [true]]  # gdlint: ignore=unused-argument
) -> void:
	await _page(in_card)
	var button := _buttons[0]
	assert_int(button.mouse_filter).is_equal(
		Control.MOUSE_FILTER_PASS if in_card else Control.MOUSE_FILTER_STOP
	)
	await _tap(button)
	assert_bool(button.is_hovered()).is_true()
	await _after_the_press_feedback()
	assert_bool(button.is_hovered()).is_false()
	assert_int(_pressed).is_equal(1)
	# Its filter is what it was.
	assert_int(button.mouse_filter).is_equal(
		Control.MOUSE_FILTER_PASS if in_card else Control.MOUSE_FILTER_STOP
	)


func test_a_mouse_click_keeps_the_hover_as_before(
	in_card: bool, test_parameters := [[false], [true]]  # gdlint: ignore=unused-argument
) -> void:
	Input.emulate_mouse_from_touch = false
	await _page(in_card)
	var button := _buttons[0]
	await _mouse(button, true)
	await _mouse(button, false)
	await _after_the_press_feedback()
	assert_int(_pressed).is_equal(1)
	assert_bool(button.is_hovered()).is_true()


func test_a_mouse_that_moves_over_the_button_after_a_tap_keeps_the_hover() -> void:
	# A device that has a touch screen and a mouse: the last hand decides.
	await _page()
	var button := _buttons[0]
	await _tap(button)
	var move := InputEventMouseMotion.new()
	move.position = _window_point(_centre(button) + Vector2(3.0, 0.0))
	move.relative = Vector2(3.0, 0.0)
	await _send(move)
	await _after_the_press_feedback()
	assert_bool(button.is_hovered()).is_true()


func test_a_second_tap_before_the_rest_is_due_is_not_taken_from_under_the_finger() -> void:
	await _page()
	var button := _buttons[0]
	await _tap(button)
	await _touch(_centre(button), true)
	await _after_the_press_feedback()
	assert_bool(button.is_hovered()).is_true()
	await _touch(_centre(button), false)
	await _after_the_press_feedback()
	assert_bool(button.is_hovered()).is_false()
	assert_int(_pressed).is_equal(2)


func test_a_press_that_frees_its_own_button_leaves_nothing_to_rest() -> void:
	await _page()
	var button := _buttons[0]
	button.pressed.connect(button.queue_free)
	await _tap(button)
	await _after_the_press_feedback()
	assert_bool(is_instance_valid(button)).is_false()
	assert_int(_pressed).is_equal(1)


func test_a_press_that_takes_its_button_out_of_the_tree_leaves_nothing_to_rest() -> void:
	await _page()
	var button := _buttons[0]
	button.pressed.connect(func() -> void: button.get_parent().remove_child(button))
	await _tap(button)
	await _after_the_press_feedback()
	assert_bool(button.is_inside_tree()).is_false()
	assert_int(_pressed).is_equal(1)
	button.free()
