extends GdUnitTestSuite
## The board of the end of a night (`HudEndBoard`, docs/design/end-of-night.md): one row for every
## player with the server's counts, the most points first; a player who leaves keeps their row;
## the round reached and the intermission's clock; and, with the fullest night the game allows,
## inside the canvas at every size a phone or a desktop gives.

const CANVASES: Array[Vector2] = [
	Vector2(1536.0, 864.0),
	Vector2(1920.0, 1080.0),
	Vector2(2340.0, 1080.0),
	Vector2(2560.0, 1080.0),
]
const PHONE_INSETS := Vector4(96.0, 0.0, 96.0, 24.0)
const NAMES := ["Ruby", "Moe", "Dee", "Cal", "Ned", "Ivy", "Sal", "Pat"]


func _host(canvas: Vector2) -> Control:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	return host


## A state with `players` players who each have different counts (the first is the local one).
func _state(players: int) -> HudState:
	var state := HudState.new()
	state.local_player_id = 1
	for i in players:
		var id := i + 1
		state.set_player_name(id, NAMES[i])
		state.set_player_stats(id, 10 * id, id % 3, HudState.NO_PING, id % 2)
		state.set_player_tally(id, 2 * id, 4 + id)
		# Points are set by the rules' events in a night; the entry is what the board reads.
		state.team[id]["points"] = 1000 * (players - i) if i != 1 else 99999
	state.round_number = 9
	state.night_clock = 725
	return state


func test_a_row_for_every_player_in_order_of_points_with_the_servers_counts() -> void:
	var state := _state(3)
	var board := HudEndBoard.new()
	_host(Vector2(1920.0, 1080.0)).add_child(board)
	board.show_results(state, "BACK IN", "Leave")
	assert_array(board.headings).is_equal(
		["PLAYER", "POINTS", "KILLS", "HEADSHOTS", "DOWNS", "REVIVES", "ROUNDS"]
	)
	# Moe has the most points (99999), then Ruby (3000), then Dee (1000).
	assert_array(board.row_ids).is_equal([2, 1, 3])
	assert_array(board.rows_text[0]).is_equal(["MOE", "99999", "20", "4", "2", "0", "6"])
	assert_array(board.rows_text[1]).is_equal(["RUBY", "3000", "10", "2", "1", "1", "5"])
	assert_array(board.rows_text[2]).is_equal(["DEE", "1000", "30", "6", "0", "1", "7"])
	assert_str(board.round_text).is_equal("ROUND 9 REACHED  ·  12:05")
	assert_str(board.title_text).is_equal("YOU DID NOT MAKE IT")


func test_a_player_who_leaves_keeps_their_row_and_a_later_count_replaces_it() -> void:
	var state := _state(3)
	var board := HudEndBoard.new()
	_host(Vector2(1920.0, 1080.0)).add_child(board)
	board.show_results(state, "BACK IN", "Leave")
	state.team.erase(3)
	state.team[1]["kills"] = 77
	board.refresh(state)
	assert_array(board.row_ids).contains_exactly([2, 1, 3])
	var ruby: Array = board.rows_text[board.row_ids.find(1)]
	assert_str(ruby[2]).is_equal("77")
	var dee: Array = board.rows_text[board.row_ids.find(3)]
	assert_str(dee[2]).is_equal("30")


func test_the_clock_shows_the_servers_whole_seconds_and_then_a_waiting_line() -> void:
	var board := HudEndBoard.new()
	_host(Vector2(1920.0, 1080.0)).add_child(board)
	board.show_results(_state(2), "BACK IN", "Leave")
	board.set_left(15)
	assert_str(board.countdown_text).is_equal("15")
	board.set_left(1)
	assert_str(board.countdown_text).is_equal("1")
	board.set_left(-1)
	assert_str(board.countdown_text).is_equal("")
	board.set_waiting("OPENING THE LOBBY")
	assert_str(board.countdown_text).is_equal("OPENING THE LOBBY")


func test_the_way_out_is_pressed_by_a_key_a_pad_and_a_tap() -> void:
	var board := HudEndBoard.new()
	_host(Vector2(1920.0, 1080.0)).add_child(board)
	board.show_results(_state(2), "BACK IN", "Leave")
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(board.leave_button.has_focus()).is_true()
	var pressed := [0]
	board.leave_pressed.connect(func() -> void: pressed[0] += 1)
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	board.leave_button.gui_input.emit(accept)
	board.leave_button.pressed.emit()
	assert_int(pressed[0]).is_equal(1)
	assert_str(board.leave_button.text).is_equal("Leave")


func test_the_fullest_night_fits_every_canvas_and_a_phone_with_its_notch() -> void:
	for canvas in CANVASES:
		for insets: Vector4 in [Vector4.ZERO, PHONE_INSETS]:
			var state := _state(NightHost.MAX_PLAYERS)
			# The longest name the game allows, the biggest numbers it can show.
			state.team[3]["name"] = "W".repeat(HudStyle.NAME_LIMIT)
			state.team[4]["points"] = 9999999
			state.team[4]["kills"] = 99999
			var board := HudEndBoard.new()
			var host := _host(canvas)
			host.add_child(board)
			board.set_safe_insets(insets)
			board.show_results(state, "BACK TO THE LOBBY IN", "Leave")
			board.set_left(15)
			await await_idle_frame()
			await await_idle_frame()
			await await_idle_frame()
			var rect := Rect2(Vector2.ZERO, canvas)
			var found: Array[Control] = []
			for control in board.find_children("*", "HudTicket", true, false):
				# The night report's ticket is the left column's own (`test_night_report_card.gd`).
				if control != board.report_card:
					found.append(control as Control)
			assert_int(found.size()).is_equal(1)
			var inside := rect.grow_individual(-insets.x, -insets.y, -insets.z, -insets.w)
			var seen := found[0].get_global_rect()
			(
				assert_bool(inside.encloses(seen))
				. override_failure_message(
					"%s with insets %s: the ticket %s leaves %s" % [canvas, insets, seen, inside]
				)
				. is_true()
			)
			var button := board.leave_button.get_global_rect()
			(
				assert_bool(inside.encloses(button))
				. override_failure_message(
					"%s with insets %s: Leave %s leaves %s" % [canvas, insets, button, inside]
				)
				. is_true()
			)
			(
				assert_bool(seen.intersects(button))
				. override_failure_message("%s: Leave %s on the ticket %s" % [canvas, button, seen])
				. is_false()
			)
			assert_int(board.row_ids.size()).is_equal(NightHost.MAX_PLAYERS)
			# The rows shrink on a short canvas, never past the least a row may be.
			assert_float(board.row_height()).is_between(
				HudEndBoard.MIN_ROW_HEIGHT, HudEndBoard.ROW_HEIGHT
			)
