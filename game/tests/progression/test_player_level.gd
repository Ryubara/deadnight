# The level of the person at this machine (`PlayerLevel`), read from the cached profile: a Guest
# account is a real account with a level, a player with no file is level 1, and a test can put a
# level in.
extends GdUnitTestSuite

const PATH := "user://player_level_test.json"


func after_test() -> void:
	PlayerLevel.reset()
	for path in [PATH, PATH + ".broken", PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write(xp: int) -> void:
	var profile := Profile.new()
	profile.xp = xp
	assert_bool(ProfileSave.write(profile, [], 1, PATH)).is_true()


func test_no_profile_is_level_1() -> void:
	assert_int(PlayerLevel.local(PATH)).is_equal(1)


func test_the_cached_profile_decides_the_level() -> void:
	_write(LevelCurve.xp_for(10))
	assert_int(PlayerLevel.local(PATH)).is_equal(10)
	_write(LevelCurve.xp_for(10) - 1)
	assert_int(PlayerLevel.local(PATH)).is_equal(9)
	_write(LevelCurve.xp_for(55) + 5000)
	assert_int(PlayerLevel.local(PATH)).is_equal(LevelCurve.MAX_LEVEL)


func test_a_damaged_file_is_level_1() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	assert_int(PlayerLevel.local(PATH)).is_equal(1)


func test_a_test_can_put_a_level_in_and_take_it_out() -> void:
	PlayerLevel.use(12)
	assert_int(PlayerLevel.local(PATH)).is_equal(12)
	PlayerLevel.use(900)
	assert_int(PlayerLevel.local(PATH)).is_equal(LevelCurve.MAX_LEVEL)
	PlayerLevel.reset()
	assert_int(PlayerLevel.local(PATH)).is_equal(1)
