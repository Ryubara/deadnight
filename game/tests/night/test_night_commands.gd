# What the server does with the commands of a real connection (#163): a pressed edge is not lost
# when two commands arrive together, a client that goes silent stops, and a command is always its
# connection's player's.
extends GdUnitTestSuite

const STEP := Night.STEP


func _use_command(use: bool) -> Dictionary:
	var command := NightCommand.new()
	command.use = use
	return command.to_dict()


func test_two_commands_in_one_tick_keep_the_pressed_use() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var door := &"door_concession"
	var slab := night.world.door_points(door)[0]
	night.player().teleport(slab + Vector3(0.0, 0.1, -2.0))
	night.server.rules.apply(RulesAction.grant_points(1, 400))
	NightFixture.run(night, 3)
	# Jitter bunches the pressed command and the next one into one tick.
	night.link.send(_use_command(true))
	night.link.send(_use_command(false))
	night.tick()
	NightFixture.run(night, 3)
	assert_bool(night.server.rules.is_door_open(door)).is_true()
	night.queue_free()


func test_a_reload_pressed_before_a_newer_command_still_happens() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	var heard: Array[StringName] = []
	night.state.event_received.connect(func(e: Dictionary) -> void: heard.append(e["type"]))
	night.server.combat.weapon_of(1).ammo = 3
	var press := NightCommand.new()
	press.reload = true
	night.link.send(press.to_dict())
	night.link.send(NightCommand.new().to_dict())
	night.tick()
	NightFixture.run(night, 2)
	assert_bool(heard.has(&"reload_started")).is_true()
	night.queue_free()


func test_a_player_who_goes_silent_stops_walking() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	var walk := NightCommand.new()
	walk.motion.move = Vector2(0.0, -1.0)
	night.link.send(walk.to_dict())
	NightFixture.run(night, 2)
	var from := night.state.position()
	for _i in 100:
		night.tick()
	var after_silence := night.state.position()
	for _i in 100:
		night.tick()
	# Walking for the half second the command lasts is far; the next 100 ticks go nowhere.
	assert_float(after_silence.distance_to(from)).is_greater(0.5)
	assert_float(night.state.position().distance_to(after_silence)).is_less(0.05)
	night.queue_free()


func test_a_silent_player_stops_holding_the_trigger() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	var fire := NightCommand.new()
	fire.fire = true
	fire.dir = Vector3.FORWARD
	fire.origin = night.state.position() + Vector3(0.0, Autopilot.EYE, 0.0)
	night.link.send(fire.to_dict())
	var shots := 0
	night.state.event_received.connect(
		func(e: Dictionary) -> void: shots += 1 if e["type"] == &"shot_fired" else 0
	)
	for _i in 120:
		night.tick()
	var heard := shots
	for _i in 120:
		night.tick()
	assert_int(shots).is_equal(heard)
	night.queue_free()


func test_a_command_naming_another_player_moves_only_its_own() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	night.link.send({"type": NightServer.JOIN, "player_id": 2, "local": false})
	NightFixture.run(night, 30)
	var mine := night.state.position()
	var theirs := night.state.frame["players"][2]["pos"] as Vector3
	var command := NightCommand.new()
	command.player_id = 2
	command.motion.move = Vector2(0.0, -1.0)
	for _i in 30:
		night.link.send(command.to_dict())
		night.tick()
	assert_float((night.state.frame["players"][2]["pos"] as Vector3).distance_to(theirs)).is_less(
		0.05
	)
	assert_float(night.state.position().distance_to(mine)).is_greater(1.0)
	night.queue_free()


func test_the_frame_tells_each_player_which_command_it_used() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	var command := NightCommand.new()
	command.seq = 41
	night.link.send(command.to_dict())
	NightFixture.run(night, 3)
	assert_int(night.state.me()["ack"]).is_equal(41)
	night.queue_free()
