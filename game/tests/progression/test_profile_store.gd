extends GdUnitTestSuite
## The profile and its file: a save round trip, a damaged and a newer file, no XP for a night with
## no account, and a
## retry queue that keeps a write the backend refused.

const DIR := "user://test_profile/"

var _account := true


func _path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR + name + ".json"
	for leftover in [path, path + ".tmp", path + ".broken"]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(leftover)
	return path


func _store(name: String, with_account: bool = true) -> ProfileStore:
	_account = with_account
	var store := ProfileStore.open(_path(name), func() -> bool: return _account)
	store.seed_ids(7)
	return store


func test_a_profile_round_trips_through_its_file() -> void:
	var store := _store("round_trip")
	store.profile.equipped = {"card": "admit_one"}
	store.profile.mark_done(&"d_kills_40")
	assert_bool(store.credit(300, true, 20401)).is_true()
	var again := ProfileStore.open(store.path)
	assert_int(again.profile.xp).is_equal(300)
	assert_bool(again.profile.opening_night).is_true()
	assert_int(again.profile.bonus_day).is_equal(20401)
	assert_str(again.profile.equipped["card"]).is_equal("admit_one")
	assert_array(again.profile.done).is_equal([&"d_kills_40"])
	assert_int(again.queue.size()).is_equal(1)
	assert_int(again.revision).is_equal(store.revision)


func test_a_new_player_has_nothing_and_the_level_is_computed_not_stored() -> void:
	var store := _store("fresh")
	assert_int(store.profile.xp).is_zero()
	assert_int(store.profile.level()).is_equal(1)
	assert_bool(store.profile.opening_night).is_false()
	assert_int(store.profile.bonus_day).is_equal(Profile.NO_DAY)
	store.credit(LevelCurve.xp_for(10), false)
	var text := FileAccess.get_file_as_string(store.path)
	assert_bool(text.contains("level")).is_false()
	assert_int(ProfileStore.open(store.path).profile.level()).is_equal(10)


func test_a_damaged_file_is_set_aside_and_play_starts_fresh() -> void:
	var path := _path("damaged")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var store := ProfileStore.open(path)
	assert_int(store.profile.xp).is_zero()
	assert_bool(FileAccess.file_exists(path + ".broken")).is_true()
	assert_bool(FileAccess.file_exists(path)).is_false()
	assert_bool(ProfileSave.from_json("[1, 2]")["problem"] == ProfileSave.UNREADABLE).is_true()


func test_a_newer_schema_is_left_alone_never_overwritten() -> void:
	var path := _path("newer")
	var text := '{"revision": 9, "schemaVersion": 99, "data": {"xp": 5}}'
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var store := ProfileStore.open(path, func() -> bool: return true)
	assert_bool(store.problem == ProfileSave.NEWER_VERSION).is_true()
	assert_int(store.profile.xp).is_zero()
	# The night still plays and the player still sees the XP they earn, but the file stays.
	store.credit(100)
	assert_bool(store.save()).is_false()
	assert_str(FileAccess.get_file_as_string(path)).is_equal(text)


func test_a_night_with_no_account_earns_nothing_and_writes_nothing() -> void:
	var store := _store("no_account", false)
	assert_bool(store.credit(500, true, 20401)).is_false()
	assert_int(store.profile.xp).is_zero()
	assert_bool(store.profile.opening_night).is_false()
	assert_bool(store.queue.is_empty()).is_true()
	assert_bool(FileAccess.file_exists(store.path)).is_false()
	store.finished(&"d_kills_40")
	assert_bool(store.profile.done.is_empty()).is_true()


func test_getting_an_account_later_does_not_bring_the_earlier_nights_with_it() -> void:
	var store := _store("late", false)
	store.credit(500)
	_account = true
	assert_int(store.profile.xp).is_zero()
	store.credit(40)
	assert_int(store.profile.xp).is_equal(40)


func test_a_refused_write_stays_queued_and_is_sent_again_unchanged() -> void:
	var store := _store("retry")
	store.credit(120)
	store.credit(80)
	assert_int(store.queue.size()).is_equal(2)
	var first_id: String = store.queue[0]["id"]
	var seen: Array[String] = []
	# The backend refuses: nothing leaves the queue, and the cached profile keeps the XP.
	assert_int(store.flush(func(_write: Dictionary) -> bool: return false)).is_zero()
	assert_int(store.queue.size()).is_equal(2)
	assert_int(store.profile.xp).is_equal(200)
	# The file carries the queue, so a restart still has it.
	assert_int(ProfileStore.open(store.path).queue.size()).is_equal(2)
	# It takes the first and refuses the second.
	var taken := store.flush(
		func(write: Dictionary) -> bool:
			seen.append(write["id"])
			return seen.size() == 1
	)
	assert_int(taken).is_equal(1)
	assert_int(store.queue.size()).is_equal(1)
	assert_int(store.queue[0]["xp"]).is_equal(80)
	# Then everything goes, oldest first, with the ids it had before.
	var resent: Array[String] = []
	var rest := store.flush(
		func(write: Dictionary) -> bool:
			resent.append(write["id"])
			return true
	)
	assert_int(rest).is_equal(1)
	assert_bool(store.queue.is_empty()).is_true()
	assert_str(seen[0]).is_equal(first_id)
	assert_array(resent).is_equal([seen[1]])
	assert_bool(ProfileStore.open(store.path).queue.is_empty()).is_true()


func test_xp_past_the_top_is_kept() -> void:
	var store := _store("top")
	store.credit(LevelCurve.total() + 700)
	assert_int(store.profile.level()).is_equal(LevelCurve.MAX_LEVEL)
	assert_int(ProfileStore.open(store.path).profile.xp).is_equal(LevelCurve.total() + 700)


func test_a_garbled_field_falls_back_to_its_start() -> void:
	var damaged := {"xp": -5, "equipped": "no", "done": 3, "opening_night": "yes", "bonus_day": "x"}
	var profile := Profile.from_dict(damaged)
	assert_int(profile.xp).is_zero()
	assert_bool(profile.equipped.is_empty()).is_true()
	assert_bool(profile.done.is_empty()).is_true()
	assert_bool(profile.opening_night).is_false()
	assert_int(profile.bonus_day).is_equal(Profile.NO_DAY)
