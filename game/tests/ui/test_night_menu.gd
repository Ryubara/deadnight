# The night's menu (#471): opened and closed by the keyboard, the pad and the touch layer's pause
# button, with Settings inside it. Played alone the night stands still behind it; played with others
# (a real game server over a loopback socket) it keeps running and only this player's controls are
# off. A setting changed in it applies at once and is saved, and Leave night returns to the main
# menu with nothing left behind.
#
# Every press is the engine's own input: a key, a pad button, a finger, a mouse button.
extends GdUnitTestSuite

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const SETTINGS_PATH := "user://night_menu_test.cfg"

var _host: NightHost
var _mode := Input.MOUSE_MODE_VISIBLE
var _quiet := ""
var _saved_path := ""
var _fixture: TouchFixture


func before_test() -> void:
	_mode = Input.MOUSE_MODE_VISIBLE
	_quiet = OS.get_environment("GDS_QUIET")
	OS.unset_environment("GDS_QUIET")
	_saved_path = Settings.path
	Settings.path = SETTINGS_PATH
	Settings.reset_defaults()
	await RouterFixture.clear(get_tree())


func after_test() -> void:
	if _quiet != "":
		OS.set_environment("GDS_QUIET", _quiet)
	if _fixture != null:
		_fixture.free_all()
		_fixture = null
	NightScreen.join_url = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.action_release(&"move_forward")
	await RouterFixture.clear(get_tree())
	if is_instance_valid(_host):
		_host.get_parent().queue_free()
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _platform_mode() -> Input.MouseMode:
	return _mode


func _platform_ask(mode: Input.MouseMode) -> void:
	_mode = mode


func _enter_night() -> NightScreen:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	var grip := screen.night.player().grip
	grip.reader = _platform_mode
	grip.writer = _platform_ask
	screen.night.player().set_controls_enabled(true)
	await _frames(2)
	return screen


## A night joined on a real game server over a loopback socket.
func _enter_online_night() -> NightScreen:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	_host = NightHost.new()
	_host.port = 0
	_host.log_enabled = false
	_host.seed_value = 7
	viewport.add_child(_host)
	assert_bool(await _until(func() -> bool: return _host.serving)).is_true()
	NightScreen.join_url = "ws://127.0.0.1:%d" % _host.listener.port()
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	assert_bool(await _until(func() -> bool: return screen.night.running)).is_true()
	var grip := screen.night.player().grip
	grip.reader = _platform_mode
	grip.writer = _platform_ask
	screen.night.player().set_controls_enabled(true)
	await _frames(2)
	return screen


## The router has finished what a click asked of it (its `idle` signal is only worth waiting for
## while it is busy).
func _settled() -> void:
	if UIRouter.busy:
		await UIRouter.idle
	await _frames(2)


func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().process_frame
	return true


## `process_frame` comes before the nodes' `_process`: a change is seen at the second one.
func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(2)


## A key pressed and let go, as the engine sends it.
func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		await _send(event)


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button
		event.pressed = pressed
		await _send(event)


## A mouse click on the middle of a control, in window pixels.
func _click(control: Control) -> void:
	var at := control.get_viewport().get_final_transform() * control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		await _send(event)


func _button(screen: NightScreen, text: String) -> UIButton:
	for candidate in screen.find_children("*", "UIButton", true, false):
		if (candidate as UIButton).text == text and (candidate as UIButton).is_visible_in_tree():
			return candidate
	return null


func _menu_open(screen: NightScreen) -> bool:
	return _button(screen, "Resume") != null


func _tick_of(screen: NightScreen) -> int:
	return int(screen.night.state.frame.get("tick", 0))


func test_escape_opens_and_closes_the_menu() -> void:
	var screen := await _enter_night()
	assert_bool(_menu_open(screen)).is_false()
	await _key(KEY_ESCAPE)
	assert_bool(_menu_open(screen)).is_true()
	assert_bool(screen.night.is_paused()).is_true()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	await _key(KEY_ESCAPE)
	assert_bool(_menu_open(screen)).is_false()
	assert_bool(screen.night.is_paused()).is_false()


