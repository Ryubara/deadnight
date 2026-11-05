extends GdUnitTestSuite
## A button that hands a drag to the scroll area behind it does it only inside one (#1257).
##
## A button that passes the pointer (`MOUSE_FILTER_PASS`) with nothing above it that stops it lets
## the press go on to `_unhandled_input`: on the end board, where every ancestor ignores the
## pointer, a click on Leave would have reached the player, whose click takes the pointer lock.
## So a button passes only while a scroll area is above it. The events are the real ones through
## the `Input` singleton, a mouse click and a touch tap (with the mouse the engine makes of it).

const WINDOW := Vector2i(1280, 720)
const BUTTON := Vector2(240.0, 80.0)
const CLASSES: Array[String] = [
	"UIButton",
	"UICheckBox",
	"UIToggle",
	"MapCard",
	"NightRow",
	"ChallengeRow",
	"MenuItemButton",
	"PosterSetView",
	"WardrobeCell",
]

const SETTINGS_PATH := "user://button_outside_scroll_test.cfg"

var _saved_settings_path: String
var _saved_size: Vector2i
var _saved_factor: float
var _spy: Node
var _host: Control


## Records what reaches `_unhandled_input`, where a click that nothing took goes on to the player.
class Spy:
	extends Node
	var seen: Array[String] = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			seen.append("mouse %s" % ("down" if event.pressed else "up"))
		elif event is InputEventScreenTouch:
			seen.append("touch %s" % ("down" if event.pressed else "up"))


func before_test() -> void:
	UIInputMode.reset()
	_saved_settings_path = Settings.path
	Settings.path = SETTINGS_PATH
	_saved_size = get_window().size
	_saved_factor = get_window().content_scale_factor
	get_window().size = WINDOW
	get_window().content_scale_factor = 1.0
	_spy = Spy.new()
	add_child(_spy)
	# Like the end board: a host that ignores the pointer.
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.size = Vector2(WINDOW)
	add_child(_host)


func after_test() -> void:
	Settings.path = _saved_settings_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	_host.free()
	_spy.free()
	get_window().size = _saved_size
	get_window().content_scale_factor = _saved_factor
	Input.emulate_mouse_from_touch = true
	UIInputMode.reset()


func _unhandled() -> Array[String]:
	return (_spy as Spy).seen


func _make(class_id: String) -> BaseButton:
	var button: BaseButton
	match class_id:
		"UIButton":
			button = UIButton.new()
		"UICheckBox":
			button = UICheckBox.new()
		"UIToggle":
			button = UIToggle.new()
		"MapCard":
			button = MapCard.new()
		"NightRow":
			button = NightRow.new()
		"ChallengeRow":
			button = ChallengeRow.new()
		"MenuItemButton":
			button = MenuItemButton.new()
		"PosterSetView":
			button = PosterSetView.new()
		_:
			button = WardrobeCell.new()
	button.custom_minimum_size = BUTTON
	return button


## A button of `class_id` at (100, 100) of the host, alone or in a scroll area (`in_scroll`).
func _place(class_id: String, in_scroll: bool) -> BaseButton:
	var button := _make(class_id)
	if in_scroll:
		var scroll := ScrollContainer.new()
		UIScroll.take_touch(scroll)
		scroll.position = Vector2(100.0, 100.0)
		scroll.size = Vector2(400.0, 300.0)
		scroll.add_child(button)
		_host.add_child(scroll)
	else:
		button.position = Vector2(100.0, 100.0)
		_host.add_child(button)
	await get_tree().process_frame
	await get_tree().process_frame
	button.size = BUTTON
	return button


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame


