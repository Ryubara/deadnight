extends GdUnitTestSuite
## The scoreboard: shown while the key, the pad's Back button or the touch button is held and gone
## when it is let go; one row for each player with the server's numbers; a ping column only when a
## night has pings; and, with the longest content the game allows, inside the canvas at every size
## a phone or a desktop gives, with no text cut.

const CANVASES: Array[Vector2] = [
	Vector2(1536.0, 864.0),
	Vector2(1920.0, 1080.0),
	Vector2(2340.0, 1080.0),
	Vector2(2400.0, 1080.0),
	Vector2(2560.0, 1080.0),
]
## A notch on each side and the home bar, as a phone in landscape has.
const PHONE_INSETS := Vector4(96.0, 0.0, 96.0, 24.0)


func before_test() -> void:
	UIMotion.reduced = false
	_release_all()


func after_test() -> void:
	_release_all()


func _release_all() -> void:
	Input.action_release(Hud.SCOREBOARD_ACTION)
	Input.flush_buffered_events()


func _hud(players := 2, canvas := Vector2(1920.0, 1080.0)) -> HudFixture:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	var fixture := HudFixture.make(host, players)
	fixture.into_round_one()
	return fixture


func _key(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_TAB
	event.pressed = pressed
	return event


## Sends an event as the engine would and lets the HUD see its frame (events are buffered to the
## frame's start, and the HUD reads the action in its process).
func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await await_idle_frame()
	await await_idle_frame()


func test_it_is_hidden_until_tab_is_held_and_gone_when_it_is_let_go() -> void:
	var fixture := _hud()
	var board := fixture.hud.scoreboard
	await await_idle_frame()
	assert_bool(board.visible).is_false()
	await _send(_key(true))
	assert_bool(board.visible).is_true()
	await await_idle_frame()
	assert_bool(board.visible).is_true()
	await _send(_key(false))
	assert_bool(board.visible).is_false()


func test_the_pads_back_button_holds_it_too_from_any_pad() -> void:
	var fixture := _hud()
	for device in [0, 3]:
		var press := InputEventJoypadButton.new()
		press.device = device
		press.button_index = JOY_BUTTON_BACK
		press.pressed = true
		await _send(press)
		assert_bool(fixture.hud.scoreboard.visible).override_failure_message(str(device)).is_true()
		var lift := press.duplicate() as InputEventJoypadButton
		lift.pressed = false
		await _send(lift)
		assert_bool(fixture.hud.scoreboard.visible).is_false()


func test_a_held_action_shows_it_whatever_pressed_it() -> void:
	# The touch button presses the action without any event: the board reads the action itself.
	var fixture := _hud()
	Input.action_press(Hud.SCOREBOARD_ACTION)
	await await_idle_frame()
	assert_bool(fixture.hud.scoreboard.visible).is_true()
	Input.action_release(Hud.SCOREBOARD_ACTION)
	await await_idle_frame()
	assert_bool(fixture.hud.scoreboard.visible).is_false()


func test_a_menu_over_the_night_keeps_it_away_and_takes_it_down() -> void:
	var fixture := _hud()
	var hud := fixture.hud
	Input.action_press(Hud.SCOREBOARD_ACTION)
	await await_idle_frame()
	assert_bool(hud.scoreboard.visible).is_true()
	hud.scoreboard_enabled = false
	assert_bool(hud.scoreboard.visible).is_false()
	await await_idle_frame()
	assert_bool(hud.scoreboard.visible).is_false()
	hud.scoreboard_enabled = true
	await await_idle_frame()
	assert_bool(hud.scoreboard.visible).is_true()


func test_a_row_for_each_player_with_the_servers_numbers() -> void:
	var fixture := _hud(3)
	var state := fixture.hud.state
	state.set_player_stats(1, 12, 1, HudState.NO_PING, 2)
	state.set_player_stats(2, 7, 0)
	state.set_player_stats(3, 31, 4, HudState.NO_PING, 9)
	state.set_night_clock(754)
	fixture.act(RulesAction.grant_points(1, 250))
	var board := fixture.hud.scoreboard
	board.set_shown(true)
	assert_array(board.row_ids).is_equal([1, 2, 3])
	assert_array(board.headings).is_equal(["PLAYER", "KILLS", "DOWNS", "REVIVES", "POINTS"])
	assert_str(board.rows_text[0][0]).is_equal("RUBY")
	assert_str(board.rows_text[0][1]).is_equal("12")
	assert_str(board.rows_text[0][2]).is_equal("1")
	assert_str(board.rows_text[0][3]).is_equal("2")
	assert_str(board.rows_text[0][4]).is_equal(str(fixture.rules.points_of(1)))
	assert_str(board.rows_text[1][3]).is_equal("0")
	assert_str(board.rows_text[2][0]).is_equal("DEE")
	assert_str(board.rows_text[2][1]).is_equal("31")
	assert_str(board.rows_text[2][2]).is_equal("4")
	assert_str(board.rows_text[2][3]).is_equal("9")
	assert_str(board.round_text).is_equal("ROUND 01")
	assert_str(board.clock_text).is_equal("TIME 12:34")


func test_the_numbers_change_while_it_is_up() -> void:
	var fixture := _hud()
	var board := fixture.hud.scoreboard
	board.set_shown(true)
	assert_str(board.rows_text[1][1]).is_equal("0")
	fixture.hud.state.set_player_stats(2, 5, 0)
	assert_str(board.rows_text[1][1]).is_equal("5")
	fixture.hud.state.set_night_clock(61)
	assert_str(board.clock_text).is_equal("TIME 1:01")
	# A change heard while it is hidden is there when it comes up.
	board.set_shown(false)
	fixture.hud.state.set_player_stats(2, 6, 1)
	board.set_shown(true)
	assert_str(board.rows_text[1][1]).is_equal("6")
	assert_str(board.rows_text[1][2]).is_equal("1")


func test_a_player_who_leaves_goes_off_the_board() -> void:
	var fixture := _hud(3)
	var board := fixture.hud.scoreboard
	board.set_shown(true)
	assert_int(board.rows_text.size()).is_equal(3)
	fixture.act(RulesAction.remove_player(2))
	assert_array(board.row_ids).is_equal([1, 3])


func test_a_downed_player_is_marked_in_words_as_well_as_in_red() -> void:
	var fixture := _hud(2)
	fixture.act(RulesAction.blow(2, 99999.0))
	var board := fixture.hud.scoreboard
	board.set_shown(true)
	assert_str(board.rows_text[1][0]).is_equal("MOE  (DOWN)")
	assert_str(board.rows_text[0][0]).is_equal("RUBY")


func test_the_ping_column_is_there_only_when_someone_has_a_ping() -> void:
	var fixture := _hud(2)
	var state := fixture.hud.state
	var board := fixture.hud.scoreboard
	board.set_shown(true)
	assert_bool(board.has_ping).is_false()
	assert_int(board.rows_text[0].size()).is_equal(5)
	state.set_player_stats(1, 0, 0, 38)
	assert_bool(board.has_ping).is_true()
	assert_array(board.headings).is_equal(["PLAYER", "KILLS", "DOWNS", "REVIVES", "POINTS", "PING"])
	assert_str(board.rows_text[0][HudScoreboard.PING_CELL]).is_equal("38")
	# A player the server has not heard from yet shows a dash, not a made-up number.
	assert_str(board.rows_text[1][HudScoreboard.PING_CELL]).is_equal("-")
	state.set_player_stats(1, 0, 0, HudState.NO_PING)
	assert_bool(board.has_ping).is_false()


func test_a_player_who_bled_out_is_marked_dead_and_the_revives_are_the_servers() -> void:
	var fixture := _hud(3)
	var state := fixture.hud.state
	fixture.act(RulesAction.blow(2, 99999.0))
	fixture.act(RulesAction.blow(3, 99999.0))
	state.apply_event({"type": &"player_died", "player_id": 3, "cause": &"bleed_out"})
	var board := fixture.hud.scoreboard
	board.set_shown(true)
	assert_str(board.rows_text[1][0]).is_equal("MOE  (DOWN)")
	assert_str(board.rows_text[2][0]).is_equal("DEE  (DEAD)")
	# The count is the server's whole number, not a tally of the events heard.
	state.set_player_stats(1, 0, 0, HudState.NO_PING, 3)
	assert_str(board.rows_text[0][3]).is_equal("3")
	state.set_player_stats(1, 0, 0, HudState.NO_PING, 3)
	assert_str(board.rows_text[0][3]).is_equal("3")


func test_a_ping_reads_good_fair_or_bad() -> void:
	assert_int(HudScoreboard.ping_grade(0)).is_equal(0)
	assert_int(HudScoreboard.ping_grade(HudScoreboard.PING_GOOD_MS)).is_equal(0)
	assert_int(HudScoreboard.ping_grade(HudScoreboard.PING_GOOD_MS + 1)).is_equal(1)
	assert_int(HudScoreboard.ping_grade(HudScoreboard.PING_FAIR_MS)).is_equal(1)
	assert_int(HudScoreboard.ping_grade(HudScoreboard.PING_FAIR_MS + 1)).is_equal(2)


func test_the_clock_reads_minutes_and_after_an_hour_hours() -> void:
	assert_str(HudScoreboard.format_clock(0)).is_equal("0:00")
	assert_str(HudScoreboard.format_clock(9)).is_equal("0:09")
	assert_str(HudScoreboard.format_clock(754)).is_equal("12:34")
	assert_str(HudScoreboard.format_clock(3599)).is_equal("59:59")
	assert_str(HudScoreboard.format_clock(3600)).is_equal("1:00:00")
	assert_str(HudScoreboard.format_clock(7325)).is_equal("2:02:05")
	assert_str(HudScoreboard.format_clock(-5)).is_equal("0:00")


func test_a_snapshot_gives_a_late_hud_the_counts_and_the_clock() -> void:
	var fixture := _hud(2)
	fixture.act(RulesAction.blow(2, 99999.0))
	fixture.rules.night_time = 95.5
	fixture.rules.players[1].kills = 9
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920.0, 1080.0)
	add_child(host)
	var late := HudFixture.make(host, 1)
	late.hud.state.load_snapshot(fixture.rules.to_dict())
	late.hud.scoreboard.set_shown(true)
	assert_str(late.hud.scoreboard.rows_text[0][1]).is_equal("9")
	assert_str(late.hud.scoreboard.rows_text[1][2]).is_equal("1")
	assert_str(late.hud.scoreboard.clock_text).is_equal("TIME 1:35")


