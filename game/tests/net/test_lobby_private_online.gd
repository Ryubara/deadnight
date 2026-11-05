# The host's Private switch over the real backend (Deadnight #1186): the real `LobbyScreen` of the
# host and of a guest, each asking through a real `TogetherApi`, and the real backend
# (`spikes/backend`, run by Node on a free port). A night the game makes is listed; the host's press
# of the switch takes it out of `GET /lobbies` while its code still joins; the press back lists it
# again; the guest's screen follows on its next poll and cannot move the switch.
#
# It needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without them the
# suite is skipped with a line saying so.
extends GdUnitTestSuite

const SKIP := "needs node 24 and npm ci in spikes/backend"

var _backend := BackendFixture.new()
var _screens: Array[LobbyScreen] = []


func before_test() -> void:
	if BackendFixture.why_not() != "":
		return
	var up := await _backend.start(self)
	assert_bool(up).is_true()


func after_test() -> void:
	UIInputMode.touch = false
	for screen in _screens:
		if is_instance_valid(screen):
			screen.free()
	_screens.clear()
	_backend.stop()
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _guest(player_name: String) -> TogetherApi:
	var api := TogetherApi.new(self, _backend.url)
	api.isolated = true
	var signed := await api.sign_in(player_name)
	assert_bool(signed["ok"]).is_true()
	return api


## A real lobby screen for `lobby`, as `api`'s player sees it.
func _screen(api: TogetherApi, lobby: Dictionary) -> LobbyScreen:
	await RouterFixture.clear(get_tree())
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"api": api, "lobby": lobby}
	add_child(screen)
	_screens.append(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	for _i in 3:
		await get_tree().process_frame
	return screen


## Whether the night with `code` is in the list `api` reads.
func _listed(api: TogetherApi, code: String) -> bool:
	var listed := await api.list_nights()
	assert_bool(listed["ok"]).is_true()
	for row: Dictionary in listed["nights"]:
		if row["code"] == code:
			return true
	return false


func _press(screen: LobbyScreen) -> void:
	screen.private_switch.toggle.grab_focus()
	assert_bool(screen.private_switch.toggle.has_focus()).is_true()
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.physical_keycode = KEY_ENTER
		event.pressed = pressed
		get_viewport().push_input(event)
		await get_tree().process_frame
	# The press is sent at once; wait for its answer.
	var began := Time.get_ticks_msec()
	while screen.private_switch.sending() and Time.get_ticks_msec() - began < 15000:
		await get_tree().process_frame


func test_a_night_the_game_makes_is_listed_a_private_one_is_not_and_its_code_still_joins(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Host")
	var looker := await _guest("Looker")
	var made := await host.create_lobby()
	assert_bool(made["ok"]).is_true()
	var code := str(made["lobby"]["code"])
	# Off by default: the game asked for what `PUBLIC_BY_DEFAULT` says, and the backend listed it.
	assert_str(str(made["lobby"]["visibility"])).is_equal(
		TogetherApi.visibility_word(TogetherApi.PUBLIC_BY_DEFAULT)
	)
	var screen := await _screen(host, made["lobby"])
	assert_bool(screen.private_switch.is_private()).is_false()
	assert_bool(await _listed(looker, code)).is_true()
	# The host switches Private on: the backend takes it out of the list at once.
	await _press(screen)
	assert_bool(screen.private_switch.is_private()).is_true()
	assert_str(screen.note.text).is_equal(LobbyPrivateSwitch.SAID_ON)
	assert_bool(await _listed(looker, code)).is_false()
	# A friend with the code still gets in.
	var friend := await looker.join_code(code)
	assert_bool(friend["ok"]).is_true()
	assert_str(str(friend["lobby"]["visibility"])).is_equal("private")
	# And off again: listed.
	await _press(screen)
	assert_bool(screen.private_switch.is_private()).is_false()
	assert_bool(await _listed(looker, code)).is_true()


func test_a_guests_screen_follows_the_switch_and_cannot_move_it(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Host")
	var guest := await _guest("Bo")
	var made := await host.create_lobby()
	var joined := await guest.join_code(str(made["lobby"]["code"]))
	assert_bool(joined["ok"]).is_true()
	var host_screen := await _screen(host, made["lobby"])
	var guest_screen := await _screen(guest, joined["lobby"])
	# One focus in the window: the key goes to the host's switch.
	host_screen.private_switch.toggle.grab_focus()
	assert_bool(guest_screen.private_switch.editable).is_false()
	assert_bool(guest_screen.private_switch.is_private()).is_false()
	await _press(host_screen)
	# The guest reads it on their next poll, and is told.
	await guest_screen.watch.poll()
	assert_bool(guest_screen.private_switch.is_private()).is_true()
	assert_str(guest_screen.note.text).is_equal(
		"Host made the night private. Only the code gets in."
	)
	# The guest's switch is read only (every device is held off it: `test_lobby_private.gd`), and
	# the backend would refuse their change (below): the night is out of the list.
	assert_bool(guest_screen.private_switch.editable).is_false()
	var looker := await _guest("Looker")
	assert_bool(await _listed(looker, str(made["lobby"]["code"]))).is_false()
	# Back to public: the guest follows again.
	await _press(host_screen)
	await guest_screen.watch.poll()
	assert_bool(guest_screen.private_switch.is_private()).is_false()
	assert_str(guest_screen.note.text).is_equal(
		"Host made the night public. It is in the Server Browser."
	)
	assert_bool(await _listed(looker, str(made["lobby"]["code"]))).is_true()


func test_only_the_host_can_make_the_night_private_at_the_backend(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Host")
	var guest := await _guest("Bo")
	var made := await host.create_lobby()
	var joined := await guest.join_code(str(made["lobby"]["code"]))
	var refused := await guest.set_visibility(joined["lobby"], false)
	assert_bool(refused["ok"]).is_false()
	assert_str(str(refused["error"])).is_equal("not_host")
	assert_bool(await _listed(guest, str(made["lobby"]["code"]))).is_true()
