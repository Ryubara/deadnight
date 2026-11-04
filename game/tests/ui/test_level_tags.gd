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
	Input.action_release(Hud.SCOREBOARD_ACTION)
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


func test_a_tag_is_icon_then_level_then_name_with_the_two_gaps_and_a_bot_is_the_name_alone(
) -> void:
	var fixture := HudFixture.make(_host(), 1)
	var state := _state(fixture.hud.state)
	state.set_player_level(2, 7, 7)
	var markers := fixture.hud.markers
	# The same words, one with a level and one without (a bot's marker has none).
	var list: Array[Dictionary] = [
		_ally(2, 0.5, state, "Moe"),
		_ally(3, 0.3, state, "Moe"),
	]
	state.set_markers(list)
	await await_idle_frame()
	var parts: Dictionary = markers.tag_parts[&"player_2"]
	var icon: Rect2 = parts["icon"]
	var level: Rect2 = parts["level"]
	var who: Rect2 = parts["name"]
	# Left to right: the icon, the level right beside it, then the name.
	assert_float(icon.end.x).is_less(level.position.x)
	assert_float(level.end.x).is_less(who.position.x)
	# The two gaps are the shared values, measured on the laid-out rectangles.
	assert_float(level.position.x - icon.end.x).is_equal_approx(LevelTag.ICON_GAP, 0.01)
	assert_float(who.position.x - level.end.x).is_equal_approx(LevelTag.NAME_GAP, 0.01)
	assert_float(LevelTag.NAME_GAP).is_greater(LevelTag.ICON_GAP * 2.0)
	assert_vector(icon.size).is_equal(Vector2.ONE * LevelTag.ICON)
	# The whole tag is centred where it always was (on the marker), and a short level is as close
	# to its icon as a long one.
	var at: Vector2 = markers.placed[&"player_2"]["at"]
	assert_float((markers.tags[&"player_2"] as Rect2).get_center().x).is_equal_approx(at.x, 0.5)
	state.set_player_level(2, 55, 55)
	state.set_markers(list)
	await await_idle_frame()
	var wide: Dictionary = markers.tag_parts[&"player_2"]
	(
		assert_float((wide["level"] as Rect2).position.x - (wide["icon"] as Rect2).end.x)
		. is_equal_approx(LevelTag.ICON_GAP, 0.01)
	)
	(
		assert_float((wide["name"] as Rect2).position.x - (wide["level"] as Rect2).end.x)
		. is_equal_approx(LevelTag.NAME_GAP, 0.01)
	)
	# No level: the name alone, centred on the marker, with no icon, no level and no gap.
	assert_bool(markers.tag_parts.has(&"player_3")).is_false()
	var bare: Rect2 = markers.tags[&"player_3"]
	var bare_at: Vector2 = markers.placed[&"player_3"]["at"]
	assert_float(bare.get_center().x).is_equal_approx(bare_at.x, 0.5)
	assert_float(bare.size.x).is_less((markers.tags[&"player_2"] as Rect2).size.x - LevelTag.ICON)
	assert_dict(markers.placed).contains_keys([&"player_2", &"player_3"])


func test_the_clock_of_a_body_on_the_ground_follows_the_name() -> void:
	var fixture := HudFixture.make(_host(), 1)
	var state := _state(fixture.hud.state)
	state.set_markers(
		[_ally(2, 0.5, state, "Moe", {"downed": true, "bleed": 31, "important": true})]
	)
	await await_idle_frame()
	var parts: Dictionary = fixture.hud.markers.tag_parts[&"player_2"]
	assert_float((parts["icon"] as Rect2).end.x).is_less((parts["level"] as Rect2).position.x)
	assert_float((parts["level"] as Rect2).end.x).is_less((parts["name"] as Rect2).position.x)
	var tag: Rect2 = fixture.hud.markers.tags[&"player_2"]
	assert_float((parts["name"] as Rect2).end.x).is_equal_approx(tag.end.x, 0.01)


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


