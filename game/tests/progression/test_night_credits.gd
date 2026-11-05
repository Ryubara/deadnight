extends GdUnitTestSuite
## The film credits' titles (`NightCredits`, `CrewTitles`, `CrewTracker`, the design page's night
## report and credits): each title goes to the player with the most of its stat, a tie to
## the lower seat, a stat of zero names no one, a player holds at most one title and one with
## nothing is an Extra; solo and four players get theirs; and no title names a stat the night does
## not count (each is moved by an event the tally hears).

const BOARDS := ChallengeStats.BOARDS
const FUEL := ChallengeStats.FUEL_CANS
const DOWNS := ChallengeStats.DOWNS
const FUEL_ITEMS: Array[StringName] = [&"fuel_can"]


func _titles_of(credits: Array[Dictionary]) -> Dictionary:
	var by_player := {}
	for credit in credits:
		by_player[credit["player_id"]] = credit["id"]
	return by_player


func _removal(killer: int, boss: bool) -> Dictionary:
	return {
		"type": &"zombie_removed",
		"zombie_id": 1,
		"zombie_type": &"walker",
		"boss": boss,
		"cause": &"killed",
		"killer_id": killer,
		"zone": &"body",
		"melee": false,
	}


# --- Who gets what -----------------------------------------------------------------------------


func test_a_title_goes_to_the_player_with_the_most_of_its_stat() -> void:
	var counts := {1: {BOARDS: 3}, 2: {BOARDS: 9}, 3: {BOARDS: 5}}
	var titles := _titles_of(NightCredits.award(counts, {1: 1, 2: 2, 3: 3}))
	assert_that(titles[2]).is_equal(&"key_grip")
	assert_int(titles.size()).is_equal(3)


func test_every_shipped_title_goes_to_the_leader_of_its_own_stat() -> void:
	var list := CrewTitles.shipped()
	var counts := {}
	var seats := {}
	# Player n leads title n and has a little of the rest, so only the leader can take it.
	for i in list.titles.size():
		var id := i + 1
		seats[id] = id
		var mine := {}
		for other in list.titles:
			mine[other["stat"]] = 1
		mine[list.titles[i]["stat"]] = 10
		counts[id] = mine
	var titles := _titles_of(NightCredits.award(counts, seats))
	for i in list.titles.size():
		assert_that(titles[i + 1]).is_equal(list.titles[i]["id"])


func test_a_tie_goes_to_the_lower_seat_not_the_lower_id() -> void:
	# Id 5 sits in seat 1, id 2 in seat 3: the same count, so the seat decides.
	var counts := {5: {FUEL: 4}, 2: {FUEL: 4}}
	var titles := _titles_of(NightCredits.award(counts, {5: 1, 2: 3}))
	assert_that(titles[5]).is_equal(&"best_boy")
	assert_that(titles[2]).is_equal(&"extra")


func test_a_stat_of_zero_names_no_one_and_everyone_is_an_extra() -> void:
	var counts := {1: {}, 2: {BOARDS: 0, FUEL: 0}, 3: {DOWNS: 0}}
	var credits := NightCredits.award(counts, {1: 1, 2: 2, 3: 3})
	assert_int(credits.size()).is_equal(3)
	for credit in credits:
		assert_that(credit["id"]).is_equal(&"extra")
		assert_int(credit["count"]).is_zero()


func test_a_player_has_one_title_and_the_runner_up_takes_the_next() -> void:
	# Player 1 leads boards and fuel; the title earlier in the billing is theirs, the other goes on
	# to the runner-up (a player never holds two).
	var counts := {1: {BOARDS: 9, FUEL: 9}, 2: {BOARDS: 2, FUEL: 3}}
	var credits := NightCredits.award(counts, {1: 1, 2: 2})
	var titles := _titles_of(credits)
	assert_that(titles[1]).is_equal(&"best_boy")
	assert_that(titles[2]).is_equal(&"key_grip")
	var seen := {}
	for credit in credits:
		assert_bool(seen.has(credit["player_id"])).is_false()
		seen[credit["player_id"]] = true


