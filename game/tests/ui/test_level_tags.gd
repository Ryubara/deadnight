extends GdUnitTestSuite
## The level and icon beside a name (#1077, docs/design/progression.md#the-level-over-a-head): what
## the HUD's state keeps of them (the events, a late joiner's snapshot, a bot, the viewer's
## setting), the tag over a head that keeps its place inside the screen, and the scoreboard, the
## night report and the lobby list that show them.

const CANVASES: Array[Vector2] = [
	Vector2(1536.0, 864.0),
	Vector2(1920.0, 1080.0),
	Vector2(2340.0, 1080.0),
	Vector2(2560.0, 1080.0),
]

var _settings: SettingsService


func before_test() -> void:
	UIMotion.reduced = false
	_settings = SettingsService.new()
	_settings.path = SettingsService.HARNESS_PATH
	LevelIcons.release()


func after_test() -> void:
	if is_instance_valid(_settings):
		_settings.free()
	LobbyScreen.opener = Callable()


func _host(canvas := Vector2(1920.0, 1080.0)) -> Control:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	return host


## A state whose party has levels: Ruby 12, Moe 30 (icon 31), Dee none.
func _state(state := HudState.new()) -> HudState:
	state.local_player_id = 1
	for i in 3:
		state.set_player_name(i + 1, ["Ruby", "Moe", "Dee"][i])
	state.set_player_level(1, 12, 12)
	state.set_player_level(2, 30, 31)
	return state


func _ally(id: int, x: float, state: HudState, label := "Ruby", extra := {}) -> Dictionary:
	var shown := state.level_of(state.team.get(id, {}))
	var marker := {
		"id": StringName("player_%d" % id),
		"kind": &"ally",
		"x": x,
		"y": 0.5,
		"distance": 5.0,
		"label": label,
		"important": false,
		"level": shown.x,
		"icon": shown.y,
	}
	marker.merge(extra, true)
	return marker


# --- The state ---


func test_the_state_keeps_the_level_and_icon_of_a_seat_from_the_events() -> void:
	var state := HudState.new()
	state.apply_event(
		{"type": &"player_named", "player_id": 2, "name": "Moe", "level": 30, "icon": 31}
	)
	assert_vector(state.level_of(state.team[2])).is_equal(Vector2i(30, 31))
	state.apply_event({"type": &"player_leveled", "player_id": 2, "level": 31, "icon": 31})
	assert_vector(state.level_of(state.team[2])).is_equal(Vector2i(31, 31))
	# A name with no level (a bot took the seat) clears it.
	state.apply_event({"type": &"player_named", "player_id": 2, "name": "Bot Vic"})
	assert_vector(state.level_of(state.team[2])).is_equal(Vector2i.ZERO)


func test_a_bad_level_is_no_level_and_never_indexes_outside_the_atlas() -> void:
	var state := HudState.new()
	for level in [0, -1, 56, 9999]:
		state.set_player_level(1, level, 1)
		assert_vector(state.level_of(state.team[1])).is_equal(Vector2i.ZERO)
	state.set_player_level(1, 7, 9999)
	assert_vector(state.level_of(state.team[1])).is_equal(Vector2i(7, 7))


func test_a_late_joiner_reads_every_level_from_the_snapshot_and_keeps_them_after_a_resume() -> void:
	var rules := GameRules.new((load(HudFixture.TUNING) as RulesTuning).duplicate(true), 1)
	for id in [1, 2, 3]:
		rules.apply(RulesAction.add_player(id))
	var snapshot := rules.to_dict()
	snapshot["names"] = {1: "Ruby", 2: "Moe", 3: "Dee"}
	snapshot["levels"] = {1: Vector2i(12, 12), 2: Vector2i(30, 31)}
	var state := HudState.new()
	state.local_player_id = 3
	state.load_snapshot(snapshot)
	assert_vector(state.level_of(state.team[1])).is_equal(Vector2i(12, 12))
	assert_vector(state.level_of(state.team[2])).is_equal(Vector2i(30, 31))
	assert_vector(state.level_of(state.team[3])).is_equal(Vector2i.ZERO)
	# The seat that came back is loaded again from a newer snapshot: its level is the new one.
	snapshot["levels"] = {1: Vector2i(13, 13)}
	state.load_snapshot(snapshot)
	assert_vector(state.level_of(state.team[1])).is_equal(Vector2i(13, 13))
	assert_vector(state.level_of(state.team[2])).is_equal(Vector2i.ZERO)
	# A snapshot of a server that knows no levels leaves what the events said.
	snapshot.erase("levels")
	state.load_snapshot(snapshot)
	assert_vector(state.level_of(state.team[1])).is_equal(Vector2i(13, 13))


