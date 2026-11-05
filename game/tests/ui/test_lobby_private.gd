# The Private switch in the host's lobby (Deadnight #1186): a night is public until its host
# switches it private; the host moves it with the keyboard, a gamepad or a finger, and every press
# is sent as it is made; a guest reads it, read only, on their next poll; a backend that says
# nothing of visibility gets no switch. The real backend half is `test_lobby_private_online.gd`.
extends GdUnitTestSuite


func before_test() -> void:
	LobbyScreen.opener = func() -> void: pass


func after_test() -> void:
	LobbyScreen.opener = Callable()
	Input.action_release(&"ui_accept")
	UIInputMode.touch = false


func _screen(api: LobbyFixture.FakeApi) -> LobbyScreen:
	await RouterFixture.clear(get_tree())
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"api": api, "lobby": api.lobby}
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	# Laid out: the containers size their children a frame or two after the screen is added.
	for _i in 3:
		await get_tree().process_frame
	return screen


func _hosted() -> LobbyFixture.FakeApi:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	return api


## Bo's view of Ann's lobby.
func _guest_api() -> LobbyFixture.FakeApi:
	var api := LobbyFixture.FakeApi.new(self)
	api.me = "b"
	api.lobby = LobbyFixture.lobby(
		[LobbyFixture.member("a", "Ann", 1, true), LobbyFixture.member("b", "Bo", 2)]
	)
	return api


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event)
		await get_tree().process_frame


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		get_viewport().push_input(event)
		await get_tree().process_frame


## A finger on `control`: the touch event and the emulated mouse press it becomes.
func _tap(control: Control) -> void:
	UIInputMode.touch = true
	var at := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = at
		touch.pressed = pressed
		get_viewport().push_input(touch)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		click.device = InputEvent.DEVICE_ID_EMULATION
		get_viewport().push_input(click, true)
		await get_tree().process_frame


func test_a_new_night_is_public_and_the_default_is_one_constant() -> void:
	# The constant is what new nights are made with and what the switch starts from.
	assert_bool(TogetherApi.PUBLIC_BY_DEFAULT).is_true()
	assert_str(TogetherApi.new_lobby_body()["visibility"]).is_equal(
		TogetherApi.visibility_word(TogetherApi.PUBLIC_BY_DEFAULT)
	)
	assert_int(int(TogetherApi.new_lobby_body()["maxPlayers"])).is_equal(NightHost.MAX_PLAYERS)
	var screen := await _screen(_hosted())
	assert_bool(screen.private_switch.row.visible).is_true()
	assert_bool(screen.private_switch.is_private()).is_equal(not TogetherApi.PUBLIC_BY_DEFAULT)
	assert_bool(screen.private_switch.is_private()).is_false()
	assert_str(screen.private_switch.row.hint).is_equal(LobbyPrivateSwitch.HINT_OFF)
	screen.free()


func test_the_hints_are_short_enough_for_the_rows_column() -> void:
	# The column trims what does not fit (the other rows' hints end in "..."): these two do not.
	for hint in [LobbyPrivateSwitch.HINT_ON, LobbyPrivateSwitch.HINT_OFF]:
		assert_int(hint.length()).is_less_equal(24)


func test_the_host_has_the_switch_and_it_can_be_reached_by_every_device() -> void:
	var screen := await _screen(_hosted())
	assert_bool(screen.private_switch.editable).is_true()
	assert_bool(screen.private_switch.toggle.focus_mode == Control.FOCUS_ALL).is_true()
	assert_bool(screen.private_switch.toggle.mouse_filter == Control.MOUSE_FILTER_STOP).is_true()
	# A finger's height: a tap target of the menu (62 units), not the control's 52.
	assert_float(screen.private_switch.toggle.size.y).is_greater_equal(MenuLook.TAP_TARGET - 0.5)
	assert_float(screen.private_switch.row.size.y).is_greater_equal(MenuLook.TAP_TARGET - 0.5)
	screen.free()


