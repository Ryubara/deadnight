extends GdUnitTestSuite
## The plate everywhere a name shows besides the bottom-left boxes (#1070): the scoreboard and the
## night report (a card chip behind the row, the emblem after the name, the level badge and the
## name where they were), the lobby's seats (the card and emblem a member chose, only those the
## game has), and the equip screen (what is worn, what is owned, what is still to earn and how, and
## the choice written to the profile).

const PROFILE_DIR := "user://test_plate_screen/"

var _holder: Control


func before_test() -> void:
	HudPortrait.live = false
	UIMotion.reduced = false
	DirAccess.make_dir_recursive_absolute(PROFILE_DIR)
	for file in DirAccess.get_files_at(PROFILE_DIR):
		DirAccess.remove_absolute(PROFILE_DIR + file)


func after_test() -> void:
	HudPortrait.live = true
	Input.action_release(Hud.SCOREBOARD_ACTION)
	LobbyScreen.opener = Callable()
	if is_instance_valid(_holder):
		_holder.free()
	await RouterFixture.clear(get_tree())


func _state() -> HudState:
	var state := HudState.new()
	state.local_player_id = 1
	for i in 3:
		state.set_player_name(i + 1, ["Ruby", "Moe", "Dee"][i])
		state.team[i + 1]["points"] = 1000 * (3 - i)
	state.set_player_level(1, 12, 12)
	state.set_player_level(2, 30, 31)
	state.set_player_plate(1, &"cartoon", &"admit_one")
	state.set_player_plate(2, &"", &"walk_in")
	return state


func _host() -> Control:
	_holder = Control.new()
	_holder.size = Vector2(1920.0, 1080.0)
	add_child(_holder)
	return _holder


# --- The scoreboard and the night report ---


func test_the_scoreboard_puts_a_card_behind_the_row_and_the_emblem_after_the_name() -> void:
	var fixture := HudFixture.make(_host(), 3)
	var state := fixture.hud.state
	state.set_player_level(1, 12, 12)
	state.set_player_plate(1, &"cartoon", &"admit_one")
	state.set_player_plate(2, &"", &"walk_in")
	var board := fixture.hud.scoreboard
	Input.action_press(Hud.SCOREBOARD_ACTION)
	board.set_shown(true)
	board.refresh()
	await await_idle_frame()
	await await_idle_frame()
	var cards := board.find_children("Card", "CardArt", true, false)
	assert_int(cards.size()).is_equal(1)
	assert_str((cards[0] as CardArt).card_id).is_equal("cartoon")
	assert_bool((cards[0] as CardArt).by_height).is_true()
	assert_int(board.find_children("Emblem", "EmblemArt", true, false).size()).is_equal(2)
	# The name and the level are what they were.
	assert_str(board.rows_text[0][0]).is_equal("RUBY")
	assert_array(board.row_levels).is_equal([12, 0, 0])
	# The emblem is after the name's room and the row still fits its cell.
	for slot: Control in board.find_children("EmblemSlot", "Control", true, false):
		assert_float(slot.size.x).is_equal(PlateRow.emblem_taken(&"x", slot.size.y))


func test_the_night_report_shows_the_same_plate() -> void:
	var board := HudEndBoard.new()
	_host().add_child(board)
	board.show_results(_state(), "THE CROWD WINS", "Leave")
	await await_idle_frame()
	await await_idle_frame()
	var cards := board.find_children("Card", "CardArt", true, false)
	assert_int(cards.size()).is_equal(1)
	assert_str((cards[0] as CardArt).card_id).is_equal("cartoon")
	assert_int(board.find_children("Emblem", "EmblemArt", true, false).size()).is_equal(2)
	assert_array(board.row_levels).is_equal([12, 30, 0])
	# A viewer who turned levels off still sees the cards and emblems (they are not levels).
	assert_str(board.rows_text[1][0]).is_equal("MOE")


