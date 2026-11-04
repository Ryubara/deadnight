extends GdUnitTestSuite
## The end of a night played alone, through the real screens (docs/design/end-of-night.md): the
## Play screen starts the night with the player's rules; when the last player goes down the HUD
## gives way to the end board over the camera's flight, with every player's row and the server's
## seconds; at the end of the clock the player is back on the same Play screen with the rules as
## they left them (map, bots, intensity), and the way out pressed at once does the same.

const PLAY := "res://ui/screens/play_screen.tscn"
const SECONDS := 2.0


func after_test() -> void:
	await RouterFixture.clear(get_tree())
	NightScreen.match_settings = null
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _rules() -> MatchSettings:
	var chosen := MatchSettings.new()
	chosen.map = "small_indoor"
	chosen.bots = 2
	chosen.count_multiplier = 2.0
	chosen.break_seconds = 9.0
	return chosen.clamped()


## The Play screen with `_rules()` on its panel, the night started from it: the night screen.
func _night_from_play() -> Array:
	UIRouter.reset(PLAY, UITransition.Kind.CUT)
	await UIRouter.idle
	var play := UIRouter.top() as PlayScreen
	play.panel.set_settings(_rules())
	play.start()
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	screen.night.server.end_seconds = SECONDS
	return [play, screen]


## Everyone goes down; the loopback delivers it on the next tick, and the first frame with the
## server's seconds on the one after.
func _end(screen: NightScreen) -> void:
	var night := screen.night
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	for id: int in night.server.rules.players.keys():
		night.link.broadcast(night.server.rules.apply(RulesAction.set_downed(id, true)))
	NightFixture.run(night, 3)


func test_the_board_replaces_the_hud_and_the_clock_ends_on_the_play_screen_with_its_rules() -> void:
	var made := await _night_from_play()
	var play: PlayScreen = made[0]
	var screen: NightScreen = made[1]
	assert_str(screen.night.match_settings.map).is_equal("small_indoor")
	var board: HudEndBoard = screen.get_node("EndBoard")
	assert_bool(board.visible).is_false()
	assert_bool(screen._hud.visible).is_true()
	_end(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	# The HUD gives way; the board is up with the three seats and the server's seconds.
	assert_bool(screen._hud.visible).is_false()
	assert_bool(board.visible).is_true()
	assert_int(board.row_ids.size()).is_equal(3)
	assert_str(board.countdown_text).is_equal(str(int(SECONDS)))
	assert_str(board.leave_button.text).is_equal("Back")
	assert_object(screen.night.end_camera).is_not_null()
	assert_object(screen.get_viewport().get_camera_3d()).is_same(screen.night.end_camera)
	# The night is still ticked (by the engine) and the server's clock runs it out.
	var left := await _until(func() -> bool: return UIRouter.top() is PlayScreen, 20.0)
	assert_bool(left).is_true()
	# The same Play screen, with the rules as the player left them.
	assert_object(UIRouter.top()).is_same(play)
	var kept := play.panel.settings()
	assert_str(kept.map).is_equal("small_indoor")
	assert_int(kept.bots).is_equal(2)
	assert_float(kept.count_multiplier).is_equal(2.0)
	assert_float(kept.break_seconds).is_equal(9.0)


func test_the_way_out_pressed_at_once_goes_back_to_the_play_screen() -> void:
	var made := await _night_from_play()
	var play: PlayScreen = made[0]
	var screen: NightScreen = made[1]
	screen.night.server.end_seconds = 60.0
	_end(screen)
	await get_tree().process_frame
	var board: HudEndBoard = screen.get_node("EndBoard")
	board.leave_button.pressed.emit()
	var left := await _until(func() -> bool: return UIRouter.top() is PlayScreen, 20.0)
	assert_bool(left).is_true()
	assert_object(UIRouter.top()).is_same(play)
	assert_str(play.panel.settings().map).is_equal("small_indoor")


func _until(condition: Callable, seconds: float) -> bool:
	var began := Time.get_ticks_msec()
	while not condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().process_frame
	return true