func test_start_on_a_pad_opens_and_closes_the_menu() -> void:
	var screen := await _enter_night()
	await _pad(JOY_BUTTON_START)
	assert_bool(_menu_open(screen)).is_true()
	await _pad(JOY_BUTTON_START)
	assert_bool(_menu_open(screen)).is_false()


func test_the_touch_pause_button_opens_the_menu_and_a_tap_on_resume_closes_it() -> void:
	TouchMode.device_is_touch = true
	var screen := await _enter_night()
	var touch := screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	touch.refresh()
	_fixture = TouchFixture.attach(self, touch)
	assert_bool(screen.touch_active()).is_true()
	await _fixture.touch(0, _fixture.at(TouchLayout.PAUSE))
	await _fixture.lift(0)
	await _frames(2)
	assert_bool(_menu_open(screen)).is_true()
	assert_bool(screen.night.is_paused()).is_true()
	assert_bool(screen.touch_active()).is_false()
	var resume := _button(screen, "Resume")
	await _fixture.tap(resume.get_global_rect().get_center())
	await _frames(2)
	assert_bool(_menu_open(screen)).is_false()
	assert_bool(screen.night.is_paused()).is_false()
	assert_bool(screen.touch_active()).is_true()


func test_a_solo_night_stands_still_behind_the_menu() -> void:
	var screen := await _enter_night()
	await _key(KEY_ESCAPE)
	var tick := _tick_of(screen)
	assert_bool(screen.night.running).is_false()
	await _frames(20)
	assert_int(_tick_of(screen)).is_equal(tick)
	assert_str(_title(screen)).is_equal("Paused")


func test_a_night_with_others_goes_on_behind_the_menu_and_the_player_stands_still() -> void:
	var screen := await _enter_online_night()
	await _key(KEY_ESCAPE)
	assert_bool(_menu_open(screen)).is_true()
	assert_bool(screen.night.running).is_true()
	assert_str(_title(screen)).is_equal("Menu")
	var tick := _tick_of(screen)
	# The player holds forward: the key goes nowhere while the menu is open.
	Input.action_press(&"move_forward")
	var command := HumanController.new().command(screen.night.player(), Night.PLAYER_ID)
	assert_vector(command.motion.move).is_equal(Vector2.ZERO)
	assert_bool(screen.night.player().controls_enabled()).is_false()
	await _until(func() -> bool: return _tick_of(screen) > tick + 10)
	assert_int(_tick_of(screen)).is_greater(tick + 10)
	await _key(KEY_ESCAPE)
	assert_bool(_menu_open(screen)).is_false()
	assert_bool(screen.night.player().controls_enabled()).is_true()
	assert_bool(screen.night.running).is_true()


