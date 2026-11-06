# What the operator of a game server lets its rooms do with bots (#230): a cap per room, a budget of
# bots shared by the open rooms, and a kill-switch, all read from the environment and all stronger
# than the host's Bots setting.
extends GdUnitTestSuite


func _config(env: Dictionary) -> ServerConfig:
	return ServerConfig.from_environment(func(key: String) -> String: return env.get(key, ""))


func test_an_environment_with_no_budget_lets_a_room_seat_what_its_host_asked_for() -> void:
	var limits := BotLimits.from_config(_config({"BOT_BUDGET": "0"}))
	assert_int(limits.per_room).is_equal(MatchSettings.MAX_BOTS)
	assert_bool(limits.off).is_false()
	assert_int(limits.budget).is_equal(0)
	for rooms in range(1, 6):
		assert_int(limits.for_room(rooms)).is_equal(MatchSettings.MAX_BOTS)


## #1193, #1222: a room with bots costs more tick, and the build before #1193 took 27 ms of the
## 16.7 ms for 3 rooms of 8 people and 7 bots. Unset, the server shares three bots among its rooms,
## what the measurement on Railway allows: a lone room seats three, two rooms and three rooms one
## each, four rooms none.
func test_an_unset_environment_shares_a_small_budget_of_bots_among_the_rooms() -> void:
	var limits := BotLimits.from_config(_config({}))
	assert_int(limits.budget).is_equal(GameServer.DEFAULT_BOT_BUDGET)
	assert_int(limits.budget).is_equal(3)
	assert_int(limits.for_room(1)).is_equal(3)
	assert_int(limits.for_room(2)).is_equal(1)
	assert_int(limits.for_room(GameServer.DEFAULT_CAPACITY)).is_equal(1)
	assert_int(limits.for_room(GameServer.DEFAULT_CAPACITY + 1)).is_equal(0)
	# Junk is the default, not a switch-off; a number is the operator's own.
	assert_int(_config({"BOT_BUDGET": "lots"}).bot_budget).is_equal(3)
	assert_int(_config({"BOT_BUDGET": "7"}).bot_budget).is_equal(7)
	assert_int(_config({"BOT_BUDGET": "-2"}).bot_budget).is_equal(0)


func test_the_cap_per_room_is_read_and_held_to_zero_to_three() -> void:
	assert_int(_config({"MAX_BOTS": "2"}).max_bots).is_equal(2)
	assert_int(_config({"MAX_BOTS": "0"}).max_bots).is_equal(0)
	assert_int(_config({"MAX_BOTS": "9"}).max_bots).is_equal(MatchSettings.MAX_BOTS)
	assert_int(_config({"MAX_BOTS": "-3"}).max_bots).is_equal(0)
	# Junk is no cap at all, not a switch-off.
	assert_int(_config({"MAX_BOTS": "lots"}).max_bots).is_equal(MatchSettings.MAX_BOTS)
	assert_int(BotLimits.from_config(_config({"MAX_BOTS": "1"})).for_room(1)).is_equal(1)


func test_the_kill_switch_reads_the_usual_words_for_yes_and_stops_every_room() -> void:
	for yes in ["1", "true", "TRUE", "yes", "on", " on "]:
		var limits := BotLimits.from_config(_config({"BOTS_OFF": yes}))
		assert_bool(limits.off).override_failure_message(yes).is_true()
		assert_int(limits.for_room(1)).is_equal(0)
		assert_int(limits.for_room(3)).is_equal(0)
	for no in ["", "0", "false", "no", "off", "maybe"]:
		assert_bool(_config({"BOTS_OFF": no}).bots_off).override_failure_message(no).is_false()


func test_a_budget_is_shared_by_the_open_rooms_and_never_raises_the_cap() -> void:
	var limits := BotLimits.from_config(_config({"BOT_BUDGET": "4"}))
	assert_int(limits.for_room(1)).is_equal(4)
	assert_int(limits.for_room(2)).is_equal(2)
	assert_int(limits.for_room(3)).is_equal(1)
	assert_int(limits.for_room(5)).is_equal(0)
	# A room count of zero (a server with no room yet) is read as one.
	assert_int(limits.for_room(0)).is_equal(4)
	var capped := BotLimits.from_config(_config({"BOT_BUDGET": "9", "MAX_BOTS": "2"}))
	assert_int(capped.for_room(1)).is_equal(2)
	assert_int(capped.for_room(3)).is_equal(2)
	assert_int(capped.for_room(4)).is_equal(2)
	assert_int(capped.for_room(5)).is_equal(1)


func test_the_bots_a_night_seats_obey_the_setting_and_the_cap_and_never_the_people() -> void:
	for wanted in range(0, MatchSettings.MAX_BOTS + 1):
		for cap in range(0, MatchSettings.MAX_BOTS + 1):
			var seated := NightBots.target(wanted, cap)
			assert_int(seated).is_equal(mini(wanted, cap))
	assert_int(NightBots.target(3, 1)).is_equal(1)
	assert_int(NightBots.target(3, 0)).is_equal(0)
	# No cap given is the setting's own maximum.
	assert_int(NightBots.target(3)).is_equal(3)
