extends GdUnitTestSuite
## The end board with the fullest night (Deadnight #1145): the fullest report card, the credits of
## eight people and the seven bots that come on top (#1179) and the players' ticket stay inside
## the screen, and the way out (Leave) with the countdown above it is always on it, at every canvas
## (1536 x 864 is a 1920 x 1080 window at the largest UI scale; 1872 x 864 a phone at that scale
## with its notch) and with every line readable.

const CANVASES: Array[Vector2] = [
	Vector2(1536.0, 864.0),
	Vector2(1872.0, 864.0),
	Vector2(1920.0, 1080.0),
	Vector2(2340.0, 1080.0),
	Vector2(2560.0, 1080.0),
]
const PHONE_INSETS := Vector4(96.0, 0.0, 96.0, 24.0)
const PHONE_MIN_WIDTH := 1800.0


func _board(canvas: Vector2, players: int, insets: Vector4, kept: bool, bots := 0) -> HudEndBoard:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	var board := HudEndBoard.new()
	host.add_child(board)
	board.set_safe_insets(insets)
	board.show_results(EndBoardFixtures.state(players, bots), "BACK TO THE LOBBY IN", "Leave")
	board.set_left(15)
	board.show_report(EndBoardFixtures.fullest_report(kept))
	board.show_credits(EndBoardFixtures.fullest_credits(players, 1500, bots))
	return board


func test_leave_and_everything_else_stay_on_screen_with_the_fullest_night() -> void:
	var faults: Array[String] = []
	for canvas in CANVASES:
		for insets: Vector4 in [Vector4.ZERO, PHONE_INSETS]:
			if insets != Vector4.ZERO and canvas.x < PHONE_MIN_WIDTH:
				continue
			# People and bots: one, four, eight, and eight with the seven bots on top.
			for mix: Vector2i in [
				Vector2i(1, 0),
				Vector2i(4, 0),
				Vector2i(NightHost.MAX_PLAYERS, 0),
				Vector2i(NightHost.MAX_PLAYERS, MatchSettings.MAX_BOTS)
			]:
				for kept: bool in [true, false]:
					var board := _board(canvas, mix.x, insets, kept, mix.y)
					for _i in 4:
						await await_idle_frame()
					var where := (
						"%s, insets %s, %d people %d bots, kept %s"
						% [canvas, insets, mix.x, mix.y, kept]
					)
					faults.append_array(_faults(board, canvas, insets, where))
	assert_array(faults).is_empty()


## What is wrong with the board, in words: a part outside the screen's safe area, the left column's
## parts out of order or on one another, or type smaller than the HUD's floor.
func _faults(board: HudEndBoard, canvas: Vector2, insets: Vector4, where: String) -> Array[String]:
	var faults: Array[String] = []
	var inside := Rect2(Vector2.ZERO, canvas).grow_individual(
		-insets.x, -insets.y, -insets.z, -insets.w
	)
	var column: Array[Control] = [
		board._title,
		board._round_label,
		board.report_card,
		board._caption,
		board._number,
		board.leave_button,
	]
	var names := ["title", "round", "report", "caption", "countdown", "Leave"]
	var others: Array[Control] = [board._ticket, board.credits_card]
	for i in column.size():
		var seen := column[i].get_global_rect()
		if not inside.encloses(seen):
			faults.append("%s: the %s %s leaves %s" % [where, names[i], seen, inside])
		if i > 0 and seen.position.y < column[i - 1].get_global_rect().end.y - 0.5:
			faults.append("%s: the %s %s is on the %s" % [where, names[i], seen, names[i - 1]])
	for part in others:
		if part.visible and not inside.encloses(part.get_global_rect()):
			faults.append("%s: %s leaves %s" % [where, part.get_global_rect(), inside])
	for label in board.find_children("*", "Label", true, false):
		var text := label as Label
		if text.is_visible_in_tree() and text.get_theme_font_size(&"font_size") < HudStyle.MIN_TEXT:
			faults.append(
				"%s: '%s' is set in %d" % [where, text.text, text.get_theme_font_size(&"font_size")]
			)
	if board._title.get_theme_font_size(&"font_size") < HudStyle.MEDIUM:
		faults.append(
			"%s: the title is set in %d" % [where, board._title.get_theme_font_size(&"font_size")]
		)
	if board._number.get_theme_font_size(&"font_size") < HudEndBoard.NUMBER_FLOOR:
		faults.append(
			(
				"%s: the countdown is set in %d"
				% [where, board._number.get_theme_font_size(&"font_size")]
			)
		)
	return faults


func test_a_tall_screen_keeps_the_title_and_the_countdown_at_their_full_size() -> void:
	var board := _board(Vector2(2560.0, 1440.0), 4, Vector4.ZERO, true)
	for _i in 4:
		await await_idle_frame()
	assert_int(board._title.get_theme_font_size(&"font_size")).is_equal(HudStyle.BIG)
	assert_int(board._number.get_theme_font_size(&"font_size")).is_equal(HudStyle.NUMERAL)
	assert_float(board.report_card.row_height).is_equal(HudNightReport.ROW)
