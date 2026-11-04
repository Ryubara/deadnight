# Stepping out of a telegraphed blow (bots plan, phase 3): the numbers it stands on are the zombie
# tuning's, and the bot reacts to a swing only after its reaction time and only if there is time
# left.
extends GdUnitTestSuite

const HERE := Vector3.ZERO


func _swinger(look: StringName, at: Vector3, began: float) -> BotBeliefs:
	var beliefs := BotBeliefs.new()
	beliefs.contacts[1] = {
		"id": 1,
		"position": at,
		"mode": ZombieBody.Mode.ATTACK,
		"look": look,
		"attack_at": began,
		"believed_at": 0.0,
		"last_seen": 0.0,
		"visible": true,
	}
	return beliefs


func test_the_numbers_are_the_game_tunings() -> void:
	var tuning := ZombieTuning.shipped()
	assert_float(BotDodge.REACH).is_equal(tuning.reach)
	assert_float(BotDodge.SLACK).is_equal(tuning.strike_slack)
	assert_float(BotDodge.WINDUP).is_equal(tuning.windup_seconds)
	var rules := RulesFixture.tuning()
	var boss: ZombieType = rules.roster.type_of(&"headliner")
	assert_float(BotDodge.BOSS_WINDUP).is_equal(boss.telegraph_seconds)
	var crawler: ZombieType = rules.roster.type_of(&"crawler")
	assert_float(BotDodge.CRAWLER_WINDUP).is_equal(crawler.telegraph_seconds)
	assert_float(crawler.reach + tuning.strike_slack).is_less_equal(BotDodge.REACH + BotDodge.SLACK)
	assert_int(BotBeliefs.START_GRENADES).is_equal(rules.explosives.start_grenades)


func test_a_swing_is_noticed_after_the_reaction_and_not_before() -> void:
	var dodge := BotDodge.new(BotProfile.regular())
	var beliefs := _swinger(&"headliner", Vector3(0, 0, -1.2), 10.0)
	beliefs.now = 10.2
	assert_array(dodge.swings(beliefs, HERE)).is_empty()
	beliefs.now = 10.0 + BotProfile.regular().reaction_seconds + 0.01
	assert_array(dodge.swings(beliefs, HERE)).has_size(1)


func test_the_boss_leaves_time_and_a_plain_zombie_does_not_for_a_slow_bot() -> void:
	var reading := BotProfile.rookie()
	reading.telegraph_read = 1.0
	var rookie := BotDodge.new(reading)
	var beliefs := _swinger(&"headliner", Vector3(0, 0, -1.2), 10.0)
	beliefs.now = 10.0 + BotProfile.rookie().reaction_seconds + 0.01
	assert_array(rookie.swings(beliefs, HERE)).has_size(1)
	var plain := _swinger(&"walker", Vector3(0, 0, -1.2), 10.0)
	plain.now = 10.0 + BotProfile.rookie().reaction_seconds + 0.01
	assert_array(rookie.swings(plain, HERE)).is_empty()
	var veteran := BotDodge.new(BotProfile.veteran())
	plain.now = 10.0 + BotProfile.veteran().reaction_seconds + 0.01
	assert_array(veteran.swings(plain, HERE)).has_size(1)


func test_a_swing_that_cannot_reach_the_bot_is_no_danger() -> void:
	var dodge := BotDodge.new(BotProfile.veteran())
	var beliefs := _swinger(&"headliner", Vector3(0, 0, -3.5), 10.0)
	beliefs.now = 11.0
	assert_array(dodge.swings(beliefs, HERE)).is_empty()


func test_the_clock_of_a_swing_starts_with_it_and_ends_when_the_zombie_stops() -> void:
	var rng := RandomNumberGenerator.new()
	var perception := BotPerception.new(BotProfile.veteran(), BotLevel.new(), rng)
	var zombie := {
		"id": 5,
		"position": Vector3(0, 0, -5),
		"mode": ZombieBody.Mode.CHASE,
		"yaw": 0.0,
		"episode": 1,
		"look": &"walker",
		"speed": 1.0,
		"tearing": false,
	}
	perception.observe(0.0, true, {"pos": HERE}, [zombie], 1, 0.0)
	zombie["mode"] = ZombieBody.Mode.ATTACK
	zombie["episode"] = 2
	perception.observe(1.0, true, {"pos": HERE}, [zombie], 1, 0.0)
	assert_float(perception.beliefs.contacts[5]["attack_at"]).is_equal(1.0)
	perception.observe(1.3, true, {"pos": HERE}, [zombie], 1, 0.0)
	assert_float(perception.beliefs.contacts[5]["attack_at"]).is_equal(1.0)
	zombie["mode"] = ZombieBody.Mode.CHASE
	perception.observe(1.6, true, {"pos": HERE}, [zombie], 1, 0.0)
	assert_float(perception.beliefs.contacts[5]["attack_at"]).is_equal(-1.0)


func test_a_telegraphed_blow_is_made_out_at_the_profiles_read_and_a_plain_one_always() -> void:
	var rookie := BotProfile.rookie()
	var dodge := BotDodge.new(rookie, 5)
	var noticed := 0
	var swings := 400
	for episode in swings:
		var boss := _swinger(&"headliner", Vector3(0, 0, -1.2), 10.0)
		boss.contacts[1]["episode"] = episode
		boss.now = 10.7
		noticed += dodge.swings(boss, HERE).size()
	var share := float(noticed) / float(swings)
	assert_float(share).is_between(rookie.telegraph_read - 0.07, rookie.telegraph_read + 0.07)
	# A swing is rolled once: asking again in the same swing gives the same answer.
	var again := _swinger(&"headliner", Vector3(0, 0, -1.2), 10.0)
	again.contacts[1]["episode"] = 3
	again.now = 10.7
	var first := dodge.swings(again, HERE).size()
	for _i in 5:
		assert_int(dodge.swings(again, HERE).size()).is_equal(first)


func test_the_rookie_never_makes_out_the_boss_and_the_others_always_do() -> void:
	# The fit to the weak boss night (#568): a Rookie that steps out of the headliner's blow wins the
	# night every time, which the simulator's weak players do not.
	for profile: BotProfile in [BotProfile.rookie(), BotProfile.regular(), BotProfile.veteran()]:
		var dodge := BotDodge.new(profile, 5)
		var noticed := 0
		for episode in 60:
			var boss := _swinger(&"headliner", Vector3(0, 0, -1.2), 10.0)
			boss.contacts[1]["episode"] = episode
			boss.now = 10.7
			noticed += dodge.swings(boss, HERE).size()
		assert_int(noticed).is_equal(0 if profile.title == "Rookie" else 60)
