# The options a dedicated game server is started with: each setting of the match has one, and a
# value the game does not take is found, not pulled into bounds (Deadnight #944: `--map` and
# `--bot-skill` were never read, so a server started with them ran the usual night).
extends GdUnitTestSuite


func _args(words: Array) -> NetArgs:
	return NetArgs.new(PackedStringArray(words))


func test_no_options_are_the_usual_night() -> void:
	var settings := _args([]).match_settings()
	assert_bool(settings.is_default()).is_true()
	assert_str(MatchSettings.problem(settings.to_dict())).is_equal(&"")


func test_every_setting_has_an_option_and_reaches_the_settings() -> void:
	var settings := (
		_args(
			[
				"--count",
				"2",
				"--max-alive=12",
				"--break",
				"10",
				"--map",
				"small_indoor",
				"--bots=3",
				"--bot-skill",
				"2",
				"--perk-limit=1"
			]
		)
		. match_settings()
	)
	(
		assert_dict(settings.to_dict())
		. is_equal(
			{
				"count_multiplier": 2.0,
				"max_alive": 12,
				"break_seconds": 10.0,
				"map": "small_indoor",
				"bots": 3,
				"bot_skill": 2,
				"perk_limit": 1,
			}
		)
	)
	assert_str(MatchSettings.problem(settings.to_dict())).is_equal(&"")


func test_each_setting_alone_changes_only_that_setting() -> void:
	var options := {
		"count_multiplier": ["--count", "3"],
		"max_alive": ["--max-alive", "20"],
		"break_seconds": ["--break", "5"],
		"map": ["--map", "small_indoor"],
		"bots": ["--bots", "4"],
		"bot_skill": ["--bot-skill", "0"],
		"perk_limit": ["--perk-limit", "1"],
	}
	# A setting added to the match without an option fails here.
	assert_array(options.keys()).contains_exactly_in_any_order(MatchSettings.KEYS.keys())
	var usual := MatchSettings.new().to_dict()
	for key: String in options:
		var changed := _args(options[key]).match_settings().to_dict()
		for other: String in usual:
			if other == key:
				assert_that(changed[other]).is_not_equal(usual[other])
			else:
				assert_that(changed[other]).is_equal(usual[other])


func test_a_value_the_game_does_not_take_is_found_by_its_setting() -> void:
	var cases := {
		"map": ["--map", "nowhere"],
		"bots": ["--bots", "9"],
		"bot_skill": ["--bot-skill", "5"],
		"count_multiplier": ["--count", "50"],
		"break_seconds": ["--break", "500"],
		"perk_limit": ["--perk-limit", "2"],
	}
	for key: String in cases:
		var settings := _args(cases[key]).match_settings()
		assert_str(MatchSettings.problem(settings.to_dict())).is_equal(StringName(key))
