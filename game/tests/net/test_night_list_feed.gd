# The Server Browser's list reader (`NightListFeed`, `NightEntry`, Deadnight #1180): what it makes
# of the rows the backend lists, and how it keeps inside the backend's limit of 20 asks in 10
# seconds for one account (docs/design/lobby.md#the-list-of-nights-the-server-browsers-data-1179),
# however fast it is pressed.
extends GdUnitTestSuite

var _now := 100.0
var _api: BrowserFixture.FakeApi
var _feed: NightListFeed


func before_test() -> void:
	_now = 100.0
	_api = BrowserFixture.FakeApi.new(self)
	_api.nights = BrowserFixture.nights()
	_feed = NightListFeed.new()
	_feed.clock = func() -> float: return _now
	add_child(_feed)


func after_test() -> void:
	_feed.stop()
	_feed.queue_free()
	await get_tree().process_frame


# --- The rows ---


func test_a_row_is_people_out_of_the_seats_with_the_bots_apart() -> void:
	var entry := NightEntry.from_row(
		BrowserFixture.row("KITE42", "drive_in", "match", 3, "Ann", 2, 6)
	)
	assert_str(entry.people_text()).is_equal("3 of 8")
	assert_str(entry.bots_text()).is_equal("+2 bots")
	assert_int(entry.players).is_equal(3)
	# Two bots never add to the people: 3 people and 2 bots is still "3 of 8".
	assert_str(entry.spoken()).contains("3 of 8 people")


func test_a_lobby_and_a_match_are_told_apart_in_words() -> void:
	var waiting := NightEntry.from_row(
		BrowserFixture.row("LAMP77", "small_indoor", "lobby", 2, "Bo")
	)
	var running := NightEntry.from_row(
		BrowserFixture.row("KITE42", "drive_in", "match", 3, "Ann", 0, 6)
	)
	assert_bool(waiting.is_match()).is_false()
	assert_bool(running.is_match()).is_true()
	assert_str(waiting.state_text()).is_equal("Waiting to start")
	assert_str(running.state_text()).is_equal("In progress, round 6")
	assert_str(waiting.badge_text()).is_equal("WAITING")
	assert_str(running.badge_text()).is_equal("IN PROGRESS")


func test_a_match_that_has_said_no_round_yet_is_in_progress_without_one() -> void:
	var entry := NightEntry.from_row(BrowserFixture.row("KITE42", "drive_in", "match", 1, "Ann"))
	assert_str(entry.state_text()).is_equal("In progress")
	assert_int(entry.round_number).is_equal(0)


func test_a_full_night_says_so_and_a_night_with_room_does_not() -> void:
	var full := NightEntry.from_row(
		BrowserFixture.row("FULL88", "drive_in", "match", 8, "Ed", 1, 3)
	)
	var open := NightEntry.from_row(BrowserFixture.row("ROSE19", "drive_in", "lobby", 1, "Cy", 3))
	assert_bool(full.full).is_true()
	assert_str(full.badge_text()).is_equal("FULL")
	assert_bool(open.full).is_false()


func test_the_map_is_the_games_own_and_an_unknown_one_falls_back_to_the_lot() -> void:
	var known := NightEntry.from_row(BrowserFixture.row("LAMP77", "small_indoor", "lobby", 2, "Bo"))
	var unknown := NightEntry.from_row(BrowserFixture.row("ZZZ999", "no_such_map", "lobby", 1, "X"))
	assert_str(known.map().id).is_equal("small_indoor")
	assert_str(unknown.map().id).is_equal(MapRegistry.DEFAULT)


func test_rows_that_are_not_rows_are_left_out() -> void:
	var entries := NightEntry.parse({"nights": [{"code": "OK1234"}, 5, {"id": "no code"}, "x"]})
	assert_int(entries.size()).is_equal(1)
	assert_str(entries[0].code).is_equal("OK1234")
	assert_int(NightEntry.parse({"nights": "nope"}).size()).is_equal(0)


# --- The reader ---


