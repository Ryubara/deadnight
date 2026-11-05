extends GdUnitTestSuite
## A body no one looks through does not run its camera rig in every drawn frame (#938): a bot's, a
## remote player's on the server, a puppet. Each rig used to ease its springs and sweep the world
## in every frame (about 16 to 40 us), and a person's night has three bots to one person. The rig
## is told the look in each tick instead, so the weapon's pose reads what it read; a bot's aim and
## the server's shots never came from it (the command carries the origin and the direction).

const BOTS := 3
const FRAMES := 12
const PLAYER_SCENE := preload("res://gameplay/player/player.tscn")

var _nights: Array[Night] = []


func after_test() -> void:
	# Every night of the suite hangs under it, and its bodies are in the rig's list while it lives.
	for night in _nights:
		night.queue_free()
	_nights.clear()
	await get_tree().process_frame
	await RouterFixture.clear(get_tree())


func _night(mode: Night.Mode = Night.Mode.HUMAN, shoulder := false) -> Night:
	var night := Night.new()
	night.shoulder_camera = shoulder
	night.match_settings = MatchSettings.new()
	night.match_settings.bots = BOTS
	add_child(night)
	await night.start(mode, 7, RulesFixture.tuning())
	night.server.rules.apply(RulesAction.skip_break())
	_nights.append(night)
	return night


func _rigs(root: Node) -> Array[Node]:
	return root.find_children("*", "ThirdPersonCamera", true, false)


func _processing(root: Node) -> int:
	var count := 0
	for rig in _rigs(root):
		if rig.is_processing():
			count += 1
	return count


func _bots(night: Night) -> Array[Player]:
	var bots: Array[Player] = []
	for id: int in night.server._bodies:
		if id != Night.PLAYER_ID:
			bots.append(night.server.body_of(id))
	return bots


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func test_one_rig_runs_in_a_night_of_a_person_and_three_bots() -> void:
	var night := await _night()
	await _frames(FRAMES)
	assert_int(_rigs(night).size()).is_equal(BOTS + 1)
	assert_int(_processing(night)).is_equal(1)
	assert_bool(night.player().camera_rig.is_processing()).is_true()
	for bot in _bots(night):
		assert_bool(bot.camera_rig.is_resting()).is_true()


func test_a_bots_rig_is_not_placed_while_the_bot_walks() -> void:
	var night := await _night()
	var bot := _bots(night)[0]
	var placed := bot.camera_rig.global_position
	var walked_from := bot.global_position
	for _i in 6:
		NightFixture.run(night, 30)
		await _frames(2)
	assert_float(bot.global_position.distance_to(walked_from)).is_greater(1.0)
	assert_vector(bot.camera_rig.global_position).is_equal(placed)
	assert_vector(night.player().camera_rig.global_position).is_not_equal(placed)


func test_the_rig_of_a_bot_has_the_look_of_its_command_from_its_head() -> void:
	var night := await _night()
	NightFixture.run(night, 120)
	for bot in _bots(night):
		var rig := bot.camera_rig
		var view := rig.aim_transform()
		assert_float(rig.yaw).is_equal_approx(bot.last_command.yaw, 0.0001)
		assert_float(rig.pitch).is_equal_approx(bot.last_command.pitch, 0.0001)
		assert_vector(view.origin).is_equal_approx(
			bot.global_position + Vector3(0.0, bot.tuning.pivot_height, 0.0), Vector3.ONE * 0.001
		)
		var forward := -view.basis.z
		var expected := -(
			Basis.from_euler(Vector3(bot.last_command.pitch, bot.last_command.yaw, 0.0)).z
		)
		assert_float(forward.dot(expected)).is_greater(0.9999)


func test_a_bots_shots_leave_from_its_eye_along_its_look_not_from_its_rig() -> void:
	var night := await _night()
	NightFixture.first_zombie(night)
	var seats := night.bots.seats()
	var shots := 0
	for _i in 1200:
		night.tick()
		for id in seats:
			var command := night.server._pending.get(id) as NightCommand
			if command == null or not command.fire:
				continue
			var body: Player = night.server.body_of(id)
			var eye := body.global_position + Vector3(0.0, night.server.tuning.eye_height, 0.0)
			assert_float(command.origin.distance_to(eye)).is_less(night.server.tuning.origin_slack)
			assert_float(command.dir.length()).is_equal_approx(1.0, 0.001)
			# The rig rests, and the shot did not need it.
			assert_bool(body.camera_rig.is_resting()).is_true()
			shots += 1
		if shots >= 20:
			break
	assert_int(shots).is_greater(0)


func test_a_body_made_the_view_runs_its_rig_and_owns_the_camera() -> void:
	var night := await _night(Night.Mode.AUTOPILOT, true)
	await _frames(FRAMES)
	var body := night.player()
	assert_bool(body.camera_rig.is_resting()).is_false()
	assert_bool(body.camera_rig.is_processing()).is_true()
	assert_bool(body.camera_rig.camera().current).is_true()
	assert_int(_processing(night)).is_equal(1)


func test_no_rig_runs_in_an_autopilot_night_watched_from_a_spectator_camera() -> void:
	var night := await _night(Night.Mode.AUTOPILOT)
	await _frames(FRAMES)
	assert_int(_rigs(night).size()).is_equal(BOTS + 1)
	assert_int(_processing(night)).is_equal(0)


func test_a_server_that_draws_nothing_runs_no_rig() -> void:
	var seated := await SeatedNight.start(self, 2)
	await _frames(2)
	assert_int(_rigs(seated.world).size()).is_equal(2)
	assert_int(_processing(seated.world)).is_equal(0)
	seated.world.queue_free()


func test_a_puppets_rig_does_not_run() -> void:
	var puppet := auto_free(PLAYER_SCENE.instantiate()) as Player
	puppet.make_puppet()
	add_child(puppet)
	await _frames(2)
	assert_bool(puppet.camera_rig.is_processing()).is_false()


func test_the_bodies_the_camera_sweeps_through_follow_the_players() -> void:
	var night := await _night()
	var rig := night.player().camera_rig
	assert_int(rig._bodies().size()).is_equal(BOTS + 1)
	for id: int in night.server._bodies:
		assert_bool(rig._bodies().has(night.server.body_of(id).get_rid())).is_true()
	var leaver := night.bots.seats()[0]
	var gone := night.server.body_of(leaver).get_rid()
	night.bots.host.release(leaver)
	night.server.apply({"type": NightServer.LEAVE, "player_id": leaver})
	await _frames(3)
	assert_int(rig._bodies().size()).is_equal(BOTS)
	assert_bool(rig._bodies().has(gone)).is_false()
	night.bots.fill(BOTS)
	NightFixture.run(night, 2)
	assert_int(rig._bodies().size()).is_equal(BOTS + 1)
