extends GdUnitTestSuite
## The board is all the menu reads: today's dailies with progress, the orders, the
## ladders and the time to the next refresh. Tested on its keys and values, as a screen would use
## them.

const DAY := 20401

var _catalog: ChallengeCatalog
var _day := DAY


func before_test() -> void:
	_catalog = ChallengeCatalog.load_default()
	_day = DAY


func _open(name: String) -> ChallengeBoard:
	return ChallengeBoard.open(
		ChallengeFixture.save_path(name), ChallengeFixture.clock_on(_day), _catalog
	)


func _ladder(board: ChallengeBoard, id: StringName) -> Dictionary:
	for row in board.milestones():
		if row["id"] == id:
			return row
	return {}


func test_a_new_player_sees_three_dailies_three_orders_and_every_ladder_at_zero() -> void:
	var board := _open("fresh")
	assert_int(board.dailies().size()).is_equal(3)
	assert_int(board.orders().size()).is_equal(3)
	assert_int(board.milestones().size()).is_equal(
		_catalog.of_family(ChallengeDef.Family.MILESTONE).size()
	)
	for row in board.milestones():
		assert_int(row["value"]).is_equal(0)
		assert_int(row["rung"]).is_equal(0)
		assert_int(row["target"]).is_equal(_catalog.get_def(row["id"]).steps[0])
		assert_float(row["fraction"]).is_equal(0.0)
		assert_bool(row["done"]).is_false()


func test_a_daily_row_has_what_a_card_shows() -> void:
	var row := _open("row").dailies()[0]
	for key in ["id", "text", "progress", "target", "fraction", "done", "tier", "reward"]:
		assert_bool(row.has(key)).override_failure_message("missing key %s" % key).is_true()
	assert_str(row["tier"]).is_equal("short")
	assert_str(row["text"]).not_contains("{n}")


func test_progress_shows_as_a_fraction_and_never_past_the_target() -> void:
	var board := _open("fraction")
	var entry := board.profile.dailies[0]
	var target := _catalog.get_def(entry["id"]).target
	entry["progress"] = target / 2
	assert_float(board.dailies()[0]["fraction"]).is_equal_approx(float(target / 2) / target, 0.001)
	entry["progress"] = target * 3
	assert_int(board.dailies()[0]["progress"]).is_equal(target)
	assert_float(board.dailies()[0]["fraction"]).is_equal(1.0)
	assert_bool(board.dailies()[0]["done"]).is_true()


func test_the_next_day_shows_three_new_dailies_at_zero() -> void:
	var first := _open("expire")
	first.profile.dailies[0]["progress"] = 1
	var yesterday := first.dailies().map(func(r: Dictionary) -> StringName: return r["id"])
	_day = DAY + 1
	var board := ChallengeBoard.open(first.path, ChallengeFixture.clock_on(_day), _catalog)
	var rows := board.dailies()
	assert_int(rows.size()).is_equal(3)
	(
		assert_array(rows.map(func(r: Dictionary) -> StringName: return r["id"]))
		. is_not_equal(yesterday)
	)
	for row in rows:
		assert_int(row["progress"]).is_equal(0)
		assert_bool(row.has("banked")).is_false()


func test_the_board_is_saved_when_opened_and_reopens_the_same() -> void:
	var board := _open("saved")
	board.profile.orders[0]["progress"] = 2
	board.save()
	var again := ChallengeBoard.open(board.path, ChallengeFixture.clock_on(_day), _catalog)
	(
		assert_array(again.orders().map(func(r: Dictionary) -> int: return r["progress"]))
		. is_equal(board.orders().map(func(r: Dictionary) -> int: return r["progress"]))
	)
	assert_int(again.profile.order_seed).is_equal(board.profile.order_seed)


func test_an_order_row_names_its_slot_and_pillar() -> void:
	var rows := _open("orders").orders()
	for i in rows.size():
		assert_int(rows[i]["slot"]).is_equal(i)
		assert_bool(["night", "light", "craft"].has(String(rows[i]["pillar"]))).is_true()


func test_swapping_an_order_changes_the_slot_saves_and_tells_the_menu() -> void:
	var board := _open("swap")
	var told := [0]
	board.changed.connect(func() -> void: told[0] += 1)
	var before: StringName = board.orders()[1]["id"]
	assert_bool(board.swap_order(1)).is_true()
	assert_bool(board.orders()[1]["id"] != before).is_true()
	assert_int(told[0]).is_equal(1)
	var again := ChallengeBoard.open(board.path, ChallengeFixture.clock_on(_day), _catalog)
	(
		assert_array(again.orders().map(func(r: Dictionary) -> StringName: return r["id"]))
		. is_equal(board.orders().map(func(r: Dictionary) -> StringName: return r["id"]))
	)
	assert_bool(board.swap_order(9)).is_false()


func test_a_milestone_row_shows_the_step_it_is_climbing_to() -> void:
	var board := _open("ladder")
	board.profile.lifetime[&"kills"] = 300
	var row := _ladder(board, &"m_kills")
	# Steps 50 and 250 are behind; the next is 1000, and 50 of its 750 are done.
	assert_int(row["rung"]).is_equal(2)
	assert_int(row["target"]).is_equal(1000)
	assert_float(row["fraction"]).is_equal_approx(50.0 / 750.0, 0.001)
	assert_str(row["text"]).is_equal("Put down 1000 zombies")
	board.profile.lifetime[&"kills"] = 999999
	row = _ladder(board, &"m_kills")
	assert_bool(row["done"]).is_true()
	assert_int(row["target"]).is_equal(0)
	assert_float(row["fraction"]).is_equal(1.0)


func test_the_time_to_the_next_refresh_reads_well() -> void:
	var noon := ChallengeBoard.open(
		ChallengeFixture.save_path("clock"),
		ChallengeClock.fixed(float(DAY) * 86400.0 + 12.0 * 3600.0 + 15.0 * 60.0),
		_catalog
	)
	assert_int(noon.seconds_to_refresh()).is_equal(11 * 3600 + 45 * 60)
	assert_str(noon.refresh_text()).is_equal("11 h 45 min")
	var late := ChallengeBoard.open(
		ChallengeFixture.save_path("clock_late"),
		ChallengeClock.fixed(float(DAY) * 86400.0 + 86400.0 - 25.0 * 60.0),
		_catalog
	)
	assert_str(late.refresh_text()).is_equal("25 min")
	var last := ChallengeBoard.open(
		ChallengeFixture.save_path("clock_last"),
		ChallengeClock.fixed(float(DAY) * 86400.0 + 86400.0 - 10.0),
		_catalog
	)
	assert_str(last.refresh_text()).is_equal("1 min")


func test_refresh_deals_a_new_day_while_the_menu_is_open() -> void:
	var now := [float(DAY) * 86400.0 + 3600.0]
	var board := ChallengeBoard.open(
		ChallengeFixture.save_path("overnight"),
		ChallengeClock.from_source(func() -> float: return now[0]),
		_catalog
	)
	var told := [0]
	board.changed.connect(func() -> void: told[0] += 1)
	var today := board.dailies().map(func(r: Dictionary) -> StringName: return r["id"])
	now[0] += 86400.0
	board.refresh()
	assert_int(told[0]).is_equal(1)
	assert_int(board.dailies().size()).is_equal(3)
	(
		assert_array(board.dailies().map(func(r: Dictionary) -> StringName: return r["id"]))
		. is_equal(DailyRotation.deal(_catalog, DAY + 1))
	)
	assert_array(today).is_equal(DailyRotation.deal(_catalog, DAY))