func test_a_player_with_nothing_is_an_extra_after_the_titled() -> void:
	var counts := {1: {}, 2: {BOARDS: 1}, 3: {}}
	var credits := NightCredits.award(counts, {1: 1, 2: 2, 3: 3})
	assert_that(credits[0]["player_id"]).is_equal(2)
	assert_that(credits[0]["id"]).is_equal(&"key_grip")
	assert_that(credits[1]["id"]).is_equal(&"extra")
	assert_that(credits[1]["player_id"]).is_equal(1)
	assert_that(credits[2]["player_id"]).is_equal(3)


func test_a_solo_night_has_a_credit_with_a_title_or_as_an_extra() -> void:
	var worked := NightCredits.award({1: {BOARDS: 2, DOWNS: 1}}, {1: 1})
	assert_int(worked.size()).is_equal(1)
	assert_that(worked[0]["id"]).is_equal(&"key_grip")
	var idle := NightCredits.award({1: {}}, {1: 1})
	assert_int(idle.size()).is_equal(1)
	assert_that(idle[0]["id"]).is_equal(&"extra")


func test_a_night_of_four_gives_each_player_exactly_one_credit() -> void:
	var counts := {
		1: {BOARDS: 8, ChallengeStats.POINTS: 3000},
		2: {FUEL: 2, DOWNS: 4},
		3: {ChallengeStats.REVIVES: 1},
		4: {},
	}
	var credits := NightCredits.award(counts, {1: 1, 2: 2, 3: 3, 4: 4})
	assert_int(credits.size()).is_equal(4)
	var titles := _titles_of(credits)
	assert_that(titles[3]).is_equal(&"stunt_coordinator")
	assert_that(titles[2]).is_equal(&"best_boy")
	assert_that(titles[1]).is_equal(&"key_grip")
	assert_that(titles[4]).is_equal(&"extra")


func test_a_player_who_counted_nothing_still_has_a_seat_and_a_credit() -> void:
	# A player the tally never named (no event) is in the credits from the board's own seats.
	var credits := NightCredits.award({1: {BOARDS: 1}}, {1: 1, 2: 2})
	assert_int(credits.size()).is_equal(2)
	assert_that(credits[1]["player_id"]).is_equal(2)


# --- The titles --------------------------------------------------------------------------------


func test_the_shipped_titles_are_whole_and_name_a_stat_the_night_counts() -> void:
	var list := CrewTitles.shipped()
	assert_int(list.titles.size()).is_greater_equal(6)
	var ids := {}
	for row in list.titles:
		assert_str(row["title"]).is_not_empty()
		assert_str(row["reason"]).is_not_empty()
		assert_bool(ids.has(row["id"])).is_false()
		ids[row["id"]] = true
		# A stat the night does not count would never be anyone's.
		assert_bool(ChallengeStats.is_known(row["stat"], [], [])).is_true()
	assert_str(list.extra["title"]).is_equal("Extra")


func test_every_title_stat_is_moved_by_an_event_the_credits_hear() -> void:
	var made := {
		BOARDS: {"type": &"board_repaired", "player_id": 1},
		FUEL: {"type": &"purchase_made", "player_id": 1, "item_id": &"fuel_can"},
		ChallengeStats.DOORS: {"type": &"purchase_made", "player_id": 1, "item_id": &"door_a"},
		DOWNS: {"type": &"player_downed", "player_id": 1},
		ChallengeStats.REVIVES: {"type": &"player_revived", "player_id": 2, "reviver_id": 1},
		ChallengeStats.POINTS:
		{"type": &"points_changed", "player_id": 1, "delta": 50, "reason": &"kill"},
		ChallengeStats.KILLS_BOSS: _removal(1, true),
	}
	for row in CrewTitles.shipped().titles:
		var stat: StringName = row["stat"]
		assert_bool(made.has(stat)).is_true()
		var event: Dictionary = made[stat]
		assert_bool(CrewTitles.HEARD.has(event["type"])).is_true()
		var tally := NightTally.new(FUEL_ITEMS)
		tally.keep_only(CrewTitles.shipped().stats())
		tally.observe(event)
		# One of it, or the points the event paid.
		assert_int(tally.count(1, stat)).is_equal(int(event.get("delta", 1)))


