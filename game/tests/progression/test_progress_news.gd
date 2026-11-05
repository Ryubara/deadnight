extends GdUnitTestSuite
## Progress the menu learns of while no night is up (`ProgressNews`, #1130): the levels an account
## holds beyond what this machine knew, and the challenges its board shows finished that the cache
## lacks. Every card is told once: a card a night showed live is in the ledger (`ProgressSeen`), the
## cache is the baseline, and a cache that is not this account's is no baseline at all.

const DIR := "user://test_progress_news/"
const ACCOUNT := "account-one"
const OTHER := "account-two"
const DAY := 20401
## Level 6 opens the second tier and gives a hat: a level card, a tier card and an unlock.
const TIER_LEVEL := 6

var _catalog: ChallengeCatalog


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear()
	ProgressSeen.path = DIR + "seen.json"
	_catalog = ChallengeFixture.small_catalog()


func after_test() -> void:
	ProgressSeen.path = ""
	_clear()


func _clear() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


func _levels(events: Array) -> Array:
	var out: Array = []
	for event: Dictionary in events:
		if event["type"] == &"level_up":
			out.append(event["level"])
	return out


func _ids(events: Array) -> Array:
	var out: Array = []
	for event: Dictionary in events:
		out.append(event["id"])
	return out


func _board(account: String = ACCOUNT) -> ChallengeProfile:
	var profile := ChallengeProfile.fresh_for(account)
	profile.dealt_day = DAY
	profile.dailies = [{"id": &"d_kills", "day": DAY, "progress": 0}]
	profile.orders = [{"id": &"o_boards", "progress": 0}]
	return profile


func _told(account: String, before: ChallengeProfile, after: ChallengeProfile) -> Array:
	return ProgressNews.challenges_after_read(account, before, after, _catalog, DAY)


# --- Levels ---


func test_the_menus_cards_for_a_level_are_the_nights() -> void:
	var award := XpAward.new([&"fuel_can"], ChallengeFixture.clock_on(DAY))
	award.register(1, "ann", LevelCurve.xp_for(TIER_LEVEL) - 5, 0)
	award.add_xp(1, 10, XpAward.CHALLENGE)
	var live: Array = []
	for event in award.end_tick(true):
		if event["type"] != XpAward.GAINED:
			live.append(event)
	var menu := ProgressNews.level_events(TIER_LEVEL - 1, TIER_LEVEL)
	var types: Array = []
	for event: Dictionary in menu:
		types.append(event["type"])
	assert_array(types).is_equal([&"level_up", &"tier_up", &"unlock_earned"])
	assert_int(menu.size()).is_equal(live.size())
	for at in live.size():
		for key: String in ["type", "level", "tier_name", "slot", "item"]:
			assert_that(menu[at].get(key)).is_equal(live[at].get(key))


func test_a_profile_ahead_of_the_cache_tells_the_levels_between_once() -> void:
	assert_array(_levels(ProgressNews.levels_after_read(ACCOUNT, 4, 7))).is_equal([5, 6, 7])
	# Read again (the next sign-in) with the cache the read made: nothing is new.
	assert_array(ProgressNews.levels_after_read(ACCOUNT, 7, 7)).is_empty()
	# Even with a cache that has not caught up, the ledger knows what was told.
	assert_array(ProgressNews.levels_after_read(ACCOUNT, 4, 7)).is_empty()


func test_a_level_the_night_showed_live_is_not_shown_again() -> void:
	# An online night: the server credited levels 5 to 9 and the HUD showed them; the cache is
	# the profile of the night before (level 4).
	ProgressSeen.note_level(5, ACCOUNT)
	ProgressSeen.note_level(9, ACCOUNT)
	assert_array(ProgressNews.levels_after_read(ACCOUNT, 4, 9)).is_empty()
	# Played on elsewhere to level 11: only the two new ones are told.
	assert_array(_levels(ProgressNews.levels_after_read(ACCOUNT, 4, 11))).is_equal([10, 11])


func test_a_solo_nights_levels_are_in_the_cache_and_not_told() -> void:
	# The solo night credited its XP to the cache at once (`ProfileStore.credit`) and showed the
	# levels live; the account's profile, read at the next sign-in, is the same level.
	assert_array(ProgressNews.levels_after_read(ACCOUNT, 8, 8)).is_empty()


