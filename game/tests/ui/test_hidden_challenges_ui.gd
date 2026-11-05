extends GdUnitTestSuite
## Hidden means no leak (#1172): until a hidden challenge is done, nothing a player can read holds
## its title or its words: not the equip screen's tiles and notes, not the main menu, not the news
## the menu tells at sign-in, not the progress prompt and popup cards of a night. A silhouette and a
## riddle show instead. Once it is done its words show where they should (so the scan has teeth).

const PROFILE_DIR := "user://test_hidden_ui/"
const DAY := 20401

var _holder: Control
var _catalog: ChallengeCatalog
var _plates: PlateCatalog


func before_test() -> void:
	HudPortrait.live = false
	UIMotion.reduced = false
	_catalog = ChallengeCatalog.load_default()
	_plates = PlateCatalog.shipped()
	DirAccess.make_dir_recursive_absolute(PROFILE_DIR)
	for file in DirAccess.get_files_at(PROFILE_DIR):
		DirAccess.remove_absolute(PROFILE_DIR + file)
	ProgressSeen.path = PROFILE_DIR + "seen.json"


func after_test() -> void:
	HudPortrait.live = true
	ProgressSeen.path = ""
	MainMenu.board_factory = Callable()
	if is_instance_valid(_holder):
		_holder.free()
	await RouterFixture.clear(get_tree())


func _hidden() -> Array[ChallengeDef]:
	var found: Array[ChallengeDef] = []
	for def in _catalog.of_family(ChallengeDef.Family.FEAT):
		if def.hidden:
			found.append(def)
	return found


## What gives a hidden challenge away: its words and the titles of what it gives, in lower case.
func _secrets(only: Array[ChallengeDef] = []) -> Array[String]:
	var found: Array[String] = []
	for def in only if not only.is_empty() else _hidden():
		found.append(def.text.to_lower())
		for grant in def.grants:
			var parts := String(grant).split(":")
			found.append(_plates.title(StringName(parts[0]), StringName(parts[1])).to_lower())
	return found


## Every text a player can read in a tree of controls (labels, buttons, tips, rich text).
func _texts(root: Node, into: Array[String] = []) -> Array[String]:
	if root is Label:
		into.append((root as Label).text)
	elif root is ChallengeRow:
		# A row is a button that keeps its words in its labels and answers `text()`.
		into.append((root as ChallengeRow).text())
	elif root is Button:
		into.append((root as Button).text)
	elif root is RichTextLabel:
		into.append((root as RichTextLabel).get_parsed_text())
	if root is Control and (root as Control).tooltip_text != "":
		into.append((root as Control).tooltip_text)
	if root is Control and (root as Control).accessibility_name != "":
		into.append((root as Control).accessibility_name)
	for child in root.get_children():
		_texts(child, into)
	return into


