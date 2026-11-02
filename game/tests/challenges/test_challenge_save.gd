extends GdUnitTestSuite
## The save: the envelope and its schema version, a round trip that loses nothing, and a file that
## cannot be read or is from a newer game never taking progress down with it.

const DAY := 20401

var _catalog: ChallengeCatalog


func before_test() -> void:
	_catalog = ChallengeCatalog.load_default()


func _busy_profile() -> ChallengeProfile:
	var profile := ChallengeProfile.fresh(77)
	profile.refresh(_catalog, DAY)
	profile.refresh(_catalog, DAY + 1)
	profile.dailies[0]["progress"] = 3
	profile.dailies[4]["progress"] = 2
	profile.orders[1]["progress"] = 5
	profile.apply(_catalog, &"kills", 120, 120)
	profile.apply(_catalog, &"round", 6, 6)
	profile.finished["daily"] = 4
	profile.recent_orders.append(&"o_round_8")
	return profile


func test_the_envelope_carries_the_schema_version_and_the_revision() -> void:
	var profile := _busy_profile()
	profile.revision = 9
	var envelope: Dictionary = JSON.parse_string(ChallengeSave.to_json(profile))
	assert_int(int(envelope["schemaVersion"])).is_equal(ChallengeSave.SCHEMA_VERSION)
	assert_int(int(envelope["revision"])).is_equal(9)
	assert_bool(envelope["data"] is Dictionary).is_true()


func test_a_round_trip_through_text_loses_nothing() -> void:
	var profile := _busy_profile()
	var result := ChallengeSave.from_json(ChallengeSave.to_json(profile))
	assert_str(result["problem"]).is_equal("")
	var back: ChallengeProfile = result["profile"]
	assert_dict(back.to_dict()).is_equal(profile.to_dict())
	assert_int(back.dealt_day).is_equal(DAY + 1)


func test_a_round_trip_through_a_file_loses_nothing_and_counts_revisions() -> void:
	var path := ChallengeFixture.save_path("round_trip")
	var profile := _busy_profile()
	assert_bool(ChallengeSave.write(profile, path)).is_true()
	assert_bool(ChallengeSave.write(profile, path)).is_true()
	var result := ChallengeSave.read(path)
	var back: ChallengeProfile = result["profile"]
	assert_int(back.revision).is_equal(2)
	assert_dict(back.to_dict()).is_equal(profile.to_dict())
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()


func test_no_file_is_a_fresh_start_with_no_problem() -> void:
	var result := ChallengeSave.read(ChallengeFixture.save_path("never_written"))
	assert_object(result["profile"]).is_null()
	assert_str(result["problem"]).is_equal("")


func test_a_save_from_a_newer_game_is_refused_not_read() -> void:
	var newer := JSON.stringify({"revision": 4, "schemaVersion": 2, "data": {"anything": 1}})
	var result := ChallengeSave.from_json(newer)
	assert_object(result["profile"]).is_null()
	assert_str(result["problem"]).is_equal(ChallengeSave.NEWER_VERSION)


func test_the_board_never_writes_over_a_newer_save() -> void:
	var path := ChallengeFixture.save_path("newer")
	var newer := JSON.stringify({"revision": 4, "schemaVersion": 2, "data": {"anything": 1}})
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(newer)
	file.close()
	var board := ChallengeBoard.open(path, ChallengeFixture.clock_on(DAY), _catalog)
	assert_str(board.problem).is_equal(ChallengeSave.NEWER_VERSION)
	assert_bool(board.save()).is_false()
	board.refresh()
	assert_str(FileAccess.get_file_as_string(path)).is_equal(newer)
	# It still works in memory, so the night can be played.
	assert_int(board.dailies().size()).is_equal(3)


func test_a_damaged_file_is_set_aside_and_play_starts_fresh() -> void:
	var path := ChallengeFixture.save_path("damaged")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var board := ChallengeBoard.open(path, ChallengeFixture.clock_on(DAY), _catalog)
	assert_str(board.problem).is_equal(ChallengeSave.UNREADABLE)
	assert_bool(FileAccess.file_exists(path + ".broken")).is_true()
	assert_int(board.dailies().size()).is_equal(3)
	# And the fresh profile is saved over the path the broken file left.
	assert_str(ChallengeSave.read(path)["problem"]).is_equal("")


func test_an_envelope_without_a_version_or_data_is_unreadable() -> void:
	for text in ["[]", "{}", '{"schemaVersion": 1}', '{"schemaVersion": 0, "data": {}}']:
		assert_str(ChallengeSave.from_json(text)["problem"]).is_equal(ChallengeSave.UNREADABLE)


func test_a_hand_edited_save_falls_back_instead_of_breaking() -> void:
	var data := {
		"dealt_day": "soon",
		"dailies": [{"id": "d_kills_40", "day": 1, "progress": -5}, 7, {"noid": 1}],
		"orders":
		[{"id": "o_round_8", "progress": "lots"}, "x", {"id": "a"}, {"id": "b"}, {"id": "c"}],
		"lifetime": {"kills": -3, "nights": 2.7},
		"finished": {"daily": -1},
		"order_seed": 99999999999,
	}
	var text := JSON.stringify({"revision": -2, "schemaVersion": 1, "data": data})
	var profile: ChallengeProfile = ChallengeSave.from_json(text)["profile"]
	assert_int(profile.dealt_day).is_equal(0)
	assert_int(profile.dailies.size()).is_equal(1)
	assert_int(profile.dailies[0]["progress"]).is_equal(0)
	assert_int(profile.orders.size()).is_equal(ChallengeProfile.ORDER_SLOTS)
	assert_int(profile.lifetime[&"kills"]).is_equal(0)
	assert_int(profile.lifetime[&"nights"]).is_equal(2)
	assert_int(profile.finished["daily"]).is_equal(0)
	assert_int(profile.revision).is_equal(0)
	assert_int(profile.order_seed).is_less_equal(ChallengeProfile.SEED_MASK)


func test_nothing_in_a_save_is_too_big_for_the_backend() -> void:
	# The backend refuses a JSON integer of 2^53 or more; counts and seeds stay far below.
	var text := ChallengeSave.to_json(_busy_profile())
	var data: Dictionary = JSON.parse_string(text)
	assert_bool(_all_small(data)).is_true()
	assert_int(text.length()).is_less(64 * 1024)


func _all_small(value: Variant) -> bool:
	if value is Dictionary:
		for item: Variant in (value as Dictionary).values():
			if not _all_small(item):
				return false
	elif value is Array:
		for item: Variant in value:
			if not _all_small(item):
				return false
	elif value is float or value is int:
		return absf(float(value)) < pow(2.0, 53.0)
	return true