func test_the_first_ask_goes_out_at_once_and_the_rows_come_in_the_backends_order() -> void:
	var got: Array[Array] = []
	_feed.updated.connect(
		func(entries: Array[NightEntry], _total: int) -> void: got.append(entries)
	)
	_feed.start(_api)
	await get_tree().process_frame
	assert_int(_api.list_calls).is_equal(1)
	assert_int(got.size()).is_equal(1)
	var codes: Array[String] = []
	for entry: NightEntry in got[0]:
		codes.append(entry.code)
	assert_array(codes).is_equal(["KITE42", "LAMP77", "ROSE19", "MOTH05", "FULL88"])


func test_pressing_refresh_over_and_over_never_goes_past_the_budget() -> void:
	_feed.start(_api)
	await get_tree().process_frame
	# A player (or a bug) asking 200 times in the 10 seconds: the backend allows 20, the feed sends
	# under 15.
	for i in 200:
		_now += 0.05
		_feed.refresh(i % 2 == 0)
		await get_tree().process_frame
	assert_int(_feed.asks_in_window(_now)).is_less_equal(NightListFeed.BUDGET)
	assert_int(_api.list_calls).is_less_equal(NightListFeed.BUDGET)
	assert_int(NightListFeed.BUDGET).is_less(20)


func test_the_window_slides_so_the_feed_can_ask_again_later() -> void:
	_feed.start(_api)
	await get_tree().process_frame
	for i in 40:
		_now += 0.2
		_feed.refresh()
		await get_tree().process_frame
	var spent := _api.list_calls
	_now += NightListFeed.WINDOW + 1.0
	assert_bool(_feed.refresh()).is_true()
	await get_tree().process_frame
	assert_int(_api.list_calls).is_equal(spent + 1)


func test_a_press_of_refresh_inside_the_least_gap_is_turned_away() -> void:
	_feed.start(_api)
	await get_tree().process_frame
	_now += NightListFeed.MIN_GAP * 0.5
	assert_bool(_feed.refresh(true)).is_false()
	_now += NightListFeed.MIN_GAP
	assert_bool(_feed.refresh(true)).is_true()


func test_the_timer_asks_about_every_four_seconds_and_stays_far_inside_the_limit() -> void:
	# Over a minute: 15 timed asks, a quarter of the 60 the backend would allow in the same time.
	assert_float(NightListFeed.EVERY).is_greater_equal(3.0)
	var per_window := NightListFeed.WINDOW / NightListFeed.EVERY
	assert_float(per_window).is_less(20.0 / 2.0)


func test_a_429_holds_the_feed_for_the_seconds_the_header_named_and_keeps_the_rows() -> void:
	var waited: Array[float] = []
	_feed.waiting.connect(func(seconds: float) -> void: waited.append(seconds))
	_feed.start(_api)
	await get_tree().process_frame
	var kept := _feed.entries.size()
	assert_int(kept).is_equal(5)
	_api.list_failure = "too_many_requests"
	_now += 5.0
	_feed.refresh()
	await get_tree().process_frame
	assert_bool(waited.is_empty()).is_false()
	var calls := _api.list_calls
	_now += 3.0
	assert_bool(_feed.refresh()).is_false()
	assert_int(_api.list_calls).is_equal(calls)
	assert_int(_feed.entries.size()).is_equal(kept)


func test_a_failure_is_said_in_words_and_the_next_good_answer_clears_it() -> void:
	var said: Array[String] = []
	_feed.failed.connect(func(text: String, _reason: String) -> void: said.append(text))
	_api.list_failure = "network"
	_feed.start(_api)
	await get_tree().process_frame
	assert_array(said).is_equal([TogetherApi.TEXTS["network"]])
	assert_int(_feed.state).is_equal(NightListFeed.State.FAILED)
	_api.list_failure = ""
	_now += 5.0
	_feed.refresh()
	await get_tree().process_frame
	assert_int(_feed.state).is_equal(NightListFeed.State.LOADED)
	assert_int(_feed.entries.size()).is_equal(5)


func test_an_answer_that_comes_after_stop_is_told_to_nobody() -> void:
	var updates := [0]
	_feed.updated.connect(func(_e: Array[NightEntry], _t: int) -> void: updates[0] += 1)
	_api.hold_list = true
	_feed.start(_api)
	_feed.stop()
	_api.released.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(updates[0]).is_equal(0)