func test_a_bot_shows_no_level_and_the_setting_hides_every_level_of_the_viewer() -> void:
	var state := _state()
	state.team[2]["bot"] = true
	assert_vector(state.level_of(state.team[2])).is_equal(Vector2i.ZERO)
	state.team[2]["bot"] = false
	assert_vector(state.level_of(state.team[2])).is_equal(Vector2i(30, 31))
	state.show_levels = false
	assert_vector(state.level_of(state.team[1])).is_equal(Vector2i.ZERO)
	assert_vector(state.level_of(state.team[2])).is_equal(Vector2i.ZERO)
	# Turned back on, they are still there: the setting hides, it does not forget.
	state.show_levels = true
	assert_vector(state.level_of(state.team[1])).is_equal(Vector2i(12, 12))


# --- The setting ---


func test_levels_are_shown_by_default_and_the_setting_reaches_the_hud() -> void:
	assert_bool(SettingsService.DEFAULTS[SettingsService.SHOW_LEVELS]).is_true()
	assert_bool(bool(_settings.get_value(SettingsService.SHOW_LEVELS))).is_true()
	var fixture := HudFixture.make(_host(), 2)
	fixture.hud.state.set_player_level(2, 30, 30)
	var binding := NightHudBinding.new(
		fixture.hud, ClientState.new(), fixture.rules.tuning, null, null, _settings
	)
	assert_bool(fixture.hud.state.show_levels).is_true()
	_settings.set_value(SettingsService.SHOW_LEVELS, false)
	assert_bool(fixture.hud.state.show_levels).is_false()
	assert_vector(fixture.hud.state.level_of(fixture.hud.state.team[2])).is_equal(Vector2i.ZERO)
	_settings.set_value(SettingsService.SHOW_LEVELS, true)
	assert_bool(fixture.hud.state.show_levels).is_true()
	assert_object(binding).is_not_null()


func test_the_settings_screen_has_the_toggle_in_accessibility() -> void:
	var found := false
	for section: Dictionary in SettingsScreen.TABS:
		for row: Dictionary in section["rows"]:
			if row["key"] == SettingsService.SHOW_LEVELS:
				found = true
				assert_str(section["title"]).is_equal("Accessibility")
				assert_str(row["kind"]).is_equal("toggle")
	assert_bool(found).is_true()


# --- The tag over a head ---


func test_a_tag_is_icon_name_and_level_and_a_bare_name_for_a_bot() -> void:
	var fixture := HudFixture.make(_host(), 1)
	var state := _state(fixture.hud.state)
	var markers := fixture.hud.markers
	# The same words, one with a level and one without (a bot's marker has none).
	var list: Array[Dictionary] = [
		_ally(2, 0.5, state, "Moe"),
		_ally(3, 0.3, state, "Moe"),
	]
	state.set_markers(list)
	await await_idle_frame()
	var moe: Rect2 = markers.tags[&"player_2"]
	var bare: Rect2 = markers.tags[&"player_3"]
	# The tag with a level is the icon, the gaps and the level wider than the name alone.
	assert_float(moe.size.x).is_greater(bare.size.x + HudMarkers.TAG_ICON + HudMarkers.TAG_GAP)
	assert_float(moe.size.y).is_greater_equal(HudMarkers.TAG_ICON)
	assert_dict(markers.placed).contains_keys([&"player_2", &"player_3"])


func test_a_tag_stays_inside_the_screen_at_every_size_even_at_the_edges() -> void:
	for canvas in CANVASES:
		var fixture := HudFixture.make(_host(canvas), 1)
		var state := _state(fixture.hud.state)
		state.set_player_level(2, 55, 55)
		var list: Array[Dictionary] = []
		for x in [0.0, 0.01, 0.5, 0.99, 1.0]:
			var id := 2 + list.size()
			var marker := _ally(2, x, state, "A VERY LONG NAME INDEED")
			marker["id"] = StringName("player_%d" % id)
			list.append(marker)
		# A body on the ground wears its clock after the level.
		list.append(
			_ally(
				2,
				0.97,
				state,
				"Moe",
				{"id": &"player_9", "downed": true, "bleed": 31, "important": true}
			)
		)
		state.set_markers(list)
		await await_idle_frame()
		var screen := Rect2(Vector2.ZERO, fixture.hud.markers.size)
		# A tag for every marker the screen shows (x = 1 is off the screen's right edge, not important).
		assert_int(fixture.hud.markers.placed.size()).is_equal(list.size() - 1)
		assert_array(fixture.hud.markers.tags.keys()).contains_exactly_in_any_order(
			fixture.hud.markers.placed.keys()
		)
		for id: StringName in fixture.hud.markers.tags:
			var tag: Rect2 = fixture.hud.markers.tags[id]
			(
				assert_bool(screen.encloses(tag))
				. override_failure_message("%s %s outside %s" % [id, tag, screen])
				. is_true()
			)


