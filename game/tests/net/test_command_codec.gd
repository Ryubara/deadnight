# The numbers of a command on the wire: how far a step can be from what was sent, and that both
# ends snap the same way.
extends GdUnitTestSuite

const HALF_YAW := CommandCodec.YAW_STEP / 2.0 + 1.0e-9
const HALF_LOOK := CommandCodec.LOOK_STEP / 2.0 + 1.0e-9


func _random_command(rng: RandomNumberGenerator, seq: int) -> NightCommand:
	var command := NightCommand.new()
	command.seq = seq
	command.motion.move = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	command.motion.yaw = rng.randf_range(-20.0, 20.0)
	command.motion.pitch = rng.randf_range(-1.2, 0.9)
	command.motion.sprint = rng.randf() < 0.5
	command.motion.aim = rng.randf() < 0.3
	command.motion.jump = rng.randf() < 0.1
	command.motion.throw_over = rng.randf() < 0.1
	command.fire = rng.randf() < 0.4
	command.use = rng.randf() < 0.1
	command.origin = Vector3(
		rng.randf_range(-60.0, 60.0), rng.randf_range(0.0, 3.0), rng.randf_range(-60.0, 60.0)
	)
	command.dir = CommandCodec.direction_from_angles(
		rng.randf_range(-PI, PI), rng.randf_range(-1.0, 1.0)
	)
	return command


func test_a_turn_is_kept_to_half_a_step_whatever_the_number_of_turns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 300:
		var yaw := rng.randf_range(-100.0, 100.0)
		var snapped := CommandCodec.snap_yaw(yaw)
		assert_float(snapped).is_greater_equal(-PI)
		assert_float(snapped).is_less(PI)
		assert_float(absf(angle_difference(yaw, snapped))).is_less(HALF_YAW)
	assert_float(CommandCodec.snap_yaw(0.0)).is_equal(0.0)
	assert_float(CommandCodec.snap_yaw(TAU + 0.5)).is_equal_approx(0.5, CommandCodec.YAW_STEP)


func test_a_look_is_kept_to_half_a_step_and_held_to_a_quarter_turn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	for i in 300:
		var pitch := rng.randf_range(-PI / 2.0, PI / 2.0)
		assert_float(absf(CommandCodec.snap_pitch(pitch) - pitch)).is_less(HALF_LOOK)
	assert_float(CommandCodec.snap_pitch(5.0)).is_equal_approx(PI / 2.0, 1.0e-6)
	assert_float(CommandCodec.snap_pitch(-5.0)).is_equal_approx(-PI / 2.0, 1.0e-6)


func test_a_move_is_kept_to_a_byte_and_a_point_to_a_centimetre() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 79
	for i in 300:
		var move := Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.7, 0.7))
		assert_float(CommandCodec.snap_move(move).distance_to(move)).is_less(0.0056)
		var point := Vector3(
			rng.randf_range(-300, 300), rng.randf_range(-3, 3), rng.randf_range(-300, 300)
		)
		assert_float(CommandCodec.snap_point(point).distance_to(point)).is_less(0.0087)
	assert_vector(CommandCodec.snap_move(Vector2(1, 1))).is_equal_approx(
		Vector2(1, 1).normalized(), Vector2.ONE * 0.01
	)


func test_snapping_twice_changes_nothing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 80
	for i in 200:
		var command := _random_command(rng, i)
		var once := NetWire.quantize(command)
		var twice := NetWire.quantize(once)
		assert_vector(twice.motion.move).is_equal(once.motion.move)
		assert_float(twice.motion.yaw).is_equal(once.motion.yaw)
		assert_float(twice.motion.pitch).is_equal(once.motion.pitch)
		assert_vector(twice.origin).is_equal(once.origin)
		assert_vector(twice.dir).is_equal_approx(once.dir, Vector3.ONE * 1.0e-6)
		# Everything but the shot direction, which the last step of may differ by one.
		assert_array(NetWire.command(twice).slice(0, 19)).is_equal(
			NetWire.command(once).slice(0, 19)
		)


func test_the_client_and_the_server_read_the_same_numbers() -> void:
	# What the predicting client moves with (quantize) is, to the bit, what the server decodes.
	var rng := RandomNumberGenerator.new()
	rng.seed = 81
	for i in 200:
		var command := _random_command(rng, i)
		var sent := NetWire.quantize(command)
		var read := NetWire.read_command(NetWire.command(command))
		assert_vector(sent.motion.move).is_equal(read.motion.move)
		assert_float(sent.motion.yaw).is_equal(read.motion.yaw)
		assert_float(sent.motion.pitch).is_equal(read.motion.pitch)
		assert_bool(sent.fire).is_equal(read.fire)
		assert_bool(sent.motion.fire).is_equal(read.fire)
		assert_bool(sent.motion.sprint).is_equal(command.motion.sprint)
		assert_bool(sent.motion.jump).is_equal(command.motion.jump)
		# The motion alone snaps the same way.
		var motion := command.motion.quantize()
		assert_vector(motion.move).is_equal(read.motion.move)
		assert_float(motion.yaw).is_equal(read.motion.yaw)
		assert_float(motion.pitch).is_equal(read.motion.pitch)


func test_the_snap_keeps_the_ids_the_wire_does_not_carry() -> void:
	var command := NightCommand.new()
	command.player_id = 3
	command.muzzle = Vector3(1.234567, 2.0, 3.0)
	var sent := NetWire.quantize(command)
	assert_int(sent.player_id).is_equal(3)
	assert_vector(sent.muzzle).is_equal(Vector3(1.234567, 2.0, 3.0))


func test_a_shot_direction_survives_to_a_fraction_of_a_degree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 82
	for i in 200:
		var direction := CommandCodec.direction_from_angles(
			rng.randf_range(-PI, PI), rng.randf_range(-1.4, 1.4)
		)
		var command := NightCommand.new()
		command.dir = direction
		var back := NetWire.read_command(NetWire.command(command)).dir
		assert_float(rad_to_deg(direction.angle_to(back))).is_less(0.01)