func test_a_list_with_a_broken_row_leaves_it_out() -> void:
	var text := '{"titles": [{"id": "a", "title": "A", "stat": "boards_repaired", "reason": "r"},'
	text += ' {"id": "b"}, 7]}'
	var list := CrewTitles.from_text(text)
	assert_int(list.titles.size()).is_equal(1)
	assert_int(CrewTitles.from_text("not json").titles.size()).is_zero()


# --- What a client hears -----------------------------------------------------------------------


func test_a_client_counts_every_players_titles_from_the_events_it_hears() -> void:
	var state := ClientState.new()
	var tracker := CrewTracker.follow(state, FUEL_ITEMS)
	(
		state
		. apply_events(
			[
				{"type": &"board_repaired", "player_id": 1},
				{"type": &"board_repaired", "player_id": 1},
				{"type": &"board_repaired", "player_id": 3},
				{"type": &"player_downed", "player_id": 2},
				{"type": &"purchase_made", "player_id": 2, "item_id": &"fuel_can"},
				{"type": &"purchase_made", "player_id": 2, "item_id": &"shotgun"},
			]
		)
	)
	var counts: Dictionary = tracker.input()["counts"]
	assert_int(counts[1][BOARDS]).is_equal(2)
	assert_int(counts[3][BOARDS]).is_equal(1)
	assert_int(counts[2][DOWNS]).is_equal(1)
	assert_int(counts[2][FUEL]).is_equal(1)
	var titles := _titles_of(NightCredits.award(counts, {1: 1, 2: 2, 3: 3}))
	assert_that(titles[1]).is_equal(&"key_grip")
	assert_that(titles[2]).is_equal(&"best_boy")
	assert_that(titles[3]).is_equal(&"extra")


func test_the_horde_costs_the_credits_nothing_and_only_a_boss_counts() -> void:
	var state := ClientState.new()
	var tracker := CrewTracker.follow(state, FUEL_ITEMS)
	for _i in 200:
		state.apply_events([_removal(1, false)])
	assert_int((tracker.input()["counts"] as Dictionary).size()).is_zero()
	state.apply_events([_removal(1, true)])
	var mine: Dictionary = tracker.input()["counts"][1]
	assert_int(mine[ChallengeStats.KILLS_BOSS]).is_equal(1)
	# The kills themselves are not a stat of the credits' tally.
	assert_bool(mine.has(ChallengeStats.KILLS)).is_false()


func test_a_clients_credits_carry_the_xp_the_server_told_each_seat() -> void:
	var state := ClientState.new()
	state.player_id = 1
	var tracker := ReportTracker.follow(state, FUEL_ITEMS)
	var heard := []
	tracker.changed.connect(func() -> void: heard.append(true))
	(
		state
		. apply_events(
			[
				{
					"type": &"xp_gained",
					"player_id": 2,
					"hundredths": 4000,
					"xp": 40,
					"total": 40,
					"sources": {},
				},
				{
					"type": &"xp_gained",
					"player_id": 1,
					"hundredths": 7000,
					"xp": 70,
					"total": 70,
					"sources": {ChallengeStats.ROUND: 7000},
				},
			]
		)
	)
	var xp: Dictionary = tracker.credits_input()["xp"]
	assert_int(xp[1]).is_equal(70)
	assert_int(xp[2]).is_equal(40)
	assert_bool(xp.has(3)).is_false()
	assert_int(heard.size()).is_equal(3)


func test_a_night_nobody_keeps_gives_no_xp_to_the_credits() -> void:
	var state := ClientState.new()
	state.player_id = 1
	var tracker := ReportTracker.follow(state, FUEL_ITEMS)
	state.apply_events([{"type": &"board_repaired", "player_id": 1}])
	assert_bool(tracker.is_kept()).is_false()
	assert_dict(tracker.credits_input()["xp"]).is_empty()