func test_a_row_with_no_card_or_emblem_is_what_it_was() -> void:
	var fixture := HudFixture.make(_host(), 2)
	fixture.hud.state.set_player_level(1, 12, 12)
	var board := fixture.hud.scoreboard
	Input.action_press(Hud.SCOREBOARD_ACTION)
	board.set_shown(true)
	board.refresh()
	await await_idle_frame()
	assert_int(board.find_children("Card", "CardArt", true, false).size()).is_equal(0)
	assert_int(board.find_children("EmblemSlot", "Control", true, false).size()).is_equal(0)


func test_a_frame_goes_round_the_row_of_the_scoreboard_and_the_night_report() -> void:
	var fixture := HudFixture.make(_host(), 3)
	var state := fixture.hud.state
	state.set_player_plate(1, &"cartoon", &"admit_one", &"gold")
	state.set_player_plate(2, &"", &"", &"filmstrip")
	var board := fixture.hud.scoreboard
	Input.action_press(Hud.SCOREBOARD_ACTION)
	board.set_shown(true)
	board.refresh()
	await await_idle_frame()
	await await_idle_frame()
	var frames := board.find_children("Frame", "FrameArt", true, false)
	assert_int(frames.size()).is_equal(2)
	var shown: Array[String] = []
	for each in frames:
		shown.append(String((each as FrameArt).frame_id))
		# It fills its row, over the card, and the row's cells are where they were.
		var row := each.get_parent() as Control
		assert_vector((each as FrameArt).size).is_equal(row.size)
		assert_int(each.get_index()).is_equal(row.get_child_count() - 1)
		assert_int((each as FrameArt).op_count()).is_greater(0)
	assert_array(shown).contains_exactly_in_any_order(["gold", "filmstrip"])
	assert_str(board.rows_text[0][0]).is_equal("RUBY")
	# The night report draws the same.
	var report := HudEndBoard.new()
	_host().add_child(report)
	report.show_results(state, "THE CROWD WINS", "Leave")
	await await_idle_frame()
	await await_idle_frame()
	assert_int(report.find_children("Frame", "FrameArt", true, false).size()).is_equal(2)
	assert_str(report.rows_text[0][0]).is_equal("RUBY")


func test_a_row_with_no_frame_has_no_frame_art() -> void:
	var fixture := HudFixture.make(_host(), 2)
	var board := fixture.hud.scoreboard
	Input.action_press(Hud.SCOREBOARD_ACTION)
	board.set_shown(true)
	board.refresh()
	await await_idle_frame()
	assert_int(board.find_children("Frame", "FrameArt", true, false).size()).is_equal(0)


# --- The lobby ---


func test_the_lobby_shows_what_members_chose_and_only_what_the_game_has() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	var host := LobbyFixture.member("a", "Ann", 1, true)
	host["card"] = "dead_eye"
	host["emblem"] = "walk_in"
	var guest := LobbyFixture.member("b", "Bo", 2)
	guest["card"] = "not_a_card"
	guest["emblem"] = "nonsense"
	var third := LobbyFixture.member("c", "Cy", 3)
	api.lobby = LobbyFixture.lobby([host, guest, third])
	await RouterFixture.clear(get_tree())
	LobbyScreen.opener = func() -> void: pass
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"lobby": api.lobby, "api": api}
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	await await_idle_frame()
	var shown: Array[bool] = []
	for row in screen._seat_rows:
		shown.append((row["card"] as CardArt).visible)
	assert_array(shown).is_equal([true, false, false, false])
	assert_str((screen._seat_rows[0]["card"] as CardArt).card_id).is_equal("dead_eye")
	assert_str((screen._seat_rows[0]["emblem"] as EmblemArt).emblem_id).is_equal("walk_in")
	assert_bool((screen._seat_rows[1]["emblem"] as EmblemArt).visible).is_false()
	assert_bool((screen._seat_rows[0]["frame"] as FrameArt).visible).is_false()
	# The words of the seats are what they were, and the names are still on screen with room.
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  Cy", "4  (open)"])
	for row in screen._seat_rows.slice(0, 3):
		var seat_name := row["name"] as Label
		assert_float(seat_name.size.x).is_greater(seat_name.get_minimum_size().x - 1.0)
		assert_float(seat_name.size.x).is_greater(20.0)
	screen.free()


