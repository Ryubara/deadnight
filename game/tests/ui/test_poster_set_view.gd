extends GdUnitTestSuite
## The poster sets on screen (#1073): the Challenges tab shows each set as its poster with a panel
## uncovered for every challenge done, the six rows and the prize, and a teaser of each in "All"
## that opens them; a finished set is a card of the popup lane (live and in the menu), once.

var _board: FakeChallengeBoard


func before_test() -> void:
	UIMotion.reduced = false
	_board = FakeChallengeBoard.new()


func after_test() -> void:
	UIMotion.reduced = false
	LevelIcons.release()


## The Challenges tab on a board whose first set has `done` panels uncovered.
func _panel(done: int, compact := false) -> ChallengesPanel:
	var poster_set := PosterSets.shipped().all()[0]
	for index in done:
		_board.feats_done.append(poster_set.challenges[index])
	var context := MenuContext.new()
	context.board = _board
	context.compact = compact
	var panel := ChallengesPanel.new()
	panel.context = context
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	panel.size = Vector2(1060, 900)
	host.add_child(panel)
	await await_idle_frame()
	return panel


func test_the_poster_sets_chip_shows_every_set_whole() -> void:
	var panel := await _panel(4)
	panel.show_family(ChallengesPanel.Family.SETS)
	await await_idle_frame()
	var views := panel.sets()
	assert_int(views.size()).is_equal(2)
	assert_str(views[0].title_text()).is_equal("Attack of the Fifty-Foot Generator")
	assert_int(views[0].row_count()).is_equal(6)
	assert_str(PosterSetView.progress_text(views[0].entry)).is_equal("4 of 6 panels uncovered")
	assert_array(views[0].poster.uncovered).is_equal([0, 1, 2, 3])
	assert_array(views[1].poster.uncovered).is_empty()
	assert_str(PosterSetView.progress_text(views[1].entry)).is_equal("0 of 6 panels uncovered")
	# Nothing else is on the chip: no dailies, orders or milestones.
	assert_int(panel.rows().size()).is_equal(0)
	# Each view is as tall as what it holds, and the next one starts below it.
	for view in views:
		assert_float(view.size.y).is_greater(view.poster.size.y)
	assert_float(views[1].position.y).is_greater_equal(views[0].position.y + views[0].size.y)


func test_all_shows_a_teaser_of_each_set_and_pressing_one_opens_the_sets() -> void:
	var panel := await _panel(6)
	var views := panel.sets()
	assert_int(views.size()).is_equal(2)
	assert_str(PosterSetView.progress_text(views[0].entry)).is_equal("All 6 panels uncovered")
	assert_int(views[0].row_count()).is_equal(0)
	views[0].pressed.emit()
	assert_int(panel.family).is_equal(ChallengesPanel.Family.SETS)
	await await_idle_frame()
	assert_int(panel.sets()[0].row_count()).is_equal(6)


func test_a_done_row_says_done_and_the_others_how_far_they_are() -> void:
	var panel := await _panel(2)
	panel.show_family(ChallengesPanel.Family.SETS)
	await await_idle_frame()
	var rows := panel.sets()[0].find_children("SetRow*", "HBoxContainer", true, false)
	assert_int(rows.size()).is_equal(6)
	var states: Array[String] = []
	for row in rows:
		var label := row.get_child(row.get_child_count() - 1) as Label
		states.append(label.text)
	assert_array(states).is_equal(["DONE", "DONE", "0/1", "0/5", "0/150", "0/1,000"])


func test_a_phone_lays_the_poster_beside_the_title_and_the_rows_under_it() -> void:
	var panel := await _panel(4, true)
	panel.show_family(ChallengesPanel.Family.SETS)
	await await_idle_frame()
	var view := panel.sets()[0]
	assert_float(view.poster.size.x).is_equal(PosterSetView.POSTER_WIDTH_COMPACT)
	assert_int(view.row_count()).is_equal(6)
	assert_float(view.size.y).is_greater(view.poster.size.y + 6.0 * PosterSetView.ROW_HEIGHT)


