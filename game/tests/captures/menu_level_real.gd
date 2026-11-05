extends Node
## What the real `Main` menu shows of the level when the account's profile is read after it is up
## (#1153): the plate, the wardrobe's locks, the shop's "Yours", the stage's unlocks. Nothing here
## draws or announces: the real backend (Node, memory storage), a first visit that makes a Guest
## account, another machine that plays it to a level above this machine's cache, and then
## `main.tscn` itself, started as the game starts it, with the start-up sign-in
## (`StartupSignIn`, which a run of `res://tests/` leaves out, so it is called here with the same
## arguments Main gives it) reading the account's profile. The caches are in the user data folder:
## run this with the process's `APPDATA` pointing at a folder of its own, so they are the real
## paths (`user://profile.json`, `user://guest_account.json`) of a throwaway user and never the
## person's. Not part of the game.
##
## `APPDATA=<dir> gds godot -- --path game res://tests/captures/menu_level_real.tscn --write-movie
## <abs>/m.png --fixed-fps 10 --resolution 1280x720`. Prints `LEVELPLATE <frame> <what>` on change.

const CACHED := 4
const ACCOUNT_LEVEL := 12
const HOLD_SECONDS := 8.0
const GIVE_UP_SECONDS := 90.0
const SEEN := "user://progress_seen.json"

var _backend: BackendFixture
var _menu: MainMenu
var _clock := 0.0
var _landed_at := -1.0
var _last := ""
var _done := false


func _ready() -> void:
	set_process(false)
	UIMotion.reduced = false
	var folder := OS.get_user_data_dir()
	print("LEVELPLATE 0 user data folder: ", folder)
	_backend = BackendFixture.new()
	if not await _backend.start(self):
		return _finish("no backend: %s" % BackendFixture.why_not())
	await _prepare_account()
	var main := (load("res://main.tscn") as PackedScene).instantiate() as Control
	add_child(main)
	var waited := 0
	while (
		not (UIRouter.top() is MainMenu and (UIRouter.top() as MainMenu).has_entered())
		and waited < 600
	):
		await get_tree().process_frame
		waited += 1
	_menu = UIRouter.top() as MainMenu
	if _menu == null:
		return _finish("the menu is not up: %s" % UIRouter.top())
	print("LEVELPLATE %d sign-in begins" % Engine.get_frames_drawn())
	if StartupSignIn.begin(self, _backend.url, GuestAccount.DEFAULT_PATH) == null:
		return _finish("no sign-in started")
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	var now := _report()
	if now != _last:
		_last = now
		print("LEVELPLATE %d %s" % [Engine.get_frames_drawn(), now])
	var file_level := ProfileStore.open(ProfileSave.DEFAULT_PATH).profile.level()
	if _landed_at < 0.0 and file_level == ACCOUNT_LEVEL:
		_landed_at = _clock
	if (_landed_at >= 0.0 and _clock - _landed_at >= HOLD_SECONDS) or _clock > GIVE_UP_SECONDS:
		_finish("done")


## What the menu says of the level right now.
func _report() -> String:
	var shell := _menu.shell
	var loadout := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
	var locked := 0
	var cells := 0
	for found in loadout.wardrobe.find_children("*", "Button", true, false):
		if found is WardrobeCell:
			cells += 1
			locked += 1 if (found as WardrobeCell).locked else 0
	var shop := shell.panel(MenuTab.Id.SHOP) as ShopPanel
	var yours := 0
	for entry in shop.entries():
		yours += 1 if str(entry["how"]) == "Yours" else 0
	return (
		"plate '%s' | file %d | context %d | stage %d | wardrobe %d of %d locked | shop %d | cards %d"
		% [
			shell.plate.level_text(),
			ProfileStore.open(ProfileSave.DEFAULT_PATH).profile.level(),
			shell.context.profile.level(),
			shell.view.unlocks.level,
			locked,
			cells,
			yours,
			MenuPopups.instance.lane.queue.shown.size() if MenuPopups.instance != null else -1,
		]
	)


## A first visit made the account; another machine then played it to level 12 (a game server's
## report); this machine's cache is from before, at level 4, in the profile file the game keeps.
func _prepare_account() -> void:
	ProfileUplink.sync_path = ProfileSave.DEFAULT_PATH
	var first := TogetherApi.new(self, _backend.url)
	first.guest_path = GuestAccount.DEFAULT_PATH
	assert((await first.sign_in("Gus"))["ok"])
	var account := TogetherApi.account_id()
	var began := Time.get_ticks_msec()
	while (
		not FileAccess.file_exists(ProfileSave.DEFAULT_PATH)
		and Time.get_ticks_msec() - began < 10000
	):
		await get_tree().create_timer(0.05).timeout
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
	var cached := ProfileStore.open(ProfileSave.DEFAULT_PATH)
	cached.account = account
	cached.profile.xp = LevelCurve.xp_for(CACHED) + 5
	cached.save()
	TogetherApi.forget()
	ProfileUplink.sync_path = ""


func _finish(why: String) -> void:
	if _done:
		return
	_done = true
	print("LEVELPLATE %d %s" % [Engine.get_frames_drawn(), why])
	if _backend != null:
		_backend.stop()
	TogetherApi.forget()
	get_tree().quit()