func test_a_tag_keeps_the_places_the_markers_have_always_had() -> void:
	var fixture := HudFixture.make(_host(), 1)
	var state := _state(fixture.hud.state)
	var list: Array[Dictionary] = [
		_ally(2, 0.4, state, "Moe", {"important": true}),
		_ally(3, 1.6, state, "Dee", {"important": true}),
		_ally(2, -0.4, state, "Far", {"id": &"far"}),
	]
	state.set_markers(list)
	await await_idle_frame()
	var markers := fixture.hud.markers
	# On screen: where it is. Off screen and important: pinned to the edge. Off screen and not: gone.
	assert_bool(markers.marker_at(&"player_2")["pinned"]).is_false()
	assert_bool(markers.marker_at(&"player_3")["pinned"]).is_true()
	assert_dict(markers.marker_at(&"far")).is_empty()
	assert_bool(markers.tags.has(&"far")).is_false()


func test_a_marker_that_gets_a_level_is_drawn_again_and_one_that_keeps_it_is_not() -> void:
	var fixture := HudFixture.make(_host(), 1)
	var state := _state(fixture.hud.state)
	var markers := fixture.hud.markers
	state.set_markers([_ally(2, 0.5, state, "Moe")])
	await await_idle_frame()
	var key := markers._key()
	state.set_markers([_ally(2, 0.5, state, "Moe")])
	assert_array(markers._key()).is_equal(key)
	state.set_player_level(2, 31, 31)
	state.set_markers([_ally(2, 0.5, state, "Moe")])
	assert_array(markers._key()).is_not_equal(key)


# --- The scoreboard, the night report and the lobby ---


func test_the_scoreboard_shows_the_levels_of_the_people_and_keeps_the_names_in_one_column() -> void:
	var fixture := HudFixture.make(_host(), 3)
	var state := fixture.hud.state
	state.set_player_level(1, 12, 12)
	state.set_player_level(2, 30, 31)
	state.set_player_level(3, 55, 55)
	var board := fixture.hud.scoreboard
	board.set_shown(true)
	board.refresh()
	assert_array(board.row_levels).is_equal([12, 30, 55])
	# The cells are what they were: the name is the name, the icon and the level are beside it.
	assert_str(board.rows_text[0][0]).is_equal("RUBY")
	assert_int(_icons_in(board)).is_equal(3)
	# Every level is written whole in the room it has (a two-digit level was cut to one digit).
	var seen := 0
	for label: Label in board.find_children("*", "Label", true, false):
		if label.text in ["12", "30", "55"]:
			seen += 1
			var width := HudStyle.text_width(
				label.get_theme_font(&"font"), label.text, label.get_theme_font_size(&"font_size")
			)
			assert_float(width).is_less_equal(HudLevelCell.LEVEL_WIDTH)
	assert_int(seen).is_equal(3)
	# The viewer turns levels off: no icon, no level, no room kept for them.
	state.show_levels = false
	board.refresh()
	assert_array(board.row_levels).is_equal([0, 0, 0])
	assert_int(_icons_in(board)).is_equal(0)


func test_the_night_report_shows_the_levels_and_a_bot_none() -> void:
	var state := HudState.new()
	state.local_player_id = 1
	for i in 3:
		state.set_player_name(i + 1, ["Ruby", "Moe", "Dee"][i])
		state.team[i + 1]["points"] = 1000 * (3 - i)
	state.set_player_level(1, 12, 12)
	state.set_player_level(2, 30, 31)
	state.set_player_level(3, 8, 8)
	state.team[3]["bot"] = true
	var board := HudEndBoard.new()
	_host().add_child(board)
	board.show_results(state, "BACK IN", "Leave")
	assert_array(board.row_levels).is_equal([12, 30, 0])
	assert_int(_icons_in(board)).is_equal(2)
	assert_str(board.rows_text[2][0]).is_equal("DEE BOT")
	state.show_levels = false
	board.refresh(state)
	assert_array(board.row_levels).is_equal([0, 0, 0])


func test_the_lobby_list_shows_the_level_of_each_member_and_not_of_a_bot() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	var host := LobbyFixture.member("a", "Ann", 1, true)
	host["level"] = 12
	host["icon"] = "level_12"
	var guest := LobbyFixture.member("b", "Bo", 2)
	guest["level"] = 1
	guest["icon"] = "level_01"
	api.lobby = LobbyFixture.lobby([host, guest])
	await RouterFixture.clear(get_tree())
	LobbyScreen.opener = func() -> void: pass
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"lobby": api.lobby, "api": api}
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	assert_array(screen.seat_levels()).is_equal([12, 1, 0, 0])
	# The words of a seat are what they were: the icon and the level are beside them.
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  (open)", "4  (open)"])
	screen.free()


## The level icons a roster draws (its icon rectangles).
func _icons_in(node: Node) -> int:
	var count := 0
	if node is TextureRect and (node as TextureRect).texture is AtlasTexture:
		count += 1
	for child in node.get_children():
		count += _icons_in(child)
	return count