func test_the_scoreboard_is_icon_level_name_with_the_two_gaps_and_two_digits_whole() -> void:
	var fixture := HudFixture.make(_host(), 4)
	var state := fixture.hud.state
	state.set_player_level(1, 12, 12)
	state.set_player_level(2, 30, 31)
	state.set_player_level(3, 55, 55)
	# Player 4 is a bot beside people.
	state.team[4]["bot"] = true
	var board := fixture.hud.scoreboard
	# Held up the way a player holds it: the HUD hides the board when the key is not down.
	Input.action_press(Hud.SCOREBOARD_ACTION)
	board.set_shown(true)
	board.refresh()
	await await_idle_frame()
	await await_idle_frame()
	assert_array(board.row_levels).is_equal([12, 30, 55, 0])
	# The cells are what they were: the name is the name, the icon and the level are beside it.
	assert_str(board.rows_text[0][0]).is_equal("RUBY")
	assert_int(_icons_in(board)).is_equal(3)
	_assert_rows_in_order(board, ["12", "30", "55"])
	# Every level is written whole in the room it has (a two-digit level was cut to one digit).
	for label: Label in board.find_children("Level", "Label", true, false):
		var width := HudStyle.text_width(
			label.get_theme_font(&"font"), label.text, label.get_theme_font_size(&"font_size")
		)
		assert_float(width).is_less_equal(label.size.x)
		assert_str(label.text).has_length(2)
	_assert_bare_name_starts_with_the_badge(board, board.rows_text[3][0])
	# The viewer turns levels off: no icon, no level, no gap, no room kept for them.
	state.show_levels = false
	board.refresh()
	await await_idle_frame()
	assert_array(board.row_levels).is_equal([0, 0, 0, 0])
	assert_int(_icons_in(board)).is_equal(0)
	assert_int(board.find_children("Level", "Label", true, false).size()).is_equal(0)


func test_the_night_report_is_icon_level_name_and_a_bot_is_the_name_alone() -> void:
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
	var host := _host()
	host.add_child(board)
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.show_results(state, "BACK IN", "Leave")
	await await_idle_frame()
	await await_idle_frame()
	assert_array(board.row_levels).is_equal([12, 30, 0])
	assert_int(_icons_in(board)).is_equal(2)
	assert_str(board.rows_text[2][0]).is_equal("DEE BOT")
	_assert_rows_in_order(board, ["12", "30"])
	_assert_bare_name_starts_with_the_badge(board, board.rows_text[2][0])
	state.show_levels = false
	board.refresh(state)
	assert_array(board.row_levels).is_equal([0, 0, 0])


func test_the_lobby_list_is_icon_level_name_and_a_bot_or_an_open_seat_is_the_name_alone() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	var host := LobbyFixture.member("a", "Ann", 1, true)
	host["level"] = 12
	host["icon"] = "level_12"
	var guest := LobbyFixture.member("b", "Bo", 2)
	guest["level"] = 7
	guest["icon"] = "level_07"
	var third := LobbyFixture.member("c", "Cy", 3)
	third["level"] = 55
	third["icon"] = "level_55"
	api.lobby = LobbyFixture.lobby([host, guest, third])
	await RouterFixture.clear(get_tree())
	LobbyScreen.opener = func() -> void: pass
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"lobby": api.lobby, "api": api}
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	await await_idle_frame()
	await await_idle_frame()
	assert_array(screen.seat_levels()).is_equal([12, 7, 55, 0])
	# The words of a seat are what they were: the icon and the level are beside them.
	assert_array(screen.seat_texts()).is_equal(["1  Ann  HOST", "2  Bo", "3  Cy", "4  (open)"])
	_assert_rows_in_order(screen, ["12", "7", "55"])
	# The names of the people start on one line, whatever their level's digits.
	var starts: Array[float] = []
	for label: Label in screen.find_children("Name", "Label", true, false):
		if (
			label.get_parent().name == &"Who"
			and (label.get_parent().get_child(0) as Control).visible
		):
			starts.append(label.global_position.x)
	assert_array(starts).has_size(3)
	assert_float(starts[1]).is_equal_approx(starts[0], 0.01)
	assert_float(starts[2]).is_equal_approx(starts[0], 0.01)
	# A seat with no level has its name right after the seat number, with no gap kept for a badge.
	var open_row := screen.find_children("Who", "HBoxContainer", true, false)[3] as Control
	assert_bool(open_row.get_child(0).visible).is_false()
	var open_name := open_row.get_child(1) as Control
	assert_float(open_name.global_position.x).is_equal_approx(open_row.global_position.x, 0.01)
	screen.free()


# --- The player boxes at the bottom left ---


