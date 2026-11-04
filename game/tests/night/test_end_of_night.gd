extends GdUnitTestSuite
## The end of a night played alone, through the real night (docs/design/end-of-night.md): the last
## player down ends it, the night stands still where it ended while the server counts the
## intermission (15 s unless a test shortens it), the camera leaves the player's own lens for the
## end sequence, the frames carry the clock and the board's counts, and the night says once that
## it is closed.

const SECONDS := 2.0
const TICKS_PER_SECOND := 60


func _night(bots := 0) -> Night:
	var night := Night.new()
	night.match_settings = MatchSettings.new()
	night.match_settings.bots = bots
	add_child(night)
	await night.start(Night.Mode.HUMAN, 7, RulesFixture.tuning())
	night.server.end_seconds = SECONDS
	NightFixture.run(night, 2)
	return night


## Everyone goes down: the night is over, as the server's own events say (the loopback delivers them
## on the next tick, which this runs).
func _end(night: Night) -> void:
	night.server.rules.apply(RulesAction.skip_break())
	for id: int in night.server.rules.players.keys():
		night.link.broadcast(night.server.rules.apply(RulesAction.set_downed(id, true)))
	NightFixture.run(night, 1)


func after_test() -> void:
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func test_the_shipped_intermission_is_fifteen_seconds() -> void:
	assert_float(NightServer.END_SECONDS).is_equal(15.0)
	var night := Night.new()
	add_child(night)
	await night.start(Night.Mode.HUMAN, 7, RulesFixture.tuning())
	assert_float(night.server.end_seconds).is_equal(15.0)


func test_the_end_starts_the_camera_on_the_players_own_lens() -> void:
	var night := await _night()
	var lens := night.get_viewport().get_camera_3d()
	var from := lens.global_transform
	var fov := lens.fov
	assert_object(night.end_camera).is_null()
	_end(night)
	assert_bool(night.state.over).is_true()
	assert_object(night.end_camera).is_not_null()
	assert_object(night.get_viewport().get_camera_3d()).is_same(night.end_camera)
	assert_vector(night.end_camera.global_position).is_equal_approx(
		from.origin, Vector3.ONE * 0.001
	)
	assert_float(night.end_camera.fov).is_equal_approx(fov, 0.001)
	# It leaves: a second of its time on, it is away from the lens and higher.
	night.end_camera.seek(2.0)
	assert_float(night.end_camera.global_position.y).is_greater(from.origin.y + 1.0)
	assert_float(night.end_camera.global_position.distance_to(from.origin)).is_greater(2.0)


func test_the_night_stands_still_while_the_server_counts_the_intermission() -> void:
	var night := await _night()
	_end(night)
	NightFixture.run(night, 1)
	var body_at := night.player().global_position
	var dead_before := night.state.zombies.duplicate(true)
	var tick_before: int = int(night.state.frame["tick"])
	NightFixture.run(night, TICKS_PER_SECOND)
	assert_vector(night.player().global_position).is_equal(body_at)
	assert_array(night.state.zombies).is_equal(dead_before)
	# The server goes on ticking (the clock is in its frames) but nothing else.
	assert_int(int(night.state.frame["tick"])).is_greater(tick_before)
	assert_int(night.state.phase()).is_equal(GameRules.Phase.OVER)


func test_the_server_counts_whole_seconds_down_and_says_the_night_is_closed_once() -> void:
	var night := await _night()
	assert_int(night.state.over_left()).is_equal(-1)
	var closed := [0]
	var overs := [0]
	night.night_closed.connect(func() -> void: closed[0] += 1)
	night.night_over.connect(func(_round: int) -> void: overs[0] += 1)
	_end(night)
	NightFixture.run(night, 1)
	assert_int(overs[0]).is_equal(1)
	assert_int(night.state.over_left()).is_equal(int(SECONDS))
	var seen: Array[int] = []
	for i in int(SECONDS) * TICKS_PER_SECOND + 30:
		NightFixture.run(night, 1)
		var left := night.state.over_left()
		if seen.is_empty() or seen.back() != left:
			seen.append(left)
	assert_array(seen).is_equal([2, 1, 0])
	assert_int(closed[0]).is_equal(1)
	assert_bool(night.state.closed).is_true()
	assert_int(overs[0]).is_equal(1)


func test_the_frames_carry_the_boards_counts() -> void:
	var night := await _night()
	var rules := night.server.rules
	rules.apply(RulesAction.skip_break())
	RulesFixture.run(rules, 8.0)
	var ids := rules.zombie_ids()
	RulesFixture.kill(rules, 1, ids[0], RulesAction.ZONE_HEAD)
	RulesFixture.clear_round(rules)
	NightFixture.run(night, 2)
	var me: Dictionary = night.state.frame["players"][1]
	assert_int(int(me["headshots"])).is_equal(1)
	assert_int(int(me["rounds"])).is_equal(1)
	assert_int(int(me["kills"])).is_greater_equal(1)
	assert_int(night.state.over_left()).is_equal(-1)


func test_the_player_cannot_move_or_shoot_during_the_intermission() -> void:
	var night := await _night()
	_end(night)
	NightFixture.run(night, 1)
	var command := NightCommand.new()
	command.motion.move = Vector2(0.0, -1.0)
	command.motion.sprint = true
	NightFixture.run(night, 30, command)
	var body := night.player()
	var at := body.global_position
	NightFixture.run(night, 30, command)
	assert_vector(body.global_position).is_equal(at)
