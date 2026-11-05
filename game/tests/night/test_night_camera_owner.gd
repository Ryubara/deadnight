extends GdUnitTestSuite
## In a night with bots, the view is the person's own soldier, always (#702). Every body is the
## player scene, and its camera starts `current`, so a body that joined after the person's took the
## view: "my camera is stuck to one of the bots". Only the local person's body may own the current
## camera; a bot or a remote copy never does. Checked on the viewport's real current camera, after
## the spawn, after a bot is downed and raised, after the person is downed and raised, and after a
## bot joins late; once through the Play screen's own path (the settings, the night screen).

const MENU := "res://ui/screens/main_menu.tscn"
const NIGHT := "res://ui/screens/night_screen.tscn"
const BOTS := 3
const TICKS := 90


func before() -> void:
	# GdUnit minimizes the window after every suite and a minimized window draws no frame,
	# which the warm-up waits for (#1207).
	await WindowFixture.make_drawable(get_tree())


func after_test() -> void:
	await RouterFixture.clear(get_tree())


func _night_with_bots(count: int = BOTS) -> Night:
	var night := Night.new()
	night.match_settings = MatchSettings.new()
	night.match_settings.bots = count
	add_child(night)
	await night.start(Night.Mode.HUMAN, 7, RulesFixture.tuning())
	NightFixture.run(night, 2)
	return night


## Every body of the night that has a `Camera3D` that is current: what the viewport looks through.
func _owner_of_view(night: Night) -> int:
	var seen := night.get_viewport().get_camera_3d()
	for id: int in night.server._bodies:
		var body: Player = night.server.body_of(id)
		if body.camera_rig.camera() == seen:
			return id
	return 0


func _no_bot_owns_a_camera(night: Night) -> void:
	for id: int in night.server._bodies:
		if id == Night.PLAYER_ID:
			continue
		var camera: Camera3D = night.server.body_of(id).camera_rig.camera()
		assert_bool(camera.current).is_false()


func _assert_the_view_is_the_persons(night: Night) -> void:
	assert_int(_owner_of_view(night)).is_equal(Night.PLAYER_ID)
	assert_object(night.get_viewport().get_camera_3d()).is_same(night.player().camera_rig.camera())
	_no_bot_owns_a_camera(night)


func test_the_view_is_the_persons_after_three_bots_join() -> void:
	var night := await _night_with_bots()
	assert_int(night.bots.count()).is_equal(BOTS)
	_assert_the_view_is_the_persons(night)
	NightFixture.run(night, TICKS)
	_assert_the_view_is_the_persons(night)


func test_the_view_stays_after_a_bot_is_downed_and_raised() -> void:
	var night := await _night_with_bots()
	var bot := night.bots.seats()[0]
	night.server.rules.apply(RulesAction.set_downed(bot, true))
	NightFixture.run(night, TICKS)
	_assert_the_view_is_the_persons(night)
	night.server.rules.apply(RulesAction.set_downed(bot, false))
	NightFixture.run(night, TICKS)
	_assert_the_view_is_the_persons(night)


func test_the_view_stays_after_the_person_is_downed_and_raised() -> void:
	var night := await _night_with_bots()
	night.server.rules.apply(RulesAction.set_downed(Night.PLAYER_ID, true))
	NightFixture.run(night, TICKS)
	_assert_the_view_is_the_persons(night)
	night.server.rules.apply(RulesAction.set_downed(Night.PLAYER_ID, false))
	NightFixture.run(night, TICKS)
	_assert_the_view_is_the_persons(night)


func test_the_view_stays_when_a_bot_seat_is_freed_and_filled_again() -> void:
	var night := await _night_with_bots(2)
	var leaver := night.bots.seats()[0]
	night.bots.host.release(leaver)
	night.server.apply({"type": NightServer.LEAVE, "player_id": leaver})
	NightFixture.run(night, 2)
	_assert_the_view_is_the_persons(night)
	night.bots.fill(BOTS)
	NightFixture.run(night, TICKS)
	assert_int(night.bots.count()).is_equal(BOTS)
	_assert_the_view_is_the_persons(night)


func test_a_body_that_is_not_the_persons_has_no_current_camera() -> void:
	var night := await _night_with_bots(1)
	var bot: Player = night.server.body_of(night.bots.seats()[0])
	assert_bool(bot.local_input).is_false()
	assert_bool(bot.camera_rig.camera().current).is_false()
	assert_bool(night.player().camera_rig.camera().current).is_true()


func test_the_play_screen_path_with_three_bots_looks_through_the_person() -> void:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	var settings := MatchSettings.new()
	settings.bots = BOTS
	NightScreen.match_settings = settings
	UIRouter.push(NIGHT, UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	var night := screen.night
	assert_int(night.bots.count()).is_equal(BOTS)
	await get_tree().physics_frame
	_assert_the_view_is_the_persons(night)
	await NightFixture.settle_bake(night)