func _click(units: Vector2) -> void:
	var at := get_viewport().get_final_transform() * units
	Input.emulate_mouse_from_touch = false
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _send(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		await _send(event)


func _tap(units: Vector2) -> void:
	var at := get_viewport().get_final_transform() * units
	Input.emulate_mouse_from_touch = true
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = at
		event.pressed = pressed
		await _send(event)


func _count_presses(button: BaseButton) -> Array[int]:
	var count: Array[int] = [0]
	button.pressed.connect(func() -> void: count[0] += 1)
	return count


func _in_stopping_scroll(node: Node) -> bool:
	var up := node.get_parent()
	while up != null:
		if (
			up is ScrollContainer
			and (up as ScrollContainer).mouse_filter == Control.MOUSE_FILTER_STOP
		):
			return true
		up = up.get_parent()
	return false


func test_a_button_outside_a_scroll_area_stops_the_pointer() -> void:
	for class_id in CLASSES:
		var button := await _place(class_id, false)
		(
			assert_int(button.mouse_filter)
			. override_failure_message("%s passes the pointer outside a card" % class_id)
			. is_equal(Control.MOUSE_FILTER_STOP)
		)
		button.free()


func test_a_button_inside_a_scroll_area_passes_the_pointer() -> void:
	for class_id in CLASSES:
		var button := await _place(class_id, true)
		(
			assert_int(button.mouse_filter)
			. override_failure_message("%s stops the pointer in a card" % class_id)
			. is_equal(Control.MOUSE_FILTER_PASS)
		)
		button.get_parent().free()


func test_a_click_on_a_button_with_no_scroll_area_presses_once_and_leaks_nothing() -> void:
	for class_id in CLASSES:
		var button := await _place(class_id, false)
		var presses := _count_presses(button)
		_unhandled().clear()
		await _click(button.get_global_rect().get_center())
		(
			assert_int(presses[0])
			. override_failure_message("%s: %d presses of a click" % [class_id, presses[0]])
			. is_equal(1)
		)
		(
			assert_array(_unhandled())
			. override_failure_message("%s: a click went on to _unhandled_input" % class_id)
			. is_empty()
		)
		button.free()


func test_a_tap_on_a_button_with_no_scroll_area_presses_once_and_leaks_nothing() -> void:
	for class_id in CLASSES:
		var button := await _place(class_id, false)
		var presses := _count_presses(button)
		_unhandled().clear()
		await _tap(button.get_global_rect().get_center())
		(
			assert_int(presses[0])
			. override_failure_message("%s: %d presses of a tap" % [class_id, presses[0]])
			. is_equal(1)
		)
		(
			assert_array(_unhandled())
			. override_failure_message("%s: a tap went on to _unhandled_input" % class_id)
			. is_empty()
		)
		button.free()


func test_a_click_and_a_tap_in_a_scroll_area_press_once_and_leak_nothing() -> void:
	for class_id in CLASSES:
		var button := await _place(class_id, true)
		var presses := _count_presses(button)
		_unhandled().clear()
		await _click(button.get_global_rect().get_center())
		await _tap(button.get_global_rect().get_center())
		(
			assert_int(presses[0])
			. override_failure_message(
				"%s: %d presses of a click and a tap" % [class_id, presses[0]]
			)
			. is_equal(2)
		)
		(
			assert_array(_unhandled())
			. override_failure_message("%s in a card: %s" % [class_id, _unhandled()])
			. is_empty()
		)
		button.get_parent().free()


func test_a_button_follows_the_scroll_area_it_is_moved_into_and_out_of() -> void:
	var button := await _place("UIButton", false)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	var scroll := ScrollContainer.new()
	UIScroll.take_touch(scroll)
	_host.add_child(scroll)
	button.reparent(scroll)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	button.reparent(_host)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	# A whole branch moved into a card, and a card taken out of the tree and put back.
	var column := VBoxContainer.new()
	button.reparent(column)
	scroll.add_child(column)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	_host.remove_child(scroll)
	_host.add_child(scroll)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	column.reparent(_host)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	scroll.free()


func test_a_button_built_before_it_enters_the_tree_is_decided_on_entering() -> void:
	var scroll := ScrollContainer.new()
	UIScroll.take_touch(scroll)
	var column := VBoxContainer.new()
	var button := UIButton.new()
	column.add_child(button)
	scroll.add_child(column)
	# Nothing is in a tree yet: the engine's own default until it enters one.
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_host.add_child(scroll)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	scroll.free()


func test_a_button_that_only_draws_stays_ignored() -> void:
	var button := UIButton.new()
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scroll := ScrollContainer.new()
	UIScroll.take_touch(scroll)
	scroll.add_child(button)
	_host.add_child(scroll)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	scroll.free()


func test_a_scroll_area_that_ignores_the_pointer_does_not_open_the_pass() -> void:
	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var button := UIButton.new()
	scroll.add_child(button)
	_host.add_child(scroll)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	scroll.free()


func test_a_plain_scroll_area_passes_the_pointer_on_so_a_button_in_it_keeps_stopping_it() -> void:
	# The engine's own `ScrollContainer` passes the pointer on: a button that passed it too would
	# leak the press. Only an area that took the touch (`UIScroll.take_touch`) is handed a drag.
	var scroll := ScrollContainer.new()
	assert_int(scroll.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	var button := UIButton.new()
	scroll.add_child(button)
	_host.add_child(scroll)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	UIScroll.take_touch(scroll)
	assert_int(scroll.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	button.reparent(_host)
	button.reparent(scroll)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	scroll.free()


func test_a_ui_scroll_takes_the_touch_itself() -> void:
	var scroll := UIScroll.new()
	assert_int(scroll.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	var button := UIButton.new()
	scroll.add_child(button)
	_host.add_child(scroll)
	assert_int(button.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	scroll.free()


func _end_board() -> HudEndBoard:
	var state := HudState.new()
	state.local_player_id = 1
	state.set_player_name(1, "Ruby")
	state.set_player_stats(1, 10, 1, HudState.NO_PING, 0)
	state.set_player_tally(1, 2, 5)
	state.round_number = 3
	var board := HudEndBoard.new()
	_host.add_child(board)
	board.show_results(state, "BACK IN", "Leave")
	return board


func test_the_end_boards_leave_takes_a_click_and_a_tap_and_nothing_goes_on_to_the_player() -> void:
	var board := _end_board()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var leaves := [0]
	board.leave_pressed.connect(func() -> void: leaves[0] += 1)
	assert_int(board.leave_button.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	var at := board.leave_button.get_global_rect().get_center()
	_unhandled().clear()
	await _click(at)
	assert_int(leaves[0]).is_equal(1)
	assert_array(_unhandled()).is_empty()
	await _tap(at)
	assert_int(leaves[0]).is_equal(2)
	assert_array(_unhandled()).is_empty()


## Every button of what `root` built keeps the rule: stop the pointer, or pass it inside a scroll
## area that stops it (a button that is only drawn ignores it).
func _check_rule(root: Node, label: String) -> int:
	var found := 0
	for node in root.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		found += 1
		var want := (
			Control.MOUSE_FILTER_PASS if _in_stopping_scroll(button) else Control.MOUSE_FILTER_STOP
		)
		(
			assert_int(button.mouse_filter)
			. override_failure_message(
				(
					"%s: %s (%s) has the filter %d, wanted %d"
					% [label, button.name, button.get_class(), button.mouse_filter, want]
				)
			)
			. is_equal(want)
		)
	return found


func test_every_button_the_end_board_and_the_screens_build_follows_the_rule() -> void:
	var board := _end_board()
	await get_tree().process_frame
	assert_int(_check_rule(board, "end board")).is_greater(0)
	for path in [
		"res://ui/screens/customize_screen.tscn",
		"res://ui/screens/settings_screen.tscn",
		"res://ui/screens/credits_screen.tscn",
	]:
		var screen := (load(path) as PackedScene).instantiate() as Control
		if screen is CustomizeScreen:
			(screen as CustomizeScreen).params = {
				"unlocks": LookUnlocks.at_level(LevelCurve.MAX_LEVEL)
			}
		var layer := CanvasLayer.new()
		layer.layer = 100
		_host.add_child(layer)
		layer.add_child(screen)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_int(_check_rule(layer, path)).is_greater(0)
		layer.free()
