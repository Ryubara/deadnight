extends GdUnitTestSuite
## The film credits on the end board (`HudCredits`, `HudEndBoard.show_credits`,
## docs/design/progression.md#the-night-report-and-credits): a line for every player with the title
## they earned, what it was for, their name and the XP the night paid them; titled players first and
## the Extras after; a later call replaces them; and with one, four or eight players the credits
## stay inside the screen, clear of the players' ticket, the report, the title and the way out, at
## every canvas and on a phone with its notch.

const CANVASES: Array[Vector2] = [
	Vector2(1536.0, 864.0),
	Vector2(1920.0, 1080.0),
	Vector2(2340.0, 1080.0),
	Vector2(2560.0, 1080.0),
]
const PHONE_INSETS := Vector4(96.0, 0.0, 96.0, 24.0)
## The narrowest canvas a phone gives (2340 by 1080 is a common one).
const PHONE_MIN_WIDTH := 2000.0
const NAMES := ["Ruby", "Moe", "Dee", "Cal", "Ada", "Bo", "Cy", "Flo"]


func _host(canvas: Vector2) -> Control:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	return host


func _state(players: int) -> HudState:
	var state := HudState.new()
	state.local_player_id = 1
	for i in players:
		state.set_player_name(i + 1, NAMES[i % NAMES.size()])
		state.team[i + 1]["points"] = 1000 * (players - i)
	state.round_number = 7
	state.night_clock = 300
	return state


## Player n has the most of the nth title's stat, so every title is given while there are players.
func _night_input(players: int, xp: int = 1500) -> Dictionary:
	var list := CrewTitles.shipped()
	var counts := {}
	var told := {}
	for i in players:
		var mine := {}
		if i < list.titles.size():
			mine[list.titles[i]["stat"]] = 10 + i
		counts[i + 1] = mine
		told[i + 1] = xp
	return {"counts": counts, "xp": told}


func _board(canvas: Vector2, players: int, insets: Vector4 = Vector4.ZERO) -> HudEndBoard:
	var board := HudEndBoard.new()
	_host(canvas).add_child(board)
	board.set_safe_insets(insets)
	board.show_results(_state(players), "BACK TO THE LOBBY IN", "Leave")
	board.set_left(15)
	return board


func test_the_credits_are_hidden_until_they_are_given() -> void:
	var board := _board(Vector2(1920.0, 1080.0), 4)
	await await_idle_frame()
	assert_bool(board.credits_card.visible).is_false()
	board.show_credits(_night_input(4))
	await await_idle_frame()
	assert_bool(board.credits_card.visible).is_true()


func test_every_player_has_a_line_with_their_title_the_reason_and_their_xp() -> void:
	var board := _board(Vector2(1920.0, 1080.0), 4)
	var input := {
		"counts":
		{
			1: {ChallengeStats.BOARDS: 6},
			2: {ChallengeStats.FUEL_CANS: 3},
			3: {},
			4: {ChallengeStats.DOWNS: 2},
		},
		"xp": {1: 120, 2: 45},
	}
	board.show_credits(input)
	var card := board.credits_card
	assert_array(card.row_ids).is_equal([2, 1, 4, 3])
	(
		assert_array(card.rows_text)
		. is_equal(
			[
				["BEST BOY", "MOST FUEL CANS", "MOE", "+45 XP"],
				["KEY GRIP", "MOST BOARDS MENDED", "RUBY", "+120 XP"],
				["STUNT DOUBLE", "MOST TIMES DOWN", "CAL", ""],
				["EXTRA", "ON SET ALL NIGHT", "DEE", ""],
			]
		)
	)


func test_a_solo_night_has_its_credit() -> void:
	var board := _board(Vector2(1920.0, 1080.0), 1)
	board.show_credits({"counts": {1: {ChallengeStats.POINTS: 900}}, "xp": {1: 80}})
	assert_array(board.credits_card.rows_text).is_equal(
		[["EXECUTIVE PRODUCER", "MOST POINTS EARNED", "RUBY", "+80 XP"]]
	)


func test_a_player_who_left_keeps_their_credit() -> void:
	var state := _state(4)
	var board := HudEndBoard.new()
	_host(Vector2(1920.0, 1080.0)).add_child(board)
	board.show_results(state, "BACK", "Leave")
	state.team.erase(4)
	board.refresh(state)
	board.show_credits(_night_input(4))
	assert_int(board.credits_card.row_ids.size()).is_equal(4)


func test_a_later_call_replaces_the_credits() -> void:
	var board := _board(Vector2(1920.0, 1080.0), 2)
	board.show_credits({"counts": {1: {ChallengeStats.BOARDS: 1}}, "xp": {}})
	assert_str(board.credits_card.rows_text[0][0]).is_equal("KEY GRIP")
	board.show_credits({"counts": {2: {ChallengeStats.BOARDS: 5}}, "xp": {2: 30}})
	assert_array(board.credits_card.rows_text[0]).is_equal(
		["KEY GRIP", "MOST BOARDS MENDED", "MOE", "+30 XP"]
	)
	assert_int(board.credits_card.rows_text.size()).is_equal(2)


