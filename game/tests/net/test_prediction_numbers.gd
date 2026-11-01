# A client that moves its body with the command it sends gets the server's result only if it moves
# with the command the server reads: the wire drops bits of the yaw and the stick.
extends GdUnitTestSuite

const TICKS := 600


func _sampled(tick: int) -> NightCommand:
	var command := NightCommand.new()
	var turn := tick * 0.0173
	command.motion.move = Vector2(sin(turn * 3.1), -cos(turn * 2.3)).limit_length(1.0)
	command.motion.yaw = 0.7 + turn * 0.9
	command.motion.pitch = sin(turn) * 0.4
	command.motion.sprint = tick % 120 < 80
	command.motion.jump = tick % 97 == 40
	return command


func _run(player: Player, convert: Callable) -> PlayerMotionState:
	player.teleport(Vector3(2, 0.05, 0))
	player.state.copy_from(PlayerMotionState.new())
	player.state.position = Vector3(2, 0.05, 0)
	PlayerSimulation.restore(player, player.state, SlopeWorld.TICK)
	for tick in TICKS:
		player.tick(convert.call(_sampled(tick)).motion)
	return player.state.duplicate_state()


func test_a_client_that_snaps_its_commands_ends_where_the_server_does() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var player := await SlopeWorld.build(root)
	var unsnapped := _run(player, func(c: NightCommand) -> NightCommand: return c)
	var snapped := _run(player, func(c: NightCommand) -> NightCommand: return NetWire.quantize(c))
	var served := _run(
		player,
		func(c: NightCommand) -> NightCommand: return NetWire.read_command(NetWire.command(c))
	)
	print(
		"raw prediction ends ",
		unsnapped.position.distance_to(served.position),
		" m from the server's"
	)
	# The same commands, so the same run, to a physics engine's own rounding (the last 0.2 mm is the
	# contact it keeps from the run before); the unsnapped run is a hundred times further.
	assert_float(snapped.position.distance_to(served.position)).is_less(0.0005)
	assert_float(snapped.velocity.distance_to(served.velocity)).is_less(0.01)
	assert_float(unsnapped.position.distance_to(served.position)).is_greater(0.01)