## The longest content the game allows: four names of the limit's length, the biggest counts,
## points and pings, a three-digit round and an hour on the clock.
func _fill_worst_case(fixture: HudFixture) -> void:
	var state := fixture.hud.state
	var names := [
		"Maximiliana Rosewood",
		"Bartholomew Okonkwo",
		"Wolfgang Amadeus Zed",
		"Persephone Q-Laneway"
	]
	for i in 4:
		state.set_player_name(i + 1, names[i])
		state.set_player_stats(i + 1, 99999, 9999, 999)
		state.apply_event(
			{"type": &"points_changed", "player_id": i + 1, "total": 99999999, "delta": 0}
		)
	state.apply_event({"type": &"round_started", "round": 123, "zombie_count": 999})
	state.set_night_clock(3600 * 3 + 59 * 60 + 59)
	fixture.act(RulesAction.set_downed(2, true))


func test_the_fullest_board_fits_every_canvas_with_no_text_cut() -> void:
	for canvas in CANVASES:
		var fixture := _hud(4, canvas)
		_fill_worst_case(fixture)
		fixture.hud.offset_left = PHONE_INSETS.x if canvas.x > 2000.0 else 0.0
		fixture.hud.offset_right = -PHONE_INSETS.z if canvas.x > 2000.0 else 0.0
		var board := fixture.hud.scoreboard
		board.set_shown(true)
		await await_idle_frame()
		await await_idle_frame()
		var safe := Rect2(Vector2.ZERO, canvas)
		if canvas.x > 2000.0:
			safe = Rect2(Vector2(PHONE_INSETS.x, 0.0), canvas - Vector2(PHONE_INSETS.x * 2.0, 0.0))
		var rect := board.get_global_rect()
		(
			assert_bool(safe.encloses(rect))
			. override_failure_message("the board %s leaves %s on %s" % [rect, safe, canvas])
			. is_true()
		)
		(
			assert_float(rect.get_center().x)
			. override_failure_message("not centred on %s" % canvas)
			. is_equal_approx(safe.get_center().x, 2.0)
		)
		_assert_nothing_cut(board)
		_assert_rows_do_not_overlap(board, canvas)


