# Who the bots are (#230): a name and a look for each of the three skills' three bots, and the
# profile a room's skill means. A name is a person's, short and plain, so a lobby and a HUD can
# write BOT after it; a look is a preset of the catalogue, so every client dresses it the same.
extends GdUnitTestSuite

const SKILLS := [
	MatchSettings.SKILL_ROOKIE, MatchSettings.SKILL_REGULAR, MatchSettings.SKILL_VETERAN
]


func test_each_skill_has_three_bots_with_names_and_looks_of_their_own() -> void:
	for skill: int in SKILLS:
		var names := {}
		var looks := {}
		for seat in range(1, 5):
			var who := BotRoster.identity(skill, seat)
			names[who["name"]] = true
			looks[BotRoster.look_for(skill, seat).key()] = true
		# Four seats, three people: the seats take them in turn, so a night's three bots differ.
		assert_int(names.size()).override_failure_message("names of skill %d" % skill).is_equal(3)
		assert_int(looks.size()).override_failure_message("looks of skill %d" % skill).is_equal(3)


func test_the_three_bots_of_a_night_differ_in_every_seat_choice() -> void:
	for skill: int in SKILLS:
		for first in range(1, 3):
			var seen := {}
			for seat in [first + 1, first + 2, first + 3]:
				seen[BotRoster.name_for(skill, seat)] = true
			assert_int(seen.size()).is_equal(3)


func test_a_name_is_short_and_plain_and_no_two_skills_share_one() -> void:
	var all := {}
	for skill: int in SKILLS:
		for seat in range(1, 4):
			var bot_name := BotRoster.name_for(skill, seat)
			assert_int(bot_name.length()).is_between(2, 8)
			assert_bool(bot_name == bot_name.strip_edges()).is_true()
			assert_bool(bot_name.to_upper() != "BOT").is_true()
			assert_bool(all.has(bot_name)).override_failure_message(bot_name).is_false()
			all[bot_name] = true


func test_every_look_is_a_real_preset_of_the_catalogue_and_free_to_wear() -> void:
	var ids: Array[String] = []
	for preset in LookCatalog.presets():
		ids.append(preset["id"])
	var unlocks := LookUnlocks.new()
	for skill: int in SKILLS:
		for who: Dictionary in BotRoster.CAST[skill]:
			(
				assert_bool(ids.has(String(who["look"])))
				. override_failure_message(who["name"])
				. is_true()
			)
		for seat in range(1, 4):
			var look := BotRoster.look_for(skill, seat)
			# The server takes the look as a person's look arrives: nothing in it may be locked.
			assert_bool(look.equals(look.without_locked(unlocks))).is_true()


func test_a_room_skill_means_the_shipped_profile_of_that_name() -> void:
	assert_str(BotProfile.for_skill(MatchSettings.SKILL_ROOKIE).title).is_equal("Rookie")
	assert_str(BotProfile.for_skill(MatchSettings.SKILL_REGULAR).title).is_equal("Regular")
	assert_str(BotProfile.for_skill(MatchSettings.SKILL_VETERAN).title).is_equal("Veteran")
	# A value out of range is the nearest skill, never a crash.
	assert_str(BotProfile.for_skill(-4).title).is_equal("Rookie")
	assert_str(BotProfile.for_skill(40).title).is_equal("Veteran")


func test_the_skills_differ_only_in_how_the_bot_plays() -> void:
	var rookie := BotProfile.for_skill(MatchSettings.SKILL_ROOKIE)
	var regular := BotProfile.for_skill(MatchSettings.SKILL_REGULAR)
	var veteran := BotProfile.for_skill(MatchSettings.SKILL_VETERAN)
	# Slower and sloppier to quicker and steadier.
	assert_float(rookie.reaction_seconds).is_greater(regular.reaction_seconds)
	assert_float(regular.reaction_seconds).is_greater(veteran.reaction_seconds)
	assert_float(rookie.track_error).is_greater(regular.track_error)
	assert_float(regular.track_error).is_greater(veteran.track_error)
	assert_float(rookie.max_aim_speed).is_less(veteran.max_aim_speed)
	# None reacts faster than a person can.
	for profile in [rookie, regular, veteran]:
		assert_float(profile.reaction_seconds).is_greater_equal(BotProfile.REACTION_FLOOR)
