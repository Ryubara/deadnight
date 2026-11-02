# The frame a shooter was looking at travels with the command, and the server judges the shot
# against the world of that frame (`LagCompensator`): how far it rewinds follows how old the view
# was, up to the cap, and a shot that says nothing is judged against the present.
extends GdUnitTestSuite

const STEP := Night.STEP

var _night: Night


func _start() -> NightServer:
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	# The test steps the server by hand.
	_night.running = false
	return _night.server


func after_test() -> void:
	if is_instance_valid(_night):
		await NightFixture.settle_bake(_night)
		_night.queue_free()


## Fires one shot with the view `behind` steps old (-1: says nothing) and returns the shot event.
func _shot(server: NightServer, behind: int) -> Dictionary:
	var command := NightCommand.new()
	command.fire = true
	command.dir = Vector3.FORWARD
	command.origin = server.body_of(1).global_position + Vector3(0.0, 1.5, 0.0)
	if behind >= 0:
		command.view_step = (server.tick_count - behind) & 0xFFFF
	for _i in 60:
		server.submit(1, command)
		for event in server.step(STEP):
			if event["type"] == &"shot_fired":
				return event
		command.view_step = (server.tick_count - behind) & 0xFFFF if behind >= 0 else -1
		# A step later the same view is one step older: the next command is made fresh, as the
		# client makes one every step.
	return {}


func test_the_view_step_makes_the_server_rewind_by_its_age() -> void:
	var server := await _start()
	# Let the first shot's cooldown pass between the shots by stepping on.
	var none := await _shot(server, -1)
	assert_float(none["rewound_by"]).is_equal_approx(0.0, 0.001)
	for behind in [6, 12]:
		for _i in 40:
			server.step(STEP)
		var shot := await _shot(server, behind)
		# The step that judges the shot is one after the one the command was made in.
		assert_float(shot["rewound_by"]).is_equal_approx((behind + 1) * STEP, STEP * 0.6)


func test_a_view_older_than_the_cap_is_cut_to_the_cap() -> void:
	var server := await _start()
	var shot := await _shot(server, 120)
	assert_float(shot["rewound_by"]).is_equal_approx(LagCompensator.DEFAULT_MAX_REWIND, 0.01)


func test_the_view_step_survives_the_wrap_of_its_sixteen_bits() -> void:
	var server := await _start()
	# 70000 steps in (19 minutes): the wire carries 70000 - 6 modulo 65536.
	server.tick_count = 70_000
	var shot := await _shot(server, 6)
	assert_float(shot["rewound_by"]).is_equal_approx(7 * STEP, STEP * 0.6)


func test_a_view_from_the_future_is_the_present() -> void:
	var server := await _start()
	var command := NightCommand.new()
	command.fire = true
	command.dir = Vector3.FORWARD
	command.view_step = (server.tick_count + 500) & 0xFFFF
	server.submit(1, command)
	var shot := {}
	for _i in 10:
		for event in server.step(STEP):
			if event["type"] == &"shot_fired":
				shot = event
		if not shot.is_empty():
			break
	assert_float(shot["rewound_by"]).is_less(2.0 * STEP)


func test_the_view_step_crosses_the_wire_and_the_snap() -> void:
	var command := NightCommand.new()
	command.view_step = 65_535
	var back := NetWire.read_command(NetWire.command(command))
	assert_int(back.view_step).is_equal(65_535)
	assert_int(NetWire.quantize(command).view_step).is_equal(65_535)
	command.view_step = 0
	assert_int(NetWire.read_command(NetWire.command(command)).view_step).is_equal(0)
	command.view_step = -1
	assert_int(NetWire.read_command(NetWire.command(command)).view_step).is_equal(-1)
	assert_int(NetWire.command(command).size()).is_equal(NetWire.COMMAND_SIZE)