## Which of `secrets` show in any of `texts`.
func _leaks(texts: Array[String], secrets: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for secret in secrets:
		for text in texts:
			if text.to_lower().contains(secret):
				found.append("'%s' in '%s'" % [secret, text])
	return found


func _host() -> Control:
	_holder = Control.new()
	_holder.size = Vector2(1920.0, 1080.0)
	add_child(_holder)
	return _holder


func _profile(level: int, done: Array[StringName]) -> String:
	var path := PROFILE_DIR + "profile.json"
	var profile := Profile.new()
	profile.xp = LevelCurve.xp_for(level)
	profile.done = done
	ProfileSave.write(profile, [], 1, path)
	return path


func _screen(path: String) -> CardsScreen:
	await RouterFixture.clear(get_tree())
	var screen := (
		(load("res://ui/screens/cards_screen.tscn") as PackedScene).instantiate() as CardsScreen
	)
	screen.params = {"path": path, "account": func() -> bool: return true}
	_host().add_child(screen)
	await await_idle_frame()
	await await_idle_frame()
	return screen


# --- The equip screen: the plate pickers and the card and emblem lists ---


func test_the_equip_screen_shows_a_silhouette_and_a_riddle_for_each_hidden_piece_until_done(
) -> void:
	var screen := await _screen(_profile(30, [&"f_dead_eye"]))
	var riddles: Array[String] = []
	for def in _hidden():
		riddles.append(def.riddle)
	var veiled := 0
	for tile in screen.tiles():
		if not _plates.is_hidden(tile.kind, tile.piece_id):
			continue
		veiled += 1
		assert_bool(tile.owned).is_false()
		assert_str(tile.title_text()).is_equal("???")
		assert_array(riddles).contains([tile.status_text()])
		assert_bool(tile.art().get("silhouette")).is_true()
	assert_int(veiled).is_equal(10)
	# Every tab's page, the preview, the note: not a word of what is hidden.
	assert_array(_leaks(_texts(screen), _secrets())).is_empty()
	# Pressing a hidden tile shakes it and says the riddle, not the challenge.
	for tile in screen.tiles():
		if _plates.is_hidden(tile.kind, tile.piece_id):
			assert_bool(screen.wear(tile.kind, tile.piece_id)).is_false()
			assert_str(screen.note_text()).contains(tile.status_text())
			assert_str(screen.note_text()).contains("???")
			assert_array(_leaks([screen.note_text()], _secrets())).is_empty()
	assert_array(_leaks(_texts(screen), _secrets())).is_empty()


func test_a_hidden_piece_shows_its_title_and_art_once_its_challenge_is_done() -> void:
	var done: Array[StringName] = [&"f_snack_break", &"f_dead_on_arrival"]
	var screen := await _screen(_profile(30, done))
	for kind in [PlateCatalog.CARD, PlateCatalog.EMBLEM]:
		var tile := screen.tile(kind, &"snack_break")
		assert_bool(tile.owned).is_true()
		assert_str(tile.title_text()).is_equal("Snack Break")
		assert_str(tile.status_text()).is_equal("")
		assert_bool(tile.art().get("silhouette")).is_false()
	# What is still hidden stays so beside it, and the scan finds what is shown (it has teeth).
	var secrets := _secrets([_catalog.get_def(&"f_long_way_round")])
	assert_array(_leaks(_texts(screen), secrets)).is_empty()
	(
		assert_array(_leaks(_texts(screen), _secrets([_catalog.get_def(&"f_snack_break")])))
		. is_not_empty()
	)
	assert_bool(screen.wear(PlateCatalog.CARD, &"snack_break")).is_true()
	assert_str(screen.note_text()).contains("Snack Break")


func test_final_cut_shows_when_the_last_tier_card_is() -> void:
	var screen := await _screen(_profile(55, []))
	assert_bool(screen.tile(PlateCatalog.CARD, &"final_cut").owned).is_true()
	assert_bool(screen.tile(PlateCatalog.CARD, &"final_cut").art().get("silhouette")).is_false()
	assert_str(screen.tile(PlateCatalog.CARD, &"final_cut").title_text()).is_equal("Final Cut")
	var below := await _screen(_profile(54, []))
	assert_bool(below.tile(PlateCatalog.CARD, &"final_cut").owned).is_false()
	assert_str(below.tile(PlateCatalog.CARD, &"final_cut").title_text()).is_equal("???")


func test_a_silhouette_draws_one_flat_colour_and_no_title() -> void:
	for id in [&"snack_break", &"final_cut"]:
		var card := CardArt.new()
		card.size = Vector2(240.0, 65.0)
		card.card_id = id
		card.titled = true
		var lit := card.shape_count()
		assert_int(lit).is_greater(1)
		card.silhouette = true
		assert_int(card.shape_count()).is_equal(lit)
		for item in card._built:
			assert_object(item["c"]).is_equal(ItemIcons.SILHOUETTE)
		card.free()
		var emblem := EmblemArt.make(id, 64.0)
		emblem.silhouette = true
		assert_int(emblem.shape_count()).is_greater(1)
		for item in emblem._built:
			assert_object(item["c"]).is_equal(ItemIcons.SILHOUETTE)
		emblem.free()


# --- The main menu: the Challenges tab, the home panel, the loadout ---


func test_the_main_menu_holds_no_word_of_a_hidden_challenge_whatever_the_progress() -> void:
	var path := ChallengeFixture.save_path("hidden_menu")
	var clock := ChallengeFixture.clock_on(DAY)
	var board := ChallengeBoard.open(path, clock)
	# The board has moved every stat a hidden challenge counts, a step short of done.
	board.profile.feats[&"f_long_way_round"] = 7
	board.profile.lifetime[ChallengeStats.ROUND_LONG_WAY] = 7
	board.profile.lifetime[ChallengeStats.BREAKS_STAND] = 0
	board.save()
	MainMenu.board_factory = func() -> Object: return ChallengeBoard.open(path, clock)
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	var menu := UIRouter.top() as MainMenu
	assert_array(_leaks(_texts(menu), _secrets())).is_empty()
	# What the menu reads from the board: every row's words.
	var rows: Array[String] = []
	for row: Dictionary in menu.shell.context.board.dailies():
		rows.append(String(row["text"]))
	for row: Dictionary in menu.shell.context.board.orders():
		rows.append(String(row["text"]))
	for row: Dictionary in menu.shell.context.board.milestones():
		rows.append(String(row["text"]))
	assert_array(rows).is_not_empty()
	assert_array(_leaks(rows, _secrets())).is_empty()


func test_every_chip_of_the_challenges_tab_holds_no_word_of_a_hidden_challenge() -> void:
	var path := ChallengeFixture.save_path("hidden_chips")
	var clock := ChallengeFixture.clock_on(DAY)
	var board := ChallengeBoard.open(path, clock)
	board.profile.feats[&"f_long_way_round"] = 7
	board.profile.lifetime[ChallengeStats.ROUND_LONG_WAY] = 7
	board.save()
	MainMenu.board_factory = func() -> Object: return ChallengeBoard.open(path, clock)
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	var menu := UIRouter.top() as MainMenu
	var panel := menu.shell.panel(MenuTab.Id.CHALLENGES) as ChallengesPanel
	assert_object(panel).is_not_null()
	for family: ChallengesPanel.Family in ChallengesPanel.Family.values():
		panel.show_family(family)
		await await_idle_frame()
		assert_array(_leaks(_texts(panel), _secrets())).is_empty()
	# The Poster sets chip shows each set whole: its title, its lines and every panel's words.
	panel.show_family(ChallengesPanel.Family.SETS)
	await await_idle_frame()
	assert_array(panel.sets()).is_not_empty()
	var data: Array[String] = []
	for entry: Dictionary in menu.shell.context.board.poster_sets():
		data.append(String(entry.get("title", "")))
		for line: Variant in entry.get("lines", []):
			data.append(String(line))
		for each: Dictionary in entry.get("panels", []):
			data.append(String(each.get("text", "")))
	assert_array(data).is_not_empty()
	assert_array(_leaks(data, _secrets())).is_empty()


# --- The news and the popups ---


func test_the_news_read_at_sign_in_tells_no_hidden_challenge_that_is_not_done() -> void:
	var before := ChallengeProfile.fresh_for("an-account")
	var after := ChallengeProfile.fresh_for("an-account")
	after.refresh(_catalog, DAY)
	# The account's board moved: a hidden one a step short, one daily done by the day's first stat.
	after.feats[&"f_long_way_round"] = 7
	after.lifetime[ChallengeStats.ROUND_LONG_WAY] = 7
	for entry in after.dailies:
		entry["progress"] = _catalog.get_def(entry["id"]).target
	var events := ProgressNews.challenges_after_read("an-account", before, after, _catalog, DAY)
	assert_array(events).is_not_empty()
	var words: Array[String] = []
	for event: Dictionary in events:
		words.append(String(event["text"]))
	assert_array(_leaks(words, _secrets())).is_empty()
	var keys := ProgressNews.finished_keys(after, _catalog, DAY)
	for key: String in keys:
		assert_array(_leaks([String(keys[key]["text"])], _secrets())).is_empty()


func test_a_night_tells_a_hidden_challenge_only_when_it_is_done_and_then_in_its_own_words() -> void:
	var tracker := ChallengeTracker.new(_catalog, ChallengeFixture.clock_on(DAY), NightTally.new())
	tracker.tally.know(RulesFixture.tuning(), "drive_in")
	tracker.follow(1, ChallengeProfile.fresh())
	var told: Array[Dictionary] = []
	tracker.advanced.connect(func(advance: Dictionary) -> void: told.append(advance))
	var bench_events: Array[Dictionary] = [{"type": &"player_added", "player_id": 1, "bot": false}]
	for round_number in range(1, 8):
		bench_events.append({"type": &"round_started", "round": round_number, "zombie_count": 1})
	for event in bench_events:
		tracker.observe(event)
	var texts: Array[String] = []
	for advance in told:
		texts.append(String(advance["text"]))
	assert_array(_leaks(texts, _secrets())).is_empty()
	tracker.observe({"type": &"round_started", "round": 8, "zombie_count": 1})
	var done := told.filter(func(a: Dictionary) -> bool: return a["id"] == &"f_long_way_round")
	assert_int(done.size()).is_equal(1)
	# The popup lane shows the finish in the challenge's own words, and shows nothing before.
	var lane := PopupLane.new()
	_host().add_child(lane)
	for advance in told:
		if advance["id"] != &"f_long_way_round":
			continue
		var event: Dictionary = advance.duplicate()
		event["type"] = &"challenge_advanced"
		lane.on_event(event)
	lane.advance(0.5)
	assert_int(lane.cards().size()).is_equal(1)
	(
		assert_array(
			_leaks(_texts(lane.cards()[0]), [_catalog.get_def(&"f_long_way_round").text.to_lower()])
		)
		. is_not_empty()
	)


func test_the_lane_shows_nothing_for_the_steps_toward_a_hidden_challenge() -> void:
	var lane := PopupLane.new()
	_host().add_child(lane)
	var profile := ChallengeProfile.fresh()
	for round_number in range(1, 8):
		for advance in profile.apply(_catalog, ChallengeStats.ROUND_LONG_WAY, round_number, 1):
			var event: Dictionary = advance.duplicate()
			event["type"] = &"challenge_advanced"
			lane.on_event(event)
	lane.advance(0.5)
	assert_int(lane.cards().size()).is_equal(0)
