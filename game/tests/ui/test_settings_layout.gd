extends GdUnitTestSuite
## The Settings screen keeps every tab's rows apart and the tab strip honest, however the player
## gets there: tabs switched in any order, at once or after the entrance has finished, at several
## window sizes and interface scales (a maintainer saw a whole tab drawn on one line).

const SCREEN := "res://ui/screens/settings_screen.tscn"
const TEST_PATH := "user://settings_layout_test.cfg"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(960, 540)]
const SCALES: Array[float] = [0.8, 1.0, 1.25]
## Physics steps per second: the project's 60, and 1 so that most frames have no step at all.
const TICK_RATES: Array[int] = [1, 60]
## Longer than the rise of the last row of the longest page: the entrance has finished by then.
const SETTLE_SECONDS := 0.8
## The settle runs at this clock speed: the entrance is finished in a tenth of the wall time. Only
## the settle is sped up; the clicks and the frames between them, where a page is caught mid-way,
## run at the real pace.
const SETTLE_TIME_SCALE := 10.0

var _screen: SettingsScreen
var _saved_path: String
var _saved_size: Vector2i
var _saved_ticks := 60


func before_test() -> void:
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	var window := get_tree().root
	_saved_size = window.size
	_saved_ticks = Engine.physics_ticks_per_second
	# A headless window is 64 x 64 and a click outside it reaches nothing.
	window.size = SIZES[0]


func after_test() -> void:
	# The router is an autoload shared by every suite: leave it holding nothing.
	await RouterFixture.clear(get_tree())
	var window := get_tree().root
	window.size = _saved_size
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.time_scale = 1.0
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


## Opening each tab for the first time, by a click: the page has never been laid out before.
func test_every_tab_is_laid_out_the_first_time_it_is_clicked() -> void:
	for ticks in TICK_RATES:
		_set_physics_rate(ticks)
		await _recreate_screen()
		await _settle()
		for tab in _screen._pages.size():
			await _click_tab(tab)
			await _settle()
			_assert_page_is_clean("%d physics ticks/s, first visit to tab %d" % [ticks, tab])


## Every ordered pair of tabs, the second clicked while the first one's entrance is still running.
func test_switching_from_any_tab_to_any_tab_mid_transition() -> void:
	var count := 5
	for ticks in TICK_RATES:
		_set_physics_rate(ticks)
		await _recreate_screen()
		await _settle()
		for from in count:
			for to in count:
				if from == to:
					continue
				await _click_tab(from)
				await _frames(1)
				await _click_tab(to)
				await _frames(2)
				_assert_order("%d ticks/s, %d to %d, mid-transition" % [ticks, from, to])
				await _settle()
				_assert_page_is_clean("%d ticks/s, %d to %d, settled" % [ticks, from, to])


## Shuffled visiting orders (seeded), a click a frame apart, and then the tab the player rests on.
func test_shuffled_tab_orders_fast() -> void:
	_set_physics_rate(1)
	await _recreate_screen()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1958
	for round in 12:
		var order := range(5)
		order.shuffle()
		for tab: int in order:
			await _click_tab(tab)
			await _frames(rng.randi_range(1, 3))
		await _settle()
		_assert_page_is_clean("shuffled order %s" % [order])


## Keyboard and shoulder buttons go the same way: an input event, then the entrance.
func test_paging_with_the_keys_lays_every_tab_out() -> void:
	_set_physics_rate(1)
	await _recreate_screen()
	await _settle()
	for action: StringName in [&"ui_tab_next", &"ui_tab_prev"]:
		for i in 4:
			_send_action(action)
			await _frames(2)
			await _settle()
			_assert_page_is_clean("%s, tab %d" % [action, _screen._current])


func test_every_window_size_and_interface_scale() -> void:
	_set_physics_rate(1)
	await _recreate_screen()
	for size in SIZES:
		for scale in SCALES:
			get_tree().root.size = size
			Settings.set_value(SettingsService.UI_SCALE, scale)
			await _frames(3)
			for tab in _screen._pages.size():
				await _click_tab(tab)
				await _frames(3)
				_assert_order("%s x%s tab %d, mid-transition" % [size, scale, tab])
				await _settle()
				_assert_page_is_clean("%s x%s tab %d" % [size, scale, tab])
	Settings.set_value(SettingsService.UI_SCALE, 1.0)


func test_tab_buttons_show_one_selection_while_switching() -> void:
	_set_physics_rate(1)
	await _recreate_screen()
	await _settle()
	for tab in [1, 4, 2, 0, 3, 4, 4, 1]:
		await _click_tab(tab)
		await _frames(1)
		_assert_one_selected_tab("after tab %d" % tab)
	await _settle()
	_assert_one_selected_tab("settled")


## The pointer sweeps across the strip to the last tab and clicks it: only that tab may be lit or
## focused afterwards (the maintainer's capture showed two others still drawn as hovered).
func test_a_pointer_sweep_leaves_only_the_clicked_tab_lit() -> void:
	_set_physics_rate(60)
	await _recreate_screen()
	await _settle()
	for tab in range(0, 5):
		_move_pointer_to(_screen._tab_buttons[tab])
		await _frames(1)
	await _click_tab(4)
	await _settle()
	for i in 4:
		var button: UIButton = _screen._tab_buttons[i]
		for spring: UISpring in [button._hover, button._press, button._focus]:
			(
				assert_float(spring.value)
				. override_failure_message("tab button %d is still lit: %s" % [i, spring.value])
				. is_less(0.02)
			)
		assert_bool(button.has_focus()).is_false()
	assert_object(_screen.get_viewport().gui_get_focus_owner()).is_same(_screen._tab_buttons[4])