## A party of `players` whose first four have levels 12, 7, 55 and 30 (the bots' none), points set.
func _boxes(players: int, bots := 0) -> HudFixture:
	var fixture := HudFixture.make(_host(), players)
	fixture.into_round_one()
	var state := fixture.hud.state
	var levels := [12, 7, 55, 30, 41, 9, 23, 18]
	for i in players:
		state.apply_event(
			{"type": &"points_changed", "player_id": i + 1, "total": 1000 * (i + 1), "delta": 0}
		)
		state.set_player_level(i + 1, levels[i], levels[i])
		if i >= players - bots:
			state.team[i + 1]["bot"] = true
	fixture.hud.points.refresh()
	return fixture


## A box's icon, level and name in the order and with the gaps of `LevelTag`, inside its own box.
func _assert_box_in_order(box: HudPlayerBox, label: String) -> void:
	var parts: Dictionary = box.badge_parts
	assert_bool(parts.is_empty()).override_failure_message("%s has no badge" % label).is_false()
	var icon: Rect2 = parts["icon"]
	var level: Rect2 = parts["level"]
	var who: Rect2 = parts["name"]
	var body := Rect2(Vector2.ZERO, box.size)
	assert_float(icon.size.x).is_equal_approx(LevelTag.ICON, 0.01)
	assert_float(icon.end.x).is_less(level.position.x)
	assert_float(level.end.x).is_less(who.position.x)
	(
		assert_float(level.position.x - icon.end.x)
		. override_failure_message(label + ": icon to level")
		. is_equal_approx(LevelTag.ICON_GAP, 0.01)
	)
	(
		assert_float(who.position.x - level.end.x)
		. override_failure_message(label + ": level to name")
		. is_equal_approx(LevelTag.NAME_GAP, 0.01)
	)
	# The icon sits whole in the box, centred high to low; the name ends before the number.
	assert_bool(body.encloses(icon)).override_failure_message(label + ": icon outside").is_true()
	assert_float(icon.get_center().y).is_equal_approx(box.size.y * 0.5, 0.01)
	assert_float(who.end.x).is_less_equal(box.number_right())
	assert_float(who.size.x).is_greater(0.0)


func test_every_player_box_is_icon_level_name_in_all_three_sizes() -> void:
	# A party of four: your own box (66) and teammates' (48); eight: the compact size (32).
	for players in [4, NightHost.MAX_PLAYERS]:
		var fixture := _boxes(players)
		await await_idle_frame()
		await await_idle_frame()
		var points := fixture.hud.points
		var expected: Array[float] = [HudPlayerBox.LOCAL_HEIGHT]
		expected.append(HudPlayerBox.OTHER_HEIGHT if players == 4 else HudPlayerBox.COMPACT_HEIGHT)
		assert_float(points.box_of(1).size.y).is_equal(expected[0])
		assert_float(points.box_of(2).size.y).is_equal(expected[1])
		for id in range(1, players + 1):
			var box := points.box_of(id)
			_assert_box_in_order(box, "%d players, box %d" % [players, id])
			# The level is whole: its room is two digits wide and the box says the level it shows.
			assert_int(box.shown_level.x).is_greater(0)
			assert_float((box.badge_parts["level"] as Rect2).size.x).is_greater(0.0)
		fixture.hud.get_parent().remove_child(fixture.hud)
		fixture.hud.free()


func test_a_box_without_a_level_is_the_name_alone_and_the_points_stay_on_one_line() -> void:
	for players in [4, NightHost.MAX_PLAYERS]:
		var fixture := _boxes(players, 1)
		await await_idle_frame()
		await await_idle_frame()
		var points := fixture.hud.points
		var bot := points.box_of(players)
		var person := points.box_of(players - 1)
		assert_bool(bot.badge_parts.is_empty()).is_true()
		assert_vector(bot.shown_level).is_equal(Vector2i.ZERO)
		# The name starts where the badge would: no gap kept in front of it.
		var left := (
			HudPlayerBox.height_for(false, players > HudPoints.COMPACT_FROM)
			+ HudPlayerBox.SPLIT
			+ HudPlayerBox.PADDING
		)
		assert_float(bot.name_rect().position.x).is_equal_approx(left, 0.01)
		assert_float((person.badge_parts["icon"] as Rect2).position.x).is_equal_approx(left, 0.01)
		# The numbers of boxes of one size end on one vertical line, with or without a level.
		assert_float(bot.number_right()).is_equal_approx(person.number_right(), 0.01)
		fixture.hud.get_parent().remove_child(fixture.hud)
		fixture.hud.free()
	# Levels turned off: every box is the name alone.
	var off := _boxes(3)
	off.hud.state.show_levels = false
	await await_idle_frame()
	for id in 3:
		assert_bool(off.hud.points.box_of(id + 1).badge_parts.is_empty()).is_true()
	off.hud.get_parent().remove_child(off.hud)
	off.hud.free()