func test_the_keyboard_switches_it_private_and_back_and_each_press_is_sent() -> void:
	var api := _hosted()
	var screen := await _screen(api)
	screen.private_switch.toggle.grab_focus()
	await _key(KEY_ENTER)
	assert_bool(screen.private_switch.is_private()).is_true()
	assert_array(api.visibility_sent).is_equal(["private"])
	assert_str(screen.private_switch.row.hint).is_equal(LobbyPrivateSwitch.HINT_ON)
	assert_str(screen.note.text).is_equal(LobbyPrivateSwitch.SAID_ON)
	await _key(KEY_SPACE)
	assert_bool(screen.private_switch.is_private()).is_false()
	assert_array(api.visibility_sent).is_equal(["private", "public"])
	assert_str(screen.note.text).is_equal(LobbyPrivateSwitch.SAID_OFF)
	screen.free()


func test_a_gamepad_switches_it() -> void:
	var api := _hosted()
	var screen := await _screen(api)
	screen.private_switch.toggle.grab_focus()
	await _pad(JOY_BUTTON_A)
	assert_bool(screen.private_switch.is_private()).is_true()
	assert_array(api.visibility_sent).is_equal(["private"])
	screen.free()


func test_a_finger_switches_it() -> void:
	var api := _hosted()
	var screen := await _screen(api)
	await _tap(screen.private_switch.toggle)
	assert_bool(screen.private_switch.is_private()).is_true()
	assert_array(api.visibility_sent).is_equal(["private"])
	screen.free()


func test_a_guest_reads_it_and_cannot_move_it() -> void:
	var api := _guest_api()
	api.lobby["visibility"] = "private"
	var screen := await _screen(api)
	assert_bool(screen.private_switch.row.visible).is_true()
	assert_bool(screen.private_switch.is_private()).is_true()
	assert_bool(screen.private_switch.editable).is_false()
	assert_bool(screen.private_switch.toggle.focus_mode == Control.FOCUS_NONE).is_true()
	assert_bool(screen.private_switch.toggle.mouse_filter == Control.MOUSE_FILTER_IGNORE).is_true()
	await _tap(screen.private_switch.toggle)
	await _key(KEY_ENTER)
	assert_bool(screen.private_switch.is_private()).is_true()
	assert_array(api.visibility_sent).is_empty()
	screen.free()


func test_a_guest_sees_the_switch_move_on_the_next_poll_and_is_told() -> void:
	var api := _guest_api()
	var screen := await _screen(api)
	assert_bool(screen.private_switch.is_private()).is_false()
	var hosted := api.lobby.duplicate()
	hosted["visibility"] = "private"
	api.refreshed = hosted
	await screen.watch.poll()
	assert_bool(screen.private_switch.is_private()).is_true()
	assert_str(screen.private_switch.row.hint).is_equal(LobbyPrivateSwitch.HINT_ON)
	assert_str(screen.note.text).is_equal("Ann made the night private. Only the code gets in.")
	var listed := hosted.duplicate()
	listed["visibility"] = "public"
	api.refreshed = listed
	await screen.watch.poll()
	assert_bool(screen.private_switch.is_private()).is_false()
	assert_str(screen.note.text).is_equal("Ann made the night public. It is in the Server Browser.")
	screen.free()


func test_the_host_is_not_told_about_their_own_switch_by_the_poll() -> void:
	var before := _hosted().lobby
	var after := before.duplicate()
	after["visibility"] = "private"
	assert_array(LobbyWatch.diff(before, after, "a")).is_empty()
	var told := LobbyWatch.diff(before, after, "b")
	assert_int(told.size()).is_equal(1)
	assert_that(told[0]["kind"]).is_equal(&"visibility")
	assert_bool(told[0]["private"]).is_true()
	# A backend that says nothing of it tells nobody.
	var bare := before.duplicate()
	bare.erase("visibility")
	assert_array(LobbyWatch.diff(bare, after, "b")).is_empty()


func test_a_refusal_puts_the_switch_back_and_says_why() -> void:
	var api := _hosted()
	api.visibility_failure = "not_host"
	var screen := await _screen(api)
	await _tap(screen.private_switch.toggle)
	assert_bool(screen.private_switch.is_private()).is_false()
	assert_str(screen.private_switch.row.hint).is_equal(LobbyPrivateSwitch.HINT_OFF)
	assert_str(screen.note.text).is_equal(TogetherApi.TEXTS["not_host"])
	screen.free()


