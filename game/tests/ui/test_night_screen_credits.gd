extends GdUnitTestSuite
## The film credits through the real flow (Deadnight #1069): the Play screen starts a night, the
## player is paid and everyone goes down, and the end board's credits name every player once, with
## the title the night's own events earned and the XP the server told that seat: the Guest account's
## line is the report's total and the bots' lines have none.

const PLAY := "res://ui/screens/play_screen.tscn"
const SECONDS := 2.0


func before_test() -> void:
	PlayerLevel.use(10)
	TogetherApi.forget()


func after_test() -> void:
	TogetherApi.forget()
	NightScreen.profile_path = ""
	PlayerLevel.reset()
	await RouterFixture.clear(get_tree())
	NightScreen.match_settings = null
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _guest() -> void:
	TogetherApi._token = "guest-token"
	TogetherApi._user = {"id": "guest-1", "name": "Guest 1234"}
	NightScreen.profile_path = ChallengeFixture.save_path("credits_flow")
	ProfileSave.write(Profile.new(), [], 1, NightScreen.profile_path)


func _night_from_play(bots: int) -> NightScreen:
	var chosen := MatchSettings.new()
	chosen.map = "small_indoor"
	chosen.bots = bots
	chosen.count_multiplier = 2.0
	chosen.break_seconds = 9.0
	UIRouter.reset(PLAY, UITransition.Kind.CUT)
	await UIRouter.idle
	var play := UIRouter.top() as PlayScreen
	play.panel.set_settings(chosen.clamped())
	play.start()
	await UIRouter.idle
	var screen := UIRouter.top() as NightScreen
	await screen.night.ready_to_play
	screen.night.server.end_seconds = SECONDS
	return screen


func _play_and_end(screen: NightScreen) -> void:
	var night := screen.night
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	NightFixture.run(night, 3)
	night.link.broadcast(night.server.rules.apply(RulesAction.grant_points(Night.PLAYER_ID, 730)))
	NightFixture.run(night, 3)
	for id: int in night.server.rules.players.keys():
		night.link.broadcast(night.server.rules.apply(RulesAction.set_downed(id, true)))
	NightFixture.run(night, 3)


func test_a_night_of_four_credits_every_player_once_and_the_guests_xp_is_the_reports() -> void:
	_guest()
	var screen := await _night_from_play(3)
	_play_and_end(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var board: HudEndBoard = screen.get_node("EndBoard")
	var card := board.credits_card
	assert_bool(card.visible).is_true()
	assert_int(card.row_ids.size()).is_equal(4)
	var distinct := {}
	for id in card.row_ids:
		distinct[id] = true
	assert_int(distinct.size()).is_equal(4)
	# Everyone went down once, so the tie goes to the lowest seat: the local player.
	assert_array(card.rows_text[0].slice(0, 2)).is_equal(["STUNT DOUBLE", "MOST TIMES DOWN"])
	assert_int(card.row_ids[0]).is_equal(Night.PLAYER_ID)
	assert_str(card.rows_text[0][3]).is_equal(board.report_card.total_text)
	for i in range(1, 4):
		assert_str(card.rows_text[i][0]).is_equal("EXTRA")
		assert_str(card.rows_text[i][3]).is_equal("")


func test_a_night_with_no_account_has_credits_without_xp() -> void:
	var screen := await _night_from_play(1)
	_play_and_end(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var card: HudCredits = (screen.get_node("EndBoard") as HudEndBoard).credits_card
	assert_bool(card.visible).is_true()
	assert_int(card.row_ids.size()).is_equal(2)
	for cells: Array in card.rows_text:
		assert_str(cells[3]).is_equal("")