func test_resume_takes_the_mouse_back_after_a_visit_to_the_settings() -> void:
	var screen := await _enter_night()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_CAPTURED)
	await _key(KEY_ESCAPE)
	assert_int(_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	await _click(_button(screen, "Settings"))
	assert_bool(screen.settings_open()).is_true()
	assert_int(_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	await _click(_button(screen, "Back"))
	assert_bool(screen.settings_open()).is_false()
	await _click(_button(screen, "Resume"))
	assert_int(_mode).is_equal(Input.MOUSE_MODE_CAPTURED)
	assert_bool(screen.night.player().controls_enabled()).is_true()


func test_settings_open_in_the_menu_and_escape_goes_back_one_step() -> void:
	var screen := await _enter_night()
	await _key(KEY_ESCAPE)
	await _click(_button(screen, "Settings"))
	assert_bool(screen.settings_open()).is_true()
	assert_bool(_button(screen, "Resume") == null).is_true()
	assert_int(UIRouter.depth()).is_equal(2)
	await _key(KEY_ESCAPE)
	assert_bool(screen.settings_open()).is_false()
	assert_bool(_menu_open(screen)).is_true()
	assert_bool(screen.night.is_paused()).is_true()
	# B on a pad and Start do the same.
	await _click(_button(screen, "Settings"))
	await _pad(JOY_BUTTON_B)
	assert_bool(screen.settings_open()).is_false()
	assert_bool(_menu_open(screen)).is_true()
	await _click(_button(screen, "Settings"))
	await _pad(JOY_BUTTON_START)
	assert_bool(screen.settings_open()).is_false()
	assert_bool(screen.night.is_paused()).is_true()


func test_a_night_with_others_keeps_running_while_the_settings_are_open() -> void:
	var screen := await _enter_online_night()
	await _key(KEY_ESCAPE)
	await _click(_button(screen, "Settings"))
	assert_bool(screen.settings_open()).is_true()
	var tick := _tick_of(screen)
	assert_bool(await _until(func() -> bool: return _tick_of(screen) > tick + 10)).is_true()
	assert_bool(screen.night.running).is_true()


func test_a_setting_changed_in_the_menu_applies_at_once_and_is_saved() -> void:
	var screen := await _enter_night()
	var player := screen.night.player()
	var before := player.camera_rig.sensitivity
	var writes := Settings.write_count
	await _key(KEY_ESCAPE)
	await _click(_button(screen, "Settings"))
	var page := screen.find_children("*", "SettingsScreen", true, false)[0] as SettingsScreen
	page.select_tab(3, false)
	await _frames(2)
	var row := page._pages[3].get_child(0) as UIRow
	var slider := row.control as UISlider
	assert_str(row.title).is_equal("Mouse sensitivity")
	slider.grab_focus()
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	assert_float(Settings.get_value(SettingsService.MOUSE_SENSITIVITY)).is_greater(1.0)
	assert_float(player.camera_rig.sensitivity).is_greater(before)
	# The write follows the last change by a moment.
	assert_bool(await _until(func() -> bool: return Settings.write_count > writes, 3.0)).is_true()
	var file := ConfigFile.new()
	assert_int(file.load(SETTINGS_PATH)).is_equal(OK)
	assert_float(file.get_value("controls", "mouse_sensitivity")).is_greater(1.0)


func test_the_volume_and_the_touch_layout_change_in_the_menu_too() -> void:
	TouchMode.device_is_touch = true
	var screen := await _enter_night()
	var touch := screen.find_children("*", "TouchControls", true, false)[0] as TouchControls
	touch.refresh()
	_fixture = TouchFixture.attach(self, touch)
	var hud := screen.find_children("*", "Hud", true, false)[0] as Hud
	assert_bool(hud.mirrored).is_false()
	await _key(KEY_ESCAPE)
	await _click(_button(screen, "Settings"))
	var page := screen.find_children("*", "SettingsScreen", true, false)[0] as SettingsScreen
	page.select_tab(1, false)
	var volume := (page._pages[1].get_child(0) as UIRow).control as UISlider
	volume.grab_focus()
	await _key(KEY_LEFT)
	assert_int(Settings.get_value(SettingsService.VOLUME_MASTER)).is_less(100)
	page.select_tab(4, false)
	var hand: UIToggle = null
	for row in page._pages[4].get_children():
		if (row as UIRow).title == "Left-handed layout":
			hand = (row as UIRow).control
	hand.grab_focus()
	await _key(KEY_ENTER)
	assert_bool(Settings.get_value(SettingsService.LEFT_HANDED)).is_true()
	await _click(_button(screen, "Back"))
	await _click(_button(screen, "Resume"))
	await _frames(2)
	assert_bool(hud.mirrored).is_true()


func test_leave_night_returns_to_the_menu_and_leaves_nothing_behind() -> void:
	var screen := await _enter_night()
	var night := screen.night
	await _key(KEY_ESCAPE)
	await _click(_button(screen, "Settings"))
	await _click(_button(screen, "Back"))
	await _click(_button(screen, "Leave night"))
	await _settled()
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_int(UIRouter.depth()).is_equal(1)
	assert_bool(is_instance_valid(screen)).is_false()
	assert_bool(is_instance_valid(night)).is_false()
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)


func test_leaving_a_night_with_others_closes_the_link_and_the_server_loses_the_player() -> void:
	var screen := await _enter_online_night()
	var night := screen.night
	await _key(KEY_ESCAPE)
	await _click(_button(screen, "Leave night"))
	await _settled()
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_bool(is_instance_valid(night)).is_false()
	assert_bool(await _until(func() -> bool: return _host.peer_count() == 0)).is_true()


func _title(screen: NightScreen) -> String:
	for candidate in screen.find_children("*", "UILabel", true, false):
		var text := (candidate as UILabel).text
		if (candidate as UILabel).is_visible_in_tree() and text in ["Paused", "Menu"]:
			return text
	return ""