func test_a_long_name_ends_in_an_ellipsis_before_the_badge_or_the_points_are_cut() -> void:
	for players in [4, NightHost.MAX_PLAYERS]:
		var fixture := _boxes(players)
		var state := fixture.hud.state
		var long_name := "A".repeat(HudStyle.NAME_LIMIT)
		state.set_player_name(2, long_name)
		state.apply_event({"type": &"points_changed", "player_id": 2, "total": 987654, "delta": 0})
		await await_idle_frame()
		await await_idle_frame()
		var box := fixture.hud.points.box_of(2)
		_assert_box_in_order(box, "%d players, long name" % players)
		# The badge and the points keep their room, whole; the name takes what is left.
		assert_float(box.number_width()).is_less_equal(box.number_size().x + 0.5)
		var short := fixture.hud.points.box_of(3)
		assert_float((box.badge_parts["level"] as Rect2).size.x).is_equal_approx(
			(short.badge_parts["level"] as Rect2).size.x, 0.01
		)
		assert_float(box.name_rect().size.x).is_less(short.name_rect().size.x + box.number_size().x)
		fixture.hud.get_parent().remove_child(fixture.hud)
		fixture.hud.free()


func test_a_downed_box_keeps_its_badge_and_says_down() -> void:
	for players in [4, NightHost.MAX_PLAYERS]:
		var fixture := _boxes(players)
		fixture.hud.state.team[2]["downed"] = true
		fixture.hud.points.refresh()
		await await_idle_frame()
		await await_idle_frame()
		var box := fixture.hud.points.box_of(2)
		assert_str(box.name_text).is_equal("DOWN")
		_assert_box_in_order(box, "%d players, downed" % players)
		fixture.hud.get_parent().remove_child(fixture.hud)
		fixture.hud.free()


## Each row with a level: the icon, then the level, then the name, from the laid-out rectangles,
## with `ICON_GAP` after the icon and `NAME_GAP` after the level's room. `levels` are the texts.
func _assert_rows_in_order(root: Node, levels: Array[String]) -> void:
	var icons := root.find_children("Icon", "TextureRect", true, false).filter(_on_screen)
	var shown := root.find_children("Level", "Label", true, false).filter(_on_screen)
	var names := root.find_children("Name", "Label", true, false)
	assert_int(shown.size()).is_equal(levels.size())
	assert_int(icons.size()).is_equal(levels.size())
	assert_int(names.size()).is_greater_equal(levels.size())
	for i in levels.size():
		var icon := _rect(icons[i])
		var level := _rect(shown[i])
		var who := _rect(names[i])
		assert_str((shown[i] as Label).text).is_equal(levels[i])
		assert_float(icon.size.x).is_equal_approx(LevelTag.ICON, 0.01)
		assert_float(icon.end.x).is_less(level.position.x)
		assert_float(level.end.x).is_less(who.position.x)
		assert_float(level.position.x - icon.end.x).is_equal_approx(LevelTag.ICON_GAP, 0.01)
		assert_float(who.position.x - level.end.x).is_equal_approx(LevelTag.NAME_GAP, 0.01)


## A row with no level is a name label of its own that starts where a badge starts (the cell's left
## edge): no gap kept in front of it. `words` is the text of that name.
func _assert_bare_name_starts_with_the_badge(root: Node, words: String) -> void:
	var badge := root.find_children("Badge", "HBoxContainer", true, false)[0] as Control
	var found := false
	for label: Label in root.find_children("*", "Label", true, false):
		if label.name != &"Name" and label.text == words:
			found = true
			assert_float(label.global_position.x).is_equal_approx(badge.global_position.x, 0.01)
	assert_bool(found).is_true()


func _on_screen(node: Node) -> bool:
	return (node as CanvasItem).is_visible_in_tree()


func _rect(node: Node) -> Rect2:
	var control := node as Control
	return Rect2(control.global_position, control.size)


## The level icons a roster draws (its icon rectangles).
func _icons_in(node: Node) -> int:
	var count := 0
	if node is TextureRect and (node as TextureRect).texture is AtlasTexture:
		count += 1
	for child in node.get_children():
		count += _icons_in(child)
	return count