func test_the_credits_fit_every_canvas_and_a_phone_with_one_four_and_eight_players() -> void:
	var faults: Array[String] = []
	for canvas in CANVASES:
		for insets: Vector4 in [Vector4.ZERO, PHONE_INSETS]:
			if insets != Vector4.ZERO and canvas.x < PHONE_MIN_WIDTH:
				continue
			for players: int in [1, 4, NightHost.MAX_PLAYERS]:
				var board := _board(canvas, players, insets)
				board.show_report(_busy())
				board.show_credits(_night_input(players))
				await await_idle_frame()
				await await_idle_frame()
				await await_idle_frame()
				var where := "%s, insets %s, %d players" % [canvas, insets, players]
				faults.append_array(_faults(board, canvas, insets, players, where))
	assert_array(faults).is_empty()


## A busy night's report: four lines and the level bar (the fullest one the report can have is
## `test_night_report_card.gd`'s; on the smallest canvas that one is taller than the left column).
func _busy() -> Dictionary:
	var sources := {
		ChallengeStats.ROUND: 400 * XpRules.HUNDREDTHS / 10,
		ChallengeStats.POINTS: 1200,
		ChallengeStats.BOARDS: 600,
		XpAward.CHALLENGE: 2500,
	}
	var hundredths := 0
	for source: StringName in sources:
		hundredths += int(sources[source])
	return NightReport.compose(sources, XpRules.to_xp(hundredths), 40, true)


## What is wrong with the credits on `board`, in words.
func _faults(
	board: HudEndBoard, canvas: Vector2, insets: Vector4, players: int, where: String
) -> Array[String]:
	var faults: Array[String] = []
	var inside := Rect2(Vector2.ZERO, canvas).grow_individual(
		-insets.x, -insets.y, -insets.z, -insets.w
	)
	var card := board.credits_card
	var seen := card.get_global_rect()
	if not card.visible:
		return ["%s: the credits are not shown" % where]
	if card.rows_text.size() != players:
		faults.append("%s: %d lines for %d players" % [where, card.rows_text.size(), players])
	if not inside.encloses(seen):
		faults.append(
			(
				"%s: the credits %s leave %s (players %s, report %s, leave %s, board %s)"
				% [
					where,
					seen,
					inside,
					board._ticket.get_global_rect(),
					board.report_card.get_global_rect(),
					board.leave_button.get_global_rect(),
					board._margin.get_global_rect()
				]
			)
		)
	var tickets := {
		"the players": board._ticket.get_global_rect(),
		"the report": board.report_card.get_global_rect(),
		"Leave": board.leave_button.get_global_rect(),
		"the title": board._title.get_global_rect(),
		"the round": board._round_label.get_global_rect(),
	}
	for name: String in tickets:
		if seen.intersects(tickets[name]):
			faults.append("%s: the credits %s on %s %s" % [where, seen, name, tickets[name]])
	if not inside.encloses(board.leave_button.get_global_rect()):
		faults.append(
			"%s: Leave %s leaves %s" % [where, board.leave_button.get_global_rect(), inside]
		)
	var players_seen := board._ticket.get_global_rect()
	if not inside.encloses(players_seen):
		faults.append("%s: the players' ticket %s leaves %s" % [where, players_seen, inside])
	if card.row_height < HudCredits.MIN_ROW or card.row_height > HudCredits.ROW:
		faults.append("%s: a credit row of %s" % [where, card.row_height])
	for label in card.find_children("*", "Label", true, false):
		var text := label as Label
		if not seen.encloses(text.get_global_rect()):
			faults.append(
				(
					"%s: '%s' %s leaves the credits %s"
					% [where, text.text, text.get_global_rect(), seen]
				)
			)
	return faults


func test_the_rows_get_less_height_when_the_room_is_short_and_not_less_than_a_floor() -> void:
	var tall := _board(Vector2(1920.0, 1080.0), 2)
	tall.show_credits(_night_input(2))
	var short := _board(Vector2(1536.0, 864.0), NightHost.MAX_PLAYERS)
	short.show_credits(_night_input(NightHost.MAX_PLAYERS))
	assert_float(tall.credits_card.row_height).is_equal(HudCredits.ROW)
	assert_float(short.credits_card.row_height).is_less(HudCredits.ROW)
	assert_float(short.credits_card.row_height).is_greater_equal(HudCredits.MIN_ROW)


func test_the_two_tickets_split_the_height_by_their_rows_until_both_are_at_their_floor() -> void:
	for height: float in [780.0, 800.0, 864.0, 1080.0]:
		var board := _board(Vector2(1920.0, height), NightHost.MAX_PLAYERS)
		board.show_credits(_night_input(NightHost.MAX_PLAYERS))
		await await_idle_frame()
		var players := float(NightHost.MAX_PLAYERS)
		# What the sums say the tickets take: their chrome and a row for each player in each.
		var nominal := (
			HudEndBoard.CHROME_HEIGHT
			+ HudCredits.CHROME
			+ float(HudStyle.MD)
			+ players * (board.row_height() + board.credits_row_height())
		)
		var room := height - float(HudStyle.margin()) * 2.0
		var floors := (
			is_equal_approx(board.row_height(), HudEndBoard.MIN_ROW_HEIGHT)
			and is_equal_approx(board.credits_row_height(), HudCredits.MIN_ROW)
		)
		(
			assert_bool(nominal <= room + 0.5 or floors)
			. override_failure_message(
				(
					"height %s: the sums give %s of %s, rows %s and %s"
					% [height, nominal, room, board.row_height(), board.credits_row_height()]
				)
			)
			. is_true()
		)
		# And what is drawn fits the screen (the type's own height is the floor of a row).
		if height >= 800.0:
			var column := board._ticket.get_global_rect().merge(
				board.credits_card.get_global_rect()
			)
			assert_float(column.size.y).is_less_equal(room)