func test_a_cache_that_is_not_this_accounts_is_no_baseline() -> void:
	# A new machine, or another account: nothing was earned here, so nothing is told, and what the
	# account holds is what is known from then on.
	assert_array(ProgressNews.levels_after_read(ACCOUNT, 0, 12)).is_empty()
	assert_int(ProgressSeen.open().level_for(ACCOUNT)).is_equal(12)
	assert_array(_levels(ProgressNews.levels_after_read(ACCOUNT, 0, 13))).is_equal([13])
	# Another account on the same machine starts its own ledger.
	assert_array(ProgressNews.levels_after_read(OTHER, 0, 3)).is_empty()
	assert_int(ProgressSeen.open().level_for(ACCOUNT)).is_equal(0)


func test_the_ledger_is_not_lowered_by_a_read_that_is_behind() -> void:
	ProgressSeen.note_level(9, ACCOUNT)
	assert_array(ProgressNews.levels_after_read(ACCOUNT, 9, 6)).is_empty()
	assert_int(ProgressSeen.open().level_for(ACCOUNT)).is_equal(9)


func test_no_file_keeps_nothing_and_a_damaged_one_is_empty() -> void:
	ProgressSeen.path = ""
	ProgressSeen.note_level(9, ACCOUNT)
	assert_int(ProgressSeen.open().level_for(ACCOUNT)).is_equal(0)
	var path := DIR + "damaged.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	assert_int(ProgressSeen.open(path).level).is_equal(0)


# --- Challenges ---


func test_a_challenge_the_account_finished_elsewhere_is_told() -> void:
	var after := _board()
	after.dailies[0]["progress"] = 8
	after.orders[0]["progress"] = 5
	var events := _told(ACCOUNT, _board(), after)
	assert_array(_ids(events)).contains_exactly_in_any_order([&"d_kills", &"o_boards"])
	for event: Dictionary in events:
		assert_str(str(event["type"])).is_equal("challenge_advanced")
		assert_bool(event["completed"]).is_true()
		assert_str(event["text"]).is_equal(_catalog.get_def(event["id"]).words())


func test_a_challenge_already_in_the_cache_is_not_told() -> void:
	# A solo night finished it (the cache has it): the night showed it, the read must not.
	var before := _board()
	before.dailies[0]["progress"] = 8
	var after := _board()
	after.dailies[0]["progress"] = 8
	assert_array(_told(ACCOUNT, before, after)).is_empty()


func test_a_challenge_the_night_showed_live_is_not_told_after_it() -> void:
	# An online night: the game server finished it and the HUD showed the card live; the cache
	# board, read before, does not have it yet.
	ProgressSeen.note_challenge(ChallengeDef.Family.DAILY, &"d_kills", ACCOUNT, DAY)
	var after := _board()
	after.dailies[0]["progress"] = 8
	after.orders[0]["progress"] = 5
	assert_array(_ids(_told(ACCOUNT, _board(), after))).is_equal([&"o_boards"])
	# The ledger is spent: the cache is the account's board from now on.
	assert_bool(ProgressSeen.open().told.is_empty()).is_true()


func test_a_daily_of_another_day_is_not_told() -> void:
	var after := _board()
	after.dailies[0]["progress"] = 8
	after.dailies[0]["day"] = DAY - 2
	assert_array(_told(ACCOUNT, _board(), after)).is_empty()


func test_an_order_the_account_finished_and_settled_is_told_from_the_recent_list() -> void:
	var after := _board()
	after.orders = []
	after.recent_orders = [&"o_cans"]
	assert_array(_ids(_told(ACCOUNT, _board(), after))).is_equal([&"o_cans"])
	# The cache has settled it too: not told.
	var settled := _board()
	settled.orders = []
	settled.recent_orders = [&"o_cans"]
	assert_array(_told(ACCOUNT, settled, after)).is_empty()


func test_a_ladder_is_told_when_its_last_step_is_reached() -> void:
	var before := _board()
	before.lifetime[&"kills"] = 20
	var after := _board()
	after.lifetime[&"kills"] = 40
	assert_array(_told(ACCOUNT, before, after)).is_empty()
	after.lifetime[&"kills"] = 50
	var events := _told(ACCOUNT, before, after)
	assert_array(_ids(events)).is_equal([&"m_kills"])
	assert_str(events[0]["text"]).is_equal("Put down 50")


func test_a_board_that_is_not_this_accounts_is_no_baseline() -> void:
	var after := _board()
	after.dailies[0]["progress"] = 8
	assert_array(_told(ACCOUNT, _board(OTHER), after)).is_empty()
	assert_array(_told(ACCOUNT, null, after)).is_empty()
