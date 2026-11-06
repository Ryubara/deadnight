extends GdUnitTestSuite
## The night report through the real flow (Deadnight #1068): the Play screen starts a solo night,
## the player earns XP in it (the local rules tell the same `xp_gained` events a game server would),
## everyone goes down and the end board shows the card. For an account, a Guest account included,
## the card is the XP the night's own `XpAward` tallied and its lines add up to it; for a night with
## no account at all it shows what the night would have paid and says nothing was saved.

const PLAY := "res://ui/screens/play_screen.tscn"
const SECONDS := 2.0
const START_XP := 80

var _arrival := true


func before_test() -> void:
	# A window plays the drop that opens a night and a headless run has none (`--noarrival`); this
	# suite is about the night after it (#1348), so the drop is off as in CI.
	_arrival = NightScreen.arrival_enabled
	NightScreen.arrival_enabled = false
	PlayerLevel.use(10)
	TogetherApi.forget()


func after_test() -> void:
	NightScreen.arrival_enabled = _arrival
	TogetherApi.forget()
	NightScreen.profile_path = ""
	PlayerLevel.reset()
	await RouterFixture.clear(get_tree())
	NightScreen.match_settings = null
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


## A Guest account with `START_XP` on file: signed in, which is all the profile asks.
func _guest() -> void:
	TogetherApi._token = "guest-token"
	TogetherApi._user = {"id": "guest-1", "name": "Guest 1234"}
	var profile := Profile.new()
	profile.xp = START_XP
	NightScreen.profile_path = ChallengeFixture.save_path("report_flow")
	ProfileSave.write(profile, [], 1, NightScreen.profile_path)


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


## A round starts, the player is paid points, and everyone goes down.
func _play_and_end(screen: NightScreen) -> void:
	var night := screen.night
	night.link.broadcast(night.server.rules.apply(RulesAction.skip_break()))
	NightFixture.run(night, 3)
	night.link.broadcast(night.server.rules.apply(RulesAction.grant_points(Night.PLAYER_ID, 730)))
	NightFixture.run(night, 3)
	for id: int in night.server.rules.players.keys():
		night.link.broadcast(night.server.rules.apply(RulesAction.set_downed(id, true)))
	NightFixture.run(night, 3)


func _sum_of(card: HudNightReport) -> int:
	var total := 0
	for line: Array in card.lines_text:
		total += int(line[1])
	return total


func test_a_guest_accounts_report_is_the_nights_own_tally_and_its_lines_add_up() -> void:
	_guest()
	var screen := await _night_from_play(3)
	var night := screen.night
	assert_bool(night.server.xp.has_seat(Night.PLAYER_ID)).is_true()
	_play_and_end(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var board: HudEndBoard = screen.get_node("EndBoard")
	var card := board.report_card
	assert_bool(board.visible).is_true()
	assert_bool(card.visible).is_true()
	# The night's own tally: the round that started and the points the player was paid.
	var tally := night.server.xp.night_xp(Night.PLAYER_ID)
	assert_int(tally).is_greater_equal(XpRules.ROUND_XP + 7)
	assert_str(card.total_text).is_equal("+%d XP" % tally)
	assert_int(_sum_of(card)).is_equal(tally)
	assert_str(card.heading_text).is_equal("YOUR NIGHT")
	assert_str(card.note_text).is_equal("")
	# The settled number of the same night, from the rules' stats, is that tally.
	var progress := night.progress
	assert_object(progress).is_not_null()
	assert_int(progress.xp()).is_equal(tally)
	assert_int(XpRules.settle(XpRules.stats_of(progress.tally, Night.PLAYER_ID))).is_equal(tally)
	# The bar ends where the account does, and the level is the one the popups said.
	var total := START_XP + tally
	assert_str(card.level_text).is_equal(
		(
			"LEVEL %d" % LevelCurve.level_of(total)
			if LevelCurve.level_of(START_XP) == LevelCurve.level_of(total)
			else "LEVEL %d TO %d" % [LevelCurve.level_of(START_XP), LevelCurve.level_of(total)]
		)
	)
	assert_int(night.state.levels[Night.PLAYER_ID]).is_equal(LevelCurve.level_of(total))
	# The board's rows still list every player.
	assert_int(board.row_ids.size()).is_equal(4)


func test_a_night_with_no_account_shows_what_it_would_have_paid_and_that_nothing_was_saved(
) -> void:
	var screen := await _night_from_play(2)
	var night := screen.night
	assert_array(night.server.xp.seats()).is_empty()
	_play_and_end(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var board: HudEndBoard = screen.get_node("EndBoard")
	var card := board.report_card
	assert_bool(card.visible).is_true()
	assert_str(card.heading_text).is_equal("YOUR NIGHT, UNSAVED")
	assert_str(card.note_text).is_equal("NO ACCOUNT: THIS NIGHT WAS NOT SAVED")
	assert_str(card.level_text).is_equal("")
	# What the rules would have paid for the stats of the night, and nobody was told any of it.
	assert_int(night.server.xp.night_xp(Night.PLAYER_ID)).is_zero()
	assert_int(night.state.xp_events).is_zero()
	assert_int(_sum_of(card)).is_greater_equal(XpRules.ROUND_XP + 7)
	assert_str(card.total_text).is_equal("+%d XP" % _sum_of(card))