## Scale changes while a page is rising must not leave rows where they were.
func test_a_scale_change_during_an_entrance_still_lays_the_page_out() -> void:
	_set_physics_rate(1)
	await _recreate_screen()
	await _settle()
	await _click_tab(4)
	await _frames(2)
	Settings.set_value(SettingsService.UI_SCALE, 1.25)
	await _frames(2)
	Settings.set_value(SettingsService.UI_SCALE, 0.8)
	await _settle()
	_assert_page_is_clean("scale change mid-entrance")
	Settings.set_value(SettingsService.UI_SCALE, 1.0)


## A click is what a player does: the pointer moves onto the tab, goes down and comes up. The events
## are queued like the OS's and reach the screen at the start of the next frame, before the engine's
## own physics step and frame, which is the order that matters here.
func _click_tab(index: int) -> void:
	var button: Control = _screen._tab_buttons[index]
	var at := _window_point(button)
	_move_pointer_to(button)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)
	await get_tree().process_frame
	(
		assert_int(_screen._current)
		. override_failure_message(
			(
				"the click on tab %d did not select it (hovered %s, window %s, scale %s, mouse mode %s)"
				% [
					index,
					button.get_viewport().gui_get_hovered_control(),
					get_tree().root.size,
					button.get_viewport().get_final_transform(),
					Input.mouse_mode
				]
			)
		)
		. is_equal(index)
	)


## Where the middle of `control` is in window pixels: the stretch mode scales the window to the
## 1920 x 1080 canvas, and input events come in window pixels.
func _window_point(control: Control) -> Vector2:
	var canvas_point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	return control.get_viewport().get_final_transform() * canvas_point


func _move_pointer_to(button: Control) -> void:
	var at := _window_point(button)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)


func _send_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


## A frame has a physics step in it only when enough time has passed, so on a fast display about
## every other frame has none. The step flushes the engine's queued layout work; a low rate makes
## the frames without one the common case, and 60 is the project's own.
func _set_physics_rate(ticks: int) -> void:
	Engine.physics_ticks_per_second = ticks


## The screen as the game shows it: on the router's stage, above whatever an earlier suite left on
## the stack (a leftover main menu there takes every click aimed at a screen added anywhere else).
func _recreate_screen() -> void:
	await RouterFixture.clear(get_tree())
	UIRouter.reset(SCREEN, UITransition.Kind.CUT)
	await UIRouter.idle
	_screen = UIRouter.top() as SettingsScreen
	await _frames(2)


func _settle() -> void:
	Engine.time_scale = SETTLE_TIME_SCALE
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	Engine.time_scale = 1.0
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## The rows of the page being shown, top to bottom, none over another and all inside the panel's
## scroll area (a row below its bottom is allowed when the area scrolls: #980).
func _assert_page_is_clean(what: String) -> void:
	_assert_order(what)
	_assert_one_selected_tab(what)
	var page: VBoxContainer = _screen._pages[_screen._current]
	var scroll := page.get_parent().get_parent() as ScrollContainer
	var inside := scroll.get_global_rect().grow(1.0)
	var bar := scroll.get_v_scroll_bar()
	var scrolls := bar.max_value > bar.page + 1.0
	var rows := _visible_rows(page)
	for i in rows.size():
		var rect := rows[i].get_global_rect()
		var held := (
			inside.encloses(rect)
			or (
				scrolls
				and rect.position.x >= inside.position.x
				and rect.end.x <= inside.end.x
				and rect.position.y >= inside.position.y
			)
		)
		(
			assert_bool(held)
			. override_failure_message(
				(
					"%s: row %d (%s) %s is outside the panel %s"
					% [what, i, rows[i].title, rect, inside]
				)
			)
			. is_true()
		)
		(
			assert_float(rows[i].modulate.a)
			. override_failure_message("%s: row %d is not fully shown" % [what, i])
			. is_equal(1.0)
		)
		for j in range(i + 1, rows.size()):
			var other := rows[j].get_global_rect()
			(
				assert_bool(rect.grow(-1.0).intersects(other.grow(-1.0)))
				. override_failure_message(
					(
						"%s: rows %d (%s) %s and %d (%s) %s overlap"
						% [what, i, rows[i].title, rect, j, rows[j].title, other]
					)
				)
				. is_false()
			)


## Rows keep their order from the top, even while they are still rising.
func _assert_order(what: String) -> void:
	var rows := _visible_rows(_screen._pages[_screen._current])
	for i in range(1, rows.size()):
		(
			assert_float(rows[i].get_global_rect().position.y)
			. override_failure_message(
				(
					"%s: row %d (%s) is not below row %d (%s): %s, %s"
					% [
						what,
						i,
						rows[i].title,
						i - 1,
						rows[i - 1].title,
						rows[i].get_global_rect(),
						rows[i - 1].get_global_rect()
					]
				)
			)
			. is_greater(rows[i - 1].get_global_rect().position.y)
		)


func _assert_one_selected_tab(what: String) -> void:
	var primary := 0
	for i in _screen._tab_buttons.size():
		var button: UIButton = _screen._tab_buttons[i]
		var selected := button.variant == UIButton.Variant.PRIMARY
		primary += 1 if selected else 0
		(
			assert_bool(selected)
			. override_failure_message("%s: tab button %d selected is %s" % [what, i, selected])
			. is_equal(i == _screen._current)
		)
	(
		assert_int(primary)
		. override_failure_message("%s: %d tabs look selected" % [what, primary])
		. is_equal(1)
	)


func _visible_rows(page: Control) -> Array[UIRow]:
	var rows: Array[UIRow] = []
	for child in page.get_children():
		if child.visible:
			rows.append(child as UIRow)
	return rows
