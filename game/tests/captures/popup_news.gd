extends Node
## The popup lane over the menu told by a real source (#1130): the real backend (Node, memory
## storage), a returning Guest whose account earned a level and a finished order while this
## machine was away, and the game's own start-up sign-in (`StartupSignIn`) reading the account's
## profile and board into the caches. Nothing here announces a card: `ProfileUplink` and
## `ChallengeUplink` do, as in the game. The files it keeps are its own, under
## `user://news_capture/`, and removed at the end. Not part of the game.
##
## Record: `gds godot -- --path game res://tests/captures/popup_news.tscn --write-movie <abs>/m.png
## --fixed-fps 10 --resolution 1280x720`. Prints `NEWS <seconds> <what>` as things happen.

const DIR := "user://news_capture/"
## The level this machine's cache knows, and the level the account holds.
const CACHED := 11
const ACCOUNT_LEVEL := 12
const HOLD_SECONDS := 6.0
const GIVE_UP_SECONDS := 60.0

var _backend: BackendFixture
var _clock := 0.0
var _shown_at := -1.0
var _done := false


func _ready() -> void:
	set_process(false)
	UIMotion.reduced = false
	Settings.path = DIR + "settings.cfg"
	DirAccess.make_dir_recursive_absolute(DIR)
	Settings.reset_defaults()
	ProgressSeen.path = DIR + "seen.json"
	ProfileUplink.sync_path = DIR + "profile.json"
	ChallengeUplink.sync_path = DIR + "challenges.json"
	UIRouter.add_child(MenuPopups.new())
	UIRouter.reset("res://ui/screens/main_menu.tscn", UITransition.Kind.CUT)
	_backend = BackendFixture.new()
	if not await _backend.start(self):
		return _finish("no backend: %s" % BackendFixture.why_not())
	await _prepare_account()
	print("NEWS %.1f start-up sign-in" % _clock)
	var begun := StartupSignIn.begin(self, _backend.url, DIR + "guest.json")
	if begun == null:
		return _finish("no sign-in started")
	await get_tree().create_timer(0.1).timeout
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	var lane := MenuPopups.instance.lane
	if _shown_at < 0.0 and not lane.queue.shown.is_empty():
		_shown_at = _clock
		print("NEWS %.1f first card" % _clock)
	if (_shown_at >= 0.0 and _clock - _shown_at >= HOLD_SECONDS) or _clock > GIVE_UP_SECONDS:
		_finish("done")


## A first visit made the account; another machine then played it to level 12 and finished an
## order (a game server's report, and the board written to the account); this machine's caches are
## from before, at level 11 with the order not done.
func _prepare_account() -> void:
	var first := TogetherApi.new(self, _backend.url)
	first.guest_path = DIR + "guest.json"
	await first.sign_in("Gus")
	var account := TogetherApi.account_id()
	await _until_files()
	var catalog := ChallengeCatalog.load_default()
	var order := catalog.of_family(ChallengeDef.Family.ORDER)[0]
	var elsewhere := ChallengeProfile.fresh_for(account)
	elsewhere.orders = [{"id": order.id, "progress": order.target}]
	var read := await first.read_save(ChallengeUplink.SLOT)
	await first.write_save(ChallengeUplink.SLOT, int(read["revision"]), 1, elsewhere.to_dict())
	await HttpJson.send(
		self,
		"POST",
		"%s/internal/matches/seed-news/report" % _backend.url,
		{"Authorization": "Bearer " + BackendFixture.GAME_SERVER_SECRET},
		{
			"kind": "night",
			"round": 0,
			"seats": [{"userId": account, "xp": LevelCurve.xp_for(ACCOUNT_LEVEL) + 5}]
		}
	)
	var cached := ProfileStore.open(ProfileUplink.sync_path)
	cached.account = account
	cached.profile.xp = LevelCurve.xp_for(CACHED) + 5
	cached.save()
	var board := ChallengeProfile.fresh_for(account)
	board.orders = [{"id": order.id, "progress": 0}]
	ChallengeSave.write(board, ChallengeUplink.sync_path)
	TogetherApi.forget()


func _until_files() -> void:
	var began := Time.get_ticks_msec()
	while (
		not (
			FileAccess.file_exists(ProfileUplink.sync_path)
			and FileAccess.file_exists(ChallengeUplink.sync_path)
		)
		and Time.get_ticks_msec() - began < 10000
	):
		await get_tree().create_timer(0.05).timeout


func _finish(why: String) -> void:
	if _done:
		return
	_done = true
	print("NEWS %.1f %s" % [_clock, why])
	if _backend != null:
		_backend.stop()
	TogetherApi.forget()
	ProgressSeen.path = ""
	ProfileUplink.sync_path = ""
	ChallengeUplink.sync_path = ""
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)
	DirAccess.remove_absolute(DIR)
	Settings.reset_defaults()
	get_tree().quit()