func _labels(node: Node, found: Array[Label] = []) -> Array[Label]:
	for child in node.get_children():
		if child is Label:
			found.append(child)
		_labels(child, found)
	return found


func _assert_nothing_cut(board: HudScoreboard) -> void:
	var smallest := 999
	for label in _labels(board):
		var font := label.get_theme_font(&"font")
		var size_px := label.get_theme_font_size(&"font_size")
		smallest = mini(smallest, size_px)
		var wide := HudStyle.text_width(font, label.text, size_px)
		(
			assert_float(wide)
			. override_failure_message("%s is %.0f wide in %.0f" % [label.text, wide, label.size.x])
			. is_less_equal(label.size.x + 1.0)
		)
	assert_int(smallest).is_greater_equal(HudStyle.MIN_TEXT)


func _assert_rows_do_not_overlap(board: HudScoreboard, canvas: Vector2) -> void:
	var rects: Array[Rect2] = []
	for label in _labels(board):
		rects.append(label.get_global_rect())
	for i in rects.size():
		(
			assert_bool(Rect2(Vector2.ZERO, canvas).encloses(rects[i]))
			. override_failure_message("a label leaves the canvas: %s" % rects[i])
			. is_true()
		)
		for j in range(i + 1, rects.size()):
			(
				assert_bool(rects[i].grow(-1.0).intersects(rects[j].grow(-1.0)))
				. override_failure_message("two labels overlap: %s and %s" % [rects[i], rects[j]])
				. is_false()
			)