func test_the_lobby_puts_the_frame_a_member_chose_round_their_seat() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	var host := LobbyFixture.member("a", "Ann", 1, true)
	host["frame"] = "brass"
	var guest := LobbyFixture.member("b", "Bo", 2)
	guest["frame"] = "not_a_frame"
	api.lobby = LobbyFixture.lobby([host, guest])
	await RouterFixture.clear(get_tree())
	LobbyScreen.opener = func() -> void: pass
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"lobby": api.lobby, "api": api}
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	await await_idle_frame()
	var first := screen._seat_rows[0]["frame"] as FrameArt
	assert_bool(first.visible).is_true()
	assert_str(first.frame_id).is_equal("brass")
	assert_bool((screen._seat_rows[1]["frame"] as FrameArt).visible).is_false()
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  (open)", "4  (open)"])
	screen.free()


# --- The equip screen ---


func _profile(level: int, done: Array[StringName], equipped := {}) -> String:
	var path := PROFILE_DIR + "profile.json"
	var profile := Profile.new()
	profile.xp = LevelCurve.xp_for(level)
	profile.done = done
	profile.equipped = equipped
	ProfileSave.write(profile, [], 1, path)
	return path


func _screen(path: String, account := true) -> CardsScreen:
	await RouterFixture.clear(get_tree())
	var screen := (
		(load("res://ui/screens/cards_screen.tscn") as PackedScene).instantiate() as CardsScreen
	)
	screen.params = {"path": path, "account": func() -> bool: return account}
	_host().add_child(screen)
	await await_idle_frame()
	await await_idle_frame()
	return screen


func test_the_screen_lists_every_piece_with_what_is_owned_and_how_to_earn_the_rest() -> void:
	var path := _profile(10, [&"f_dead_eye"], {"card": "dead_eye"})
	var screen := await _screen(path)
	var plates := PlateCatalog.shipped()
	# A tile for every card, emblem and frame, and one each for wearing none.
	assert_int(screen.tiles().size()).is_equal(
		(
			plates.ids(PlateCatalog.CARD).size()
			+ plates.ids(PlateCatalog.EMBLEM).size()
			+ plates.ids(PlateCatalog.FRAME).size()
			+ 3
		)
	)
	var worn := screen.tile(PlateCatalog.CARD, &"dead_eye")
	assert_bool(worn.owned).is_true()
	assert_str(worn.status_text()).is_equal(PlateTile.WEARING)
	assert_bool(screen.tile(PlateCatalog.CARD, &"cartoon").owned).is_true()
	var locked := screen.tile(PlateCatalog.CARD, &"ironwork")
	assert_bool(locked.owned).is_false()
	assert_str(locked.status_text()).is_equal("Mend 1,000 boards")
	assert_str(screen.tile(PlateCatalog.CARD, &"trailers").status_text()).is_equal("Reach level 25")
	assert_str(screen.previewed()["card"]).is_equal("dead_eye")
	assert_str(screen.note_text()).contains("yours")


func test_wearing_a_piece_writes_it_to_the_profile_and_one_not_earned_changes_nothing() -> void:
	var path := _profile(10, [&"f_dead_eye"])
	var screen := await _screen(path)
	assert_bool(screen.wear(PlateCatalog.CARD, &"ironwork")).is_false()
	assert_str(screen.note_text()).contains("Mend 1,000 boards")
	assert_str(ProfileStore.open(path).profile.chosen(&"card")).is_equal("")
	assert_bool(screen.wear(PlateCatalog.CARD, &"dead_eye")).is_true()
	assert_bool(screen.wear(PlateCatalog.EMBLEM, &"cartoon")).is_true()
	var saved := ProfileStore.open(path)
	assert_str(saved.profile.chosen(&"card")).is_equal("dead_eye")
	assert_str(saved.profile.chosen(&"emblem")).is_equal("cartoon")
	assert_str(screen.previewed()["emblem"]).is_equal("cartoon")
	assert_str(screen.tile(PlateCatalog.CARD, &"dead_eye").status_text()).is_equal(
		PlateTile.WEARING
	)
	# Taking it off is a choice too.
	assert_bool(screen.wear(PlateCatalog.CARD, &"")).is_true()
	assert_str(ProfileStore.open(path).profile.chosen(&"card")).is_equal("")
	assert_str(screen.previewed()["card"]).is_equal("")


