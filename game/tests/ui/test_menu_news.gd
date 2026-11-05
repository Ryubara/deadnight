extends GdUnitTestSuite
## The menu's popup lane wired to the places that learn of progress while no night is up (#1130),
## through the real objects: a profile read at sign-in (`ProfileUplink.adopt_and_tell`), the lane
## that holds what comes during a night, and the live notes a night's HUD and challenge link leave
## so that a card shown in the night is not shown again in the menu.

const DIR := "user://test_menu_news/"
const ACCOUNT := "account-one"
const TIER_LEVEL := 6

var _host: Control
var _menu: MenuPopups


func before_test() -> void:
	UIMotion.reduced = false
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear()
	ProgressSeen.path = DIR + "seen.json"
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)
	_menu = MenuPopups.new()
	_host.add_child(_menu)
	await await_idle_frame()


func after_test() -> void:
	MenuPopups.set_night(false)
	_menu.free()
	ProgressSeen.path = ""
	TogetherApi.forget()
	_clear()
	LevelIcons.release()


func _clear() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


## How many cards the lane has made (showing or waiting).
func _cards() -> int:
	return _menu.lane.queue.shown.size() + _menu.lane.queue.waiting.size()


## The kinds of the cards the lane holds, in order.
func _kinds() -> Array:
	var out: Array = []
	for card in _menu.lane.queue.shown:
		out.append(card.kind)
	for card in _menu.lane.queue.waiting:
		out.append(card.kind)
	return out


## A store for ACCOUNT whose cache is at `xp`.
func _store(xp: int) -> ProfileStore:
	var store := ProfileStore.open(DIR + "profile.json", func() -> bool: return true)
	store.account = ACCOUNT
	store.profile.xp = xp
	store.save()
	return store


func _answer(xp: int) -> Dictionary:
	return {"found": true, "revision": 3, "schema_version": 1, "data": {"xp": xp}}


# --- The profile read at sign-in ---


func test_a_profile_read_at_a_higher_level_than_the_cache_shows_its_cards_once() -> void:
	var store := _store(LevelCurve.xp_for(TIER_LEVEL - 1))
	var ahead := LevelCurve.xp_for(TIER_LEVEL) + 3
	ProfileUplink.adopt_and_tell(store, _answer(ahead), ACCOUNT)
	# The cards of the night: the level's card made a tier card, and the hat the level gives.
	assert_array(_kinds()).contains_exactly([PopupQueue.Kind.TIER, PopupQueue.Kind.UNLOCK])
	assert_int(store.profile.level()).is_equal(TIER_LEVEL)
	# The next sign-in reads the same profile: nothing again.
	_menu.lane.clear()
	ProfileUplink.adopt_and_tell(ProfileStore.open(store.path), _answer(ahead), ACCOUNT)
	assert_int(_cards()).is_equal(0)


func test_a_profile_at_the_caches_level_shows_nothing() -> void:
	# A signed-in solo night: its XP is in the cache already, and the night showed its levels.
	var xp := LevelCurve.xp_for(TIER_LEVEL) + 3
	ProfileUplink.adopt_and_tell(_store(xp), _answer(xp), ACCOUNT)
	assert_int(_cards()).is_equal(0)


func test_a_profile_read_on_a_machine_that_never_knew_the_account_shows_nothing() -> void:
	var store := ProfileStore.open(DIR + "fresh.json", func() -> bool: return true)
	ProfileUplink.adopt_and_tell(store, _answer(LevelCurve.xp_for(20)), ACCOUNT)
	assert_int(_cards()).is_equal(0)
	assert_int(store.profile.level()).is_equal(20)


func test_a_level_the_nights_hud_showed_live_is_not_shown_in_the_menu() -> void:
	TogetherApi._user = {"id": ACCOUNT}
	var state := ClientState.new()
	state.player_id = 1
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var hud := HudFixture.make(host).hud
	var binding := NightHudBinding.new(hud, state, load(HudFixture.TUNING) as RulesTuning)
	# An online night: the server tells the local player's level, the HUD's lane shows it.
	state.apply_events(
		XpAward.crossing(1, TIER_LEVEL, LevelCurve.xp_for(TIER_LEVEL), LadderUnlocks.shipped())
	)
	assert_object(binding).is_not_null()
	assert_int(hud.popups.queue.waiting.size() + hud.popups.queue.shown.size()).is_greater(0)
	assert_int(ProgressSeen.open().level_for(ACCOUNT)).is_equal(TIER_LEVEL)
	# Back in the menu the cache is the night before's: the level is not told again.
	var store := _store(LevelCurve.xp_for(TIER_LEVEL - 2))
	ProfileUplink.adopt_and_tell(store, _answer(LevelCurve.xp_for(TIER_LEVEL) + 3), ACCOUNT)
	assert_int(_cards()).is_equal(0)
	# A level made elsewhere after that night is new.
	ProfileUplink.adopt_and_tell(
		_store(LevelCurve.xp_for(TIER_LEVEL) + 3),
		_answer(LevelCurve.xp_for(TIER_LEVEL + 1)),
		ACCOUNT
	)
	assert_int(_cards()).is_greater(0)
	assert_int(_menu.lane.queue.shown.size() + _menu.lane.queue.waiting.size()).is_equal(
		ProgressNews.level_events(TIER_LEVEL, TIER_LEVEL + 1).size()
	)


func test_a_challenge_the_nights_link_showed_live_is_not_shown_in_the_menu() -> void:
	TogetherApi._user = {"id": ACCOUNT}
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var hud := HudFixture.make(host).hud
	var board := ChallengeBoard.open(
		ChallengeFixture.save_path("news"),
		ChallengeFixture.clock_on(20401),
		ChallengeFixture.small_catalog()
	)
	var session := ChallengeSession.new(board)
	var settings: QuietSettings = auto_free(QuietSettings.make(self, DIR + "settings.cfg"))
	var link := ChallengeHudLink.new(session, hud, settings)
	(
		session
		. advanced
		. emit(
			{
				"id": &"o_boards",
				"family": ChallengeDef.Family.ORDER,
				"text": "Do boards_repaired 5",
				"completed": true,
			}
		)
	)
	assert_object(link).is_not_null()
	assert_bool(ProgressSeen.open().was_told(ACCOUNT, "order:o_boards")).is_true()
	# Not a step on the way: nothing is kept for it.
	session.advanced.emit(
		{"id": &"o_cans", "family": ChallengeDef.Family.ORDER, "completed": false}
	)
	assert_bool(ProgressSeen.open().was_told(ACCOUNT, "order:o_cans")).is_false()


# --- The lane while a night is up ---


func test_what_comes_during_a_night_waits_for_the_night_to_go_and_shows_once() -> void:
	MenuPopups.set_night(true)
	MenuPopups.announce(ProgressNews.level_events(TIER_LEVEL - 1, TIER_LEVEL))
	assert_int(_cards()).is_equal(0)
	MenuPopups.set_night(false)
	assert_int(_cards()).is_equal(2)
	# The night going a second time (a screen replaced) shows nothing more.
	MenuPopups.set_night(false)
	assert_int(_cards()).is_equal(2)


func test_a_night_putting_the_lane_away_drops_the_cards_of_the_menu() -> void:
	MenuPopups.announce(ProgressNews.level_events(TIER_LEVEL - 1, TIER_LEVEL))
	assert_int(_cards()).is_equal(2)
	MenuPopups.set_night(true)
	assert_int(_cards()).is_equal(0)
