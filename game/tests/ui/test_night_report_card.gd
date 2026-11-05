extends GdUnitTestSuite
## The night report's card on the end board (`HudNightReport`, `HudEndBoard.show_report`,
## docs/design/progression.md#the-night-report-and-credits): the lines as they paid, the total, the
## level bar and what comes next; a night nobody keeps says so and has no bar; the card stays
## inside the screen, clear of the way out, the title and the players' ticket, at every canvas and
## on a phone with its notch, even with every line the report can have.

const CANVASES: Array[Vector2] = [
	Vector2(1536.0, 864.0),
	Vector2(1920.0, 1080.0),
	Vector2(2340.0, 1080.0),
	Vector2(2560.0, 1080.0),
]
const PHONE_INSETS := Vector4(96.0, 0.0, 96.0, 24.0)
## The narrowest canvas a phone gives (2340 by 1080 is a common one).
const PHONE_MIN_WIDTH := 2000.0
const NAMES := ["Ruby", "Moe", "Dee", "Cal"]


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


## Every line the report has, and a cap, for a night that crossed levels and unlocked things.
func _fullest(kept: bool) -> Dictionary:
	var sources := {}
	for line in NightReport.LINES:
		for source: StringName in line["sources"]:
			sources[source] = 1850 * XpRules.HUNDREDTHS
	var hundredths := 0
	for source: StringName in sources:
		hundredths += int(sources[source])
	return NightReport.compose(sources, XpRules.to_xp(hundredths), 40 if kept else 0, kept)


func _board(canvas: Vector2, players: int = 4) -> HudEndBoard:
	var board := HudEndBoard.new()
	_host(canvas).add_child(board)
	board.show_results(_state(players), "BACK TO THE LOBBY IN", "Leave")
	board.set_left(15)
	return board


func test_the_card_is_hidden_until_a_report_is_given() -> void:
	var board := _board(Vector2(1920.0, 1080.0))
	await await_idle_frame()
	assert_bool(board.report_card.visible).is_false()
	board.show_report(NightReport.compose({ChallengeStats.ROUND: 2000}, 20, 0, true))
	assert_bool(board.report_card.visible).is_true()


func test_a_kept_night_shows_lines_total_level_and_what_is_next() -> void:
	var board := _board(Vector2(1920.0, 1080.0))
	var sources := {
		ChallengeStats.ROUND: 6000,
		ChallengeStats.POINTS: 2500,
		XpAward.OPENING_NIGHT: 5000,
		XpAward.FIRST_GAME: 10000,
	}
	var xp := XpRules.to_xp(23500)
	board.show_report(NightReport.compose(sources, xp, 100, true))
	var card := board.report_card
	(
		assert_array(card.lines_text)
		. is_equal(
			[
				["ROUNDS", "+60"],
				["POINTS", "+25"],
				["OPENING NIGHT", "+50"],
				["FIRST GAME OF THE DAY", "+100"],
			]
		)
	)
	assert_str(card.total_text).is_equal("+235 XP")
	assert_str(card.heading_text).is_equal("YOUR NIGHT")
	# 100 XP is level 2 (from 85), 335 is level 4 (from 255): the card repeats the levels the
	# popups showed, and the items they gave.
	assert_str(card.level_text).is_equal("LEVEL 2 TO 4")
	assert_str(card.progress_text).is_equal("80 / 85 XP")
	assert_str(card.next_text).is_equal("NEXT: TAN AT 5")
	assert_str(card.unlocked_text).is_equal("UNLOCKED: CHERRY, ROLLED SLEEVES")
	assert_str(card.note_text).is_equal("")
	assert_float(card.bar_from).is_equal(0.0)
	assert_float(card.bar_to).is_greater(0.9)


func test_a_night_inside_a_level_shows_one_level_and_where_it_began() -> void:
	var board := _board(Vector2(1920.0, 1080.0))
	board.show_report(NightReport.compose({ChallengeStats.ROUND: 2000}, 20, 10, true))
	var card := board.report_card
	assert_str(card.level_text).is_equal("LEVEL 1")
	assert_str(card.progress_text).is_equal("30 / 85 XP")
	assert_float(card.bar_from).is_equal_approx(10.0 / 85.0, 0.001)
	assert_float(card.bar_to).is_equal_approx(30.0 / 85.0, 0.001)
	assert_str(card.unlocked_text).is_equal("")