func test_pressing_a_tile_does_the_same_as_wearing() -> void:
	var path := _profile(5, [])
	var screen := await _screen(path)
	screen.tile(PlateCatalog.CARD, &"doors_open").pressed.emit()
	await await_idle_frame()
	assert_str(ProfileStore.open(path).profile.chosen(&"card")).is_equal("doors_open")


func test_a_player_with_no_account_owns_nothing_and_is_told_where_to_sign_in() -> void:
	var path := _profile(1, [])
	var screen := await _screen(path, false)
	assert_str(screen.note_text()).contains("Sign in")
	assert_bool(screen.wear(PlateCatalog.CARD, &"")).is_false()
	for each in screen.tiles():
		if each.piece_id != &"":
			assert_bool(each.owned).is_false()


func test_the_frames_have_a_tab_of_their_own_and_wearing_one_writes_it_to_the_profile() -> void:
	var path := _profile(30, [&"f_filmstrip"])
	var screen := await _screen(path)
	# The cards are on show first; a tab shows its page when it is pressed.
	assert_str(screen.shown_tab()).is_equal("card")
	assert_bool(screen.tile(PlateCatalog.FRAME, &"chrome").is_visible_in_tree()).is_false()
	(screen.find_child("TabFrame", true, false) as UIButton).pressed.emit()
	await await_idle_frame()
	assert_str(screen.shown_tab()).is_equal("frame")
	assert_bool(screen.tile(PlateCatalog.FRAME, &"chrome").is_visible_in_tree()).is_true()
	assert_bool(screen.tile(PlateCatalog.CARD, &"cartoon").is_visible_in_tree()).is_false()
	# Level 30 owns Chrome (29), the filmstrip challenge is done, Brass (37) is still to earn.
	assert_bool(screen.tile(PlateCatalog.FRAME, &"chrome").owned).is_true()
	assert_bool(screen.tile(PlateCatalog.FRAME, &"filmstrip").owned).is_true()
	assert_str(screen.tile(PlateCatalog.FRAME, &"brass").status_text()).is_equal("Reach level 37")
	assert_str(screen.tile(PlateCatalog.FRAME, &"velvet_rope").status_text()).is_equal(
		"Get 25 teammates back on their feet"
	)
	assert_str(screen.tile(PlateCatalog.FRAME, &"").title_text()).is_equal("No frame")
	assert_bool(screen.wear(PlateCatalog.FRAME, &"brass")).is_false()
	assert_str(ProfileStore.open(path).profile.chosen(&"frame")).is_equal("")
	assert_bool(screen.wear(PlateCatalog.FRAME, &"chrome")).is_true()
	assert_str(ProfileStore.open(path).profile.chosen(&"frame")).is_equal("chrome")
	assert_str(screen.previewed()["frame"]).is_equal("chrome")
	assert_str(screen.tile(PlateCatalog.FRAME, &"chrome").status_text()).is_equal(PlateTile.WEARING)
	# One at a time: another replaces it.
	assert_bool(screen.wear(PlateCatalog.FRAME, &"filmstrip")).is_true()
	assert_str(ProfileStore.open(path).profile.chosen(&"frame")).is_equal("filmstrip")
	assert_str(screen.tile(PlateCatalog.FRAME, &"chrome").status_text()).is_equal("")
	assert_bool(screen.wear(PlateCatalog.FRAME, &"")).is_true()
	assert_str(screen.previewed()["frame"]).is_equal("")
