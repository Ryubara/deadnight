extends GdUnitTestSuite
## The menu says one level (#1153). The start-up sign-in reads the account's profile after the
## menu is up (`ProfileUplink.adopt_and_tell` writes the profile file and tells `ProfileFeed`), so
## the level plate, the wardrobe's locks, the shop's "Yours" and the stage's unlocks follow the
## file at once, beside the LEVEL UP cards the same read makes. The menu is the real one, shown by
## the router; the read is the one the sign-in makes, with the answer a backend gives.

const MENU := "res://ui/screens/main_menu.tscn"
const DIR := "user://test_menu_follows_account/"
const ACCOUNT := "account-one"
const CACHED := 4
const ACCOUNT_LEVEL := 12

var _path_before: String
var _settings_before: String


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear()
	_settings_before = Settings.path
	Settings.reset_defaults()
	_path_before = MenuProfile.profile_path
	MenuProfile.profile_path = DIR + "profile.json"
	_write(LevelCurve.xp_for(CACHED) + 5)
	MainMenu.board_factory = func() -> Object: return FakeChallengeBoard.new()
	UIInputMode.reset()


func after_test() -> void:
	MainMenu.board_factory = Callable()
	MenuProfile.profile_path = _path_before
	Settings.reset_defaults()
	Settings.path = _settings_before
	await RouterFixture.clear(get_tree())
	_clear()
	LevelIcons.release()


func _clear() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


## The cache this machine holds: `xp` of ACCOUNT's, in the profile file the menu reads.
func _write(xp: int) -> ProfileStore:
	var store := ProfileStore.open(DIR + "profile.json", func() -> bool: return true)
	store.account = ACCOUNT
	store.profile.xp = xp
	store.save()
	return store


func _show() -> MainMenu:
	UIRouter.reset(MENU, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	return UIRouter.top() as MainMenu


## The account's profile as the backend answers a read, at `level` and `extra` XP over it.
func _answer(level: int, extra := 5) -> Dictionary:
	return {
		"ok": true,
		"found": true,
		"revision": 7,
		"schema_version": ProfileSave.SCHEMA_VERSION,
		"data": {"xp": LevelCurve.xp_for(level) + extra},
	}


func _locked_cells(menu: MainMenu) -> int:
	var count := 0
	var wardrobe := (menu.shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel).wardrobe
	for found in wardrobe.find_children("*", "Button", true, false):
		if found is WardrobeCell and (found as WardrobeCell).locked:
			count += 1
	return count


func _yours(menu: MainMenu) -> int:
	var count := 0
	for entry in (menu.shell.panel(MenuTab.Id.SHOP) as ShopPanel).entries():
		count += 1 if str(entry["how"]) == "Yours" else 0
	return count


func test_the_plate_and_the_locks_show_the_level_the_account_read_brings() -> void:
	var menu := await _show()
	var shell := menu.shell
	assert_str(shell.plate.level_text()).is_equal("LEVEL %d" % CACHED)
	var locked_before := _locked_cells(menu)
	var yours_before := _yours(menu)
	# The sign-in's read lands: the account is at level 12, this machine knew level 4.
	ProfileUplink.adopt_and_tell(
		_write(LevelCurve.xp_for(CACHED) + 5), _answer(ACCOUNT_LEVEL), ACCOUNT
	)
	assert_str(shell.plate.level_text()).is_equal("LEVEL %d" % ACCOUNT_LEVEL)
	assert_int(shell.context.profile.level()).is_equal(ACCOUNT_LEVEL)
	assert_int(shell.view.unlocks.level).is_equal(ACCOUNT_LEVEL)
	assert_int(_locked_cells(menu)).is_less(locked_before)
	assert_int(_yours(menu)).is_greater(yours_before)
	# The ring and the number in it say the same level as the words.
	assert_float(shell.plate.level_fraction()).is_equal_approx(
		shell.context.profile.level_fraction(), 0.001
	)


func test_the_cards_and_the_plate_say_one_level() -> void:
	var popups := MenuPopups.new()
	add_child(popups)
	var menu := await _show()
	ProfileUplink.adopt_and_tell(
		_write(LevelCurve.xp_for(CACHED) + 5), _answer(ACCOUNT_LEVEL), ACCOUNT
	)
	var top := 0
	for card in popups.lane.queue.shown + popups.lane.queue.waiting:
		top = maxi(top, int(card.data.get("level", 0)))
	assert_int(top).is_greater(CACHED)
	assert_str(menu.shell.plate.level_text()).is_equal("LEVEL %d" % ACCOUNT_LEVEL)
	popups.free()


func test_a_read_that_brings_nothing_new_leaves_the_menu_alone() -> void:
	var menu := await _show()
	var shown_before := menu.shell.context.profile
	ProfileUplink.adopt_and_tell(_write(LevelCurve.xp_for(CACHED) + 5), _answer(CACHED), ACCOUNT)
	assert_object(menu.shell.context.profile).is_same(shown_before)
	assert_str(menu.shell.plate.level_text()).is_equal("LEVEL %d" % CACHED)


func test_a_menu_that_is_gone_does_not_hear_the_read() -> void:
	var menu := await _show()
	await RouterFixture.clear(get_tree())
	assert_bool(is_instance_valid(menu)).is_false()
	ProfileUplink.adopt_and_tell(
		_write(LevelCurve.xp_for(CACHED) + 5), _answer(ACCOUNT_LEVEL), ACCOUNT
	)
	assert_int(ProfileFeed.shared.adopted.get_connections().size()).is_equal(0)


func test_a_level_gained_while_the_menu_is_covered_opens_the_wardrobe_when_it_is_shown_again(
) -> void:
	var menu := await _show()
	var locked_before := _locked_cells(menu)
	_write(LevelCurve.xp_for(ACCOUNT_LEVEL) + 5)
	menu.shell.set_profile(MenuProfile.load_saved())
	assert_int(_locked_cells(menu)).is_less(locked_before)
