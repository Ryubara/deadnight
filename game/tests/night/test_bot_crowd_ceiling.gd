# A hosted bot has no screen, so it counts for nothing in the crowd's ceiling (issue #946): the
# ceiling follows the platforms of the people in the night. Before, a bot joined as a browser and
# any night with one took the web's 40 even on a desktop (docs/research/crowd-budget.md says 120).
extends GdUnitTestSuite

var _night: SeatedNight


func after_test() -> void:
	if _night != null:
		_night.dispose()
		_night = null


func _start() -> void:
	_night = await SeatedNight.start(self, 0)


func _join(player_id: int, local: bool, bot := false) -> void:
	_night.server.apply(
		{"type": NightServer.JOIN, "player_id": player_id, "local": local, "bot": bot}
	)


func _ceiling() -> int:
	return _night.server.crowd_ceiling()


func test_a_desktop_person_with_three_bots_stands_the_desktop_crowd() -> void:
	await _start()
	_join(1, true)
	for id in [2, 3, 4]:
		_join(id, false, true)
	assert_int(_ceiling()).is_equal(RoundTuning.new().alive_cap_ceiling)
	assert_int(_night.server.sim.tuning.hard_cap).is_equal(_ceiling())
	assert_int(_night.server.rules.crowd_ceiling).is_equal(_ceiling())


func test_the_bots_alone_follow_the_platform_of_the_process() -> void:
	await _start()
	for id in [1, 2]:
		_join(id, false, true)
	assert_int(_ceiling()).is_equal(RoundTuning.new().ceiling_for(OS.has_feature("web")))


func test_a_browser_person_with_bots_stands_the_browsers_crowd() -> void:
	await _start()
	# A remote person is a browser until its client says it is not.
	_join(1, false)
	for id in [2, 3]:
		_join(id, false, true)
	var web := RoundTuning.new().web_alive_cap_ceiling
	assert_int(_ceiling()).is_equal(web)
	_night.server.crowd.set_platform(1, false)
	assert_int(_ceiling()).is_equal(RoundTuning.new().alive_cap_ceiling)
	_night.server.crowd.set_platform(1, true)
	assert_int(_ceiling()).is_equal(web)


func test_a_browser_joining_a_desktop_room_of_bots_takes_the_crowd_down() -> void:
	await _start()
	_join(1, false)
	_night.server.crowd.set_platform(1, false)
	_join(2, false, true)
	var native := RoundTuning.new().alive_cap_ceiling
	assert_int(_ceiling()).is_equal(native)
	_join(3, false)
	assert_int(_ceiling()).is_equal(RoundTuning.new().web_alive_cap_ceiling)
	_night.server.apply({"type": NightServer.LEAVE, "player_id": 3})
	assert_int(_ceiling()).is_equal(native)


func test_a_person_taking_a_bots_seat_counts_and_a_bot_taking_a_seat_does_not() -> void:
	await _start()
	_join(1, false)
	_night.server.crowd.set_platform(1, false)
	_join(2, false, true)
	var native := RoundTuning.new().alive_cap_ceiling
	var web := RoundTuning.new().web_alive_cap_ceiling
	# A person (a browser until it says otherwise) takes the bot's seat: the room goes down.
	_night.server.apply({"type": NightServer.SEAT_PERSON, "player_id": 2})
	assert_int(_ceiling()).is_equal(web)
	_night.server.crowd.set_platform(2, false)
	assert_int(_ceiling()).is_equal(native)
	# It leaves a browser and a bot inherits the seat: the bot's seat carries no platform.
	_night.server.crowd.set_platform(2, true)
	assert_int(_ceiling()).is_equal(web)
	_night.server.apply({"type": RulesAction.SEAT_BOT, "player_id": 2})
	assert_int(_ceiling()).is_equal(native)


func test_the_crowd_ceiling_keeps_a_bots_seat_out_of_its_table() -> void:
	var crowd := CrowdCeiling.new()
	crowd.join(1, false)
	crowd.leave(1)
	assert_int(crowd.value(RoundTuning.new())).is_equal(
		RoundTuning.new().ceiling_for(OS.has_feature("web"))
	)