func test_the_panels_tile_the_poster_and_the_art_is_made_of_the_shared_parts() -> void:
	var covered := 0.0
	for index in PosterSet.PANELS:
		var rect := PosterCompose.panel_rect(index)
		covered += rect.get_area()
		assert_bool(Rect2(Vector2.ZERO, PosterCompose.SIZE).encloses(rect)).is_true()
	assert_float(covered).is_equal(PosterCompose.SIZE.x * PosterCompose.SIZE.y)
	for poster_set in PosterSets.shipped().all():
		var art := PosterArt.make(poster_set, 200.0, [0, 1, 2])
		auto_free(art)
		assert_int(art.shape_count()).is_greater(30)
		assert_float(art.size.y).is_equal(300.0)
		# Every printed line has room on the poster.
		for line: Dictionary in PosterCompose.print_lines(poster_set):
			assert_float(line["baseline"]).is_less(PosterCompose.SIZE.y)


# --- The popup card ---


func _event(index := 0, player := -1) -> Dictionary:
	var sets := PosterSets.shipped()
	return sets.event_of(sets.all()[index], player)


func test_a_finished_set_is_a_card_with_the_title_and_the_prize() -> void:
	var card: PopupCard = auto_free(PopupCard.new())
	add_child(card)
	card.setup(PopupQueue.Kind.SET, PopupCard.set_data(_event(1)))
	assert_array(card.lines()).is_equal(["POSTER SET DONE", "Revenge of the Headliners"])
	assert_vector(card.size).is_equal(PopupCard.SET_SIZE)
	assert_vector(PopupCard.size_of(PopupQueue.Kind.SET)).is_equal(PopupCard.SET_SIZE)
	# Another kind afterwards puts the poster and the prize away.
	card.setup(PopupQueue.Kind.CHALLENGE, {"text": "x", "family": 0})
	assert_array(card.lines()).is_equal(["CHALLENGE DONE", "x"])


func test_the_lane_shows_the_set_of_its_own_player_once_with_the_card_cue() -> void:
	var lane: PopupLane = auto_free(PopupLane.new())
	var cues: Array[StringName] = []
	lane.cue.connect(func(cue: StringName) -> void: cues.append(cue))
	var state := HudState.new()
	state.local_player_id = 1
	lane.state = state
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	host.add_child(lane)
	lane.on_event(_event(0, 2))
	assert_int(lane.queue.waiting.size() + lane.queue.shown.size()).is_equal(0)
	lane.on_event(_event(0, 1))
	for _i in 20:
		lane.advance(0.05)
	assert_int(lane.cards().size()).is_equal(1)
	assert_int(lane.cards()[0].kind).is_equal(PopupQueue.Kind.SET)
	assert_array(cues).is_equal([&"card_earned"])


func test_the_lane_shows_no_set_when_popups_are_off() -> void:
	var lane: PopupLane = auto_free(PopupLane.new())
	lane.mode = PopupLane.Mode.OFF
	add_child(lane)
	lane.on_event(_event())
	assert_int(lane.queue.waiting.size() + lane.queue.shown.size()).is_equal(0)


func test_the_menu_tells_a_set_the_account_finished_elsewhere_as_a_card() -> void:
	var overlay := MenuPopups.new()
	var layer: Control = auto_free(Control.new())
	layer.size = Vector2(1920, 1080)
	add_child(layer)
	layer.add_child(overlay)
	await await_idle_frame()
	MenuPopups.announce([_event(0)])
	for _i in 20:
		overlay.lane.advance(0.05)
	assert_int(overlay.lane.cards().size()).is_equal(1)
	assert_int(overlay.lane.cards()[0].kind).is_equal(PopupQueue.Kind.SET)
	assert_array(overlay.lane.cards()[0].lines()).contains(["POSTER SET DONE"])
	layer.remove_child(overlay)
	overlay.free()
