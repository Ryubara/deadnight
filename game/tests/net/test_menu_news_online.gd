extends GdUnitTestSuite
## The menu's popup lane told of progress by the real backend (#1130, `spikes/backend` run by Node
## on a free port with memory storage; see `BackendFixture`): a returning Guest signs in, the
## account's profile and challenge board are read, and the cards of what the account earned while
## this machine was away show over the menu once, through the game's own sign-in path
## (`TogetherApi` -> `ProfileUplink` and `ChallengeUplink`). A night's own cards are not told again.

const DIR := "user://test_menu_news_online/"
const WAIT_SECONDS := 20.0
const NEEDS := "needs node 24 and npm ci in spikes/backend"
const TIER_LEVEL := 6

var _backend: BackendFixture
var _menu: MenuPopups


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear()
	ProgressSeen.path = DIR + "seen.json"
	ProfileUplink.sync_path = DIR + "profile.json"
	ChallengeUplink.sync_path = DIR + "challenges.json"
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	_menu = MenuPopups.new()
	host.add_child(_menu)


func after_test() -> void:
	if _backend != null:
		_backend.stop()
		_backend = null
	_menu.free()
	TogetherApi.forget()
	ProgressSeen.path = ""
	ProfileUplink.sync_path = ""
	ChallengeUplink.sync_path = ""
	_clear()
	LevelIcons.release()


func _clear() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


func _until(done: Callable) -> void:
	var began := Time.get_ticks_msec()
	while not done.call() and (Time.get_ticks_msec() - began) / 1000.0 < WAIT_SECONDS:
		await get_tree().create_timer(0.05).timeout
	assert_bool(done.call()).is_true()


func _kinds() -> Array:
	var out: Array = []
	for card in _menu.lane.queue.shown:
		out.append(card.kind)
	for card in _menu.lane.queue.waiting:
		out.append(card.kind)
	return out


## A returning guest of a backend, as the game's start-up sign-in makes one: a first visit that
## makes the account (and its credential), then no session, and `StartupSignIn` on the next.
func _first_visit() -> String:
	_backend = BackendFixture.new()
	assert_bool(await _backend.start(self)).is_true()
	var first := TogetherApi.new(self, _backend.url)
	first.guest_path = DIR + "guest.json"
	assert_bool((await first.sign_in("Gus"))["ok"]).is_true()
	# Its own sync (the first sign-in's) has made the files: wait for them, then spend them.
	await _until(
		func() -> bool:
			return (
				FileAccess.file_exists(ProfileUplink.sync_path)
				and FileAccess.file_exists(ChallengeUplink.sync_path)
			)
	)
	return TogetherApi.account_id()


## The account earned `xp` in a night elsewhere: a game server's report, as the backend takes it.
func _credit(account: String, xp: int) -> void:
	var sent := await HttpJson.send(
		self,
		"POST",
		"%s/internal/matches/seed-news/report" % _backend.url,
		{"Authorization": "Bearer " + BackendFixture.GAME_SERVER_SECRET},
		{"kind": "night", "round": 0, "seats": [{"userId": account, "xp": xp}]}
	)
	assert_int(sent["status"]).is_equal(200)


func _return_to_the_backend() -> TogetherApi:
	TogetherApi.forget()
	var api := TogetherApi.new(self, _backend.url)
	api.guest_path = DIR + "guest.json"
	assert_bool(StartupSignIn.wanted(api)).is_true()
	assert_bool((await StartupSignIn.run(api))["ok"]).is_true()
	return api


func test_a_level_and_a_challenge_earned_elsewhere_show_over_the_menu_after_sign_in(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	var account := await _first_visit()
	var api := TogetherApi.new(self, _backend.url)
	api.guest_path = DIR + "guest.json"
	# The account, played on another machine: level 6, and an order done.
	var order := ChallengeCatalog.load_default().of_family(ChallengeDef.Family.ORDER)[0]
	var elsewhere := ChallengeProfile.fresh_for(account)
	elsewhere.orders = [{"id": order.id, "progress": order.target}]
	var read := await api.read_save(ChallengeUplink.SLOT)
	assert_bool(read["ok"]).is_true()
	(
		assert_bool(
			(await api.write_save(
				ChallengeUplink.SLOT, int(read["revision"]), 1, elsewhere.to_dict()
			))["ok"]
		)
		. is_true()
	)
	await _credit(account, LevelCurve.xp_for(TIER_LEVEL) + 3)
	# This machine's caches, from before: the same account, level 4 and the order not yet done.
	var cached := ProfileStore.open(ProfileUplink.sync_path)
	cached.account = account
	cached.profile.xp = LevelCurve.xp_for(4) + 1
	cached.save()
	var board := ChallengeProfile.fresh_for(account)
	board.orders = [{"id": order.id, "progress": 0}]
	assert_bool(ChallengeSave.write(board, ChallengeUplink.sync_path)).is_true()
	assert_int(_kinds().size()).is_equal(0)
	# The next start: a returning guest signs in, the account is read, the cards come.
	await _return_to_the_backend()
	await _until(func() -> bool: return _kinds().has(PopupQueue.Kind.CHALLENGE))
	await _until(func() -> bool: return _kinds().has(PopupQueue.Kind.TIER))
	assert_int(ProfileStore.open(ProfileUplink.sync_path).profile.level()).is_equal(TIER_LEVEL)
	var told := _kinds().duplicate()
	assert_int(told.count(PopupQueue.Kind.CHALLENGE)).is_equal(1)
	# Levels 5 and 6: the level 5 card, then level 6 made a tier card with its hat.
	assert_int(told.count(PopupQueue.Kind.TIER)).is_equal(1)
	# Another start with nothing new: not told again.
	_menu.lane.clear()
	await _return_to_the_backend()
	await get_tree().create_timer(0.8).timeout
	assert_array(_kinds()).is_empty()


func test_a_returning_guests_cache_that_is_current_shows_nothing(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := NEEDS
) -> void:
	var account := await _first_visit()
	await _credit(account, LevelCurve.xp_for(8))
	var held := {"xp": LevelCurve.xp_for(8)}
	var cached := ProfileStore.open(ProfileUplink.sync_path)
	cached.account = account
	cached.profile.xp = LevelCurve.xp_for(8)
	cached.save()
	await _return_to_the_backend()
	await _until(
		func() -> bool: return ProfileStore.open(ProfileUplink.sync_path).profile.xp == held["xp"]
	)
	await get_tree().create_timer(0.8).timeout
	assert_array(_kinds()).is_empty()