func test_two_quick_presses_go_in_order_and_the_last_wins() -> void:
	var api := _hosted()
	api.visibility_slow = true
	var screen := await _screen(api)
	screen.private_switch.toggle.button_pressed = true
	screen.private_switch.toggle.button_pressed = false
	for i in 6:
		await get_tree().process_frame
	assert_array(api.visibility_sent).is_equal(["private", "public"])
	assert_bool(screen.private_switch.is_private()).is_false()
	assert_str(str(screen.lobby["visibility"])).is_equal("public")
	screen.free()


func test_a_press_is_sent_before_start_even_when_it_is_still_on_its_way() -> void:
	var api := _hosted()
	api.visibility_slow = true
	api.started = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)], "started", 0)
	var screen := await _screen(api)
	screen.private_switch.toggle.button_pressed = true
	await screen.start()
	assert_array(api.calls).is_equal(["visibility private", "start"])
	screen.free()


func test_a_new_host_gets_the_switch_with_the_lobbys_value() -> void:
	var api := _guest_api()
	api.lobby["visibility"] = "private"
	var screen := await _screen(api)
	assert_bool(screen.private_switch.editable).is_false()
	# Ann left: Bo is the host now.
	var next := api.lobby.duplicate(true)
	next["hostId"] = "b"
	next["members"] = [LobbyFixture.member("b", "Bo", 1, true)]
	api.refreshed = next
	await screen.watch.poll()
	assert_bool(screen.private_switch.editable).is_true()
	assert_bool(screen.private_switch.is_private()).is_true()
	assert_bool(screen.private_switch.toggle.focus_mode == Control.FOCUS_ALL).is_true()
	screen.free()


func test_a_backend_that_says_nothing_of_visibility_gets_no_switch() -> void:
	var api := _hosted()
	api.lobby.erase("visibility")
	var screen := await _screen(api)
	assert_bool(screen.private_switch.row.visible).is_false()
	assert_bool(screen.private_switch.editable).is_false()
	screen.free()


func test_a_code_looked_at_has_no_switch() -> void:
	var api := _guest_api()
	await RouterFixture.clear(get_tree())
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {
		"api": api,
		"preview": {"code": "ABC234", "state": "open", "players": 1, "maxPlayers": 4, "full": false}
	}
	add_child(screen)
	await screen.screen_enter()
	assert_bool(screen.private_switch.row.visible).is_false()
	screen.free()


func test_the_row_fits_a_desktop_a_phone_and_the_phones_real_page() -> void:
	var run := UiFitRun.new(get_tree())
	run.begin()
	# A desktop; a phone held sideways at the menu's phone factor (a 1169 x 540 canvas); and the
	# phone's real page, 844 x 390 CSS px at a pixel ratio of 2 (a 1688 x 780 window).
	var problems: Array[String] = []
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(844, 390), Vector2i(1688, 780)]:
		await run.set_window(size, 1.0)
		await run.close()
		run._scale_window()
		for host in [true, false]:
			var api := _hosted() if host else _guest_api()
			UIRouter.reset(UiFitRun.LOBBY, UITransition.Kind.CUT, {"api": api, "lobby": api.lobby})
			await UIRouter.idle
			var lobby := UIRouter.top() as LobbyScreen
			lobby.watch.every = 3600.0
			await run.frames()
			assert_bool(lobby.private_switch.row.is_visible_in_tree()).is_true()
			# The row is a finger high, and in the scrolling area (what is below scrolls).
			assert_float(lobby.private_switch.row.size.y).is_greater_equal(
				MenuLook.TAP_TARGET - 0.5
			)
			problems.append_array(
				run.problems(run.screen_subject(lobby, "lobby %s %s" % [host, size]))
			)
	await run.close()
	run.restore()
	(
		assert_array(problems)
		. override_failure_message("%d fit problems:\n%s" % [problems.size(), "\n".join(problems)])
		. is_empty()
	)