func test_a_night_nobody_keeps_says_it_was_not_saved_and_has_no_bar() -> void:
	var board := _board(Vector2(1920.0, 1080.0))
	board.show_report(NightReport.compose({ChallengeStats.ROUND: 4000}, 40, 0, false))
	var card := board.report_card
	assert_str(card.heading_text).is_equal("YOUR NIGHT, UNSAVED")
	assert_str(card.note_text).is_equal("NO ACCOUNT: THIS NIGHT WAS NOT SAVED")
	assert_array(card.lines_text).is_equal([["ROUNDS", "+40"]])
	assert_str(card.total_text).is_equal("+40 XP")
	assert_str(card.level_text).is_equal("")
	assert_array(card.find_children("*", "HudXpBar", true, false)).is_empty()


func test_a_later_report_replaces_the_card() -> void:
	var board := _board(Vector2(1920.0, 1080.0))
	board.show_report(NightReport.compose({ChallengeStats.ROUND: 2000}, 20, 0, true))
	board.show_report(NightReport.compose({ChallengeStats.ROUND: 4000}, 40, 0, true))
	assert_array(board.report_card.lines_text).is_equal([["ROUNDS", "+40"]])


func test_the_fullest_report_fits_every_canvas_and_a_phone_with_its_notch() -> void:
	var faults: Array[String] = []
	for canvas in CANVASES:
		for insets: Vector4 in [Vector4.ZERO, PHONE_INSETS]:
			# A notch is a phone's: a canvas that narrow with a phone's insets is no device.
			if insets != Vector4.ZERO and canvas.x < PHONE_MIN_WIDTH:
				continue
			for kept: bool in [true, false]:
				var board := HudEndBoard.new()
				var host := _host(canvas)
				host.add_child(board)
				board.set_safe_insets(insets)
				board.show_results(_state(NightHost.MAX_PLAYERS), "BACK TO THE LOBBY IN", "Leave")
				board.set_left(15)
				board.show_report(_fullest(kept))
				await await_idle_frame()
				await await_idle_frame()
				await await_idle_frame()
				var where := "%s, insets %s, kept %s" % [canvas, insets, kept]
				faults.append_array(_faults(board, canvas, insets, where))
	assert_array(faults).is_empty()


## What is wrong with the card on `board`, in words: outside the screen, on the way out, the round
## or the players' ticket, or with text that leaves it.
func _faults(board: HudEndBoard, canvas: Vector2, insets: Vector4, where: String) -> Array[String]:
	var faults: Array[String] = []
	var inside := Rect2(Vector2.ZERO, canvas).grow_individual(
		-insets.x, -insets.y, -insets.z, -insets.w
	)
	var card := board.report_card
	var seen := card.get_global_rect()
	if not card.visible:
		faults.append("%s: the card is not shown" % where)
	if not inside.encloses(seen):
		var title := board._title.get_global_rect()
		var players := board._ticket.get_global_rect()
		faults.append(
			(
				"%s: the card %s leaves %s (title %s, players %s)"
				% [where, seen, inside, title, players]
			)
		)
	var button := board.leave_button.get_global_rect()
	if seen.intersects(button):
		faults.append("%s: Leave %s on the card %s" % [where, button, seen])
	for control in board.find_children("*", "HudTicket", true, false):
		var players := (control as Control).get_global_rect()
		if control != card and control != board.credits_card and seen.intersects(players):
			faults.append("%s: the card %s on the players %s" % [where, seen, players])
	var round_line := board._round_label.get_global_rect()
	if seen.intersects(round_line):
		faults.append("%s: the card %s on the round %s" % [where, seen, round_line])
	if card.row_height < HudNightReport.MIN_ROW or card.row_height > HudNightReport.ROW:
		faults.append("%s: a row of %s" % [where, card.row_height])
	for label in card.find_children("*", "Label", true, false):
		var text := label as Label
		if not seen.encloses(text.get_global_rect()):
			faults.append(
				"%s: '%s' %s leaves the card %s" % [where, text.text, text.get_global_rect(), seen]
			)
	return faults


func test_the_rows_get_less_height_when_the_room_is_short_and_never_less_than_a_floor() -> void:
	var card := HudNightReport.new()
	_host(Vector2(1920.0, 1080.0)).add_child(card)
	var model := _fullest(true)
	card.show_report(model, 4000.0)
	assert_float(card.row_height).is_equal(HudNightReport.ROW)
	card.show_report(model, 420.0)
	assert_float(card.row_height).is_between(HudNightReport.MIN_ROW, HudNightReport.ROW - 1.0)
	card.show_report(model, 10.0)
	assert_float(card.row_height).is_equal(HudNightReport.MIN_ROW)
