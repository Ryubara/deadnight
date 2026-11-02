# The bytes of a night's connection: the fixed command, packed variables, frame deltas, and a
# hostile client's malformed packets.
extends GdUnitTestSuite


func _command() -> NightCommand:
	var command := NightCommand.new()
	command.seq = 4_000_000_000
	command.motion.move = Vector2(0.5, -1.0)
	command.motion.yaw = 1.25
	command.motion.pitch = -0.4
	command.motion.sprint = true
	command.motion.swap_shoulder = true
	command.fire = true
	command.use = true
	command.use_held = true
	command.origin = Vector3(3.0, 1.5, -7.25)
	command.dir = Vector3(0.0, 0.0, -1.0)
	return command


func test_a_command_is_25_bytes_and_comes_back_whole() -> void:
	var bytes := NetWire.command(_command())
	assert_int(bytes.size()).is_equal(NetWire.COMMAND_SIZE)
	assert_int(NetWire.COMMAND_SIZE).is_equal(25)
	var back := NetWire.read_command(bytes)
	assert_int(back.seq).is_equal(4_000_000_000)
	# A move longer than 1 is shortened on the way in; a stick axis is a byte (1/127).
	var shortened := Vector2(0.5, -1.0).limit_length(1.0)
	assert_float(back.motion.move.x).is_equal_approx(shortened.x, 0.008)
	assert_float(back.motion.move.y).is_equal_approx(shortened.y, 0.008)
	assert_float(back.motion.yaw).is_equal_approx(1.25, CommandCodec.YAW_STEP)
	assert_float(back.motion.pitch).is_equal_approx(-0.4, CommandCodec.LOOK_STEP)
	assert_bool(back.motion.sprint).is_true()
	assert_bool(back.motion.swap_shoulder).is_true()
	assert_bool(back.motion.jump).is_false()
	assert_bool(back.fire).is_true()
	assert_bool(back.motion.fire).is_true()
	assert_bool(back.use).is_true()
	assert_bool(back.use_held).is_true()
	assert_bool(back.reload).is_false()
	assert_float(back.origin.distance_to(Vector3(3.0, 1.5, -7.25))).is_less(0.01)
	assert_float(back.dir.distance_to(Vector3(0.0, 0.0, -1.0))).is_less(0.0002)


func test_a_command_with_hostile_bytes_is_made_harmless() -> void:
	# Integers cannot be not-a-number or infinite; the bytes that could still hurt are a move
	# longer than a full push and a look past straight up.
	var bytes := NetWire.command(_command())
	bytes.encode_s8(5, 127)
	bytes.encode_s8(6, 127)
	bytes.encode_s16(9, -32768)
	bytes.encode_s16(21, 32767)
	var back := NetWire.read_command(bytes)
	assert_float(back.motion.move.length()).is_less_equal(1.0001)
	assert_float(back.motion.pitch).is_greater_equal(-PI / 2.0 - 0.0001)
	assert_float(back.dir.length()).is_equal_approx(1.0, 0.0001)
	# A command asked to carry poison numbers sends a harmless one.
	var poison := _command()
	poison.motion.move = Vector2(NAN, INF)
	poison.motion.yaw = INF
	poison.motion.pitch = NAN
	poison.dir = Vector3.ZERO
	poison.origin = Vector3(NAN, 1.0e9, -1.0e9)
	var clean := NetWire.read_command(NetWire.command(poison))
	assert_vector(clean.motion.move).is_equal(Vector2.ZERO)
	assert_float(clean.motion.yaw).is_equal(0.0)
	assert_float(clean.motion.pitch).is_equal(0.0)
	assert_vector(clean.dir).is_equal(Vector3.FORWARD)
	assert_bool(clean.origin.is_finite()).is_true()
	assert_float(absf(clean.origin.y)).is_less_equal(327.68)


func test_wrong_sized_or_unknown_packets_read_as_nothing() -> void:
	var bytes := NetWire.command(_command())
	assert_object(NetWire.read_command(bytes.slice(0, NetWire.COMMAND_SIZE - 1))).is_null()
	bytes.append(0)
	assert_object(NetWire.read_command(bytes)).is_null()
	assert_object(NetWire.read_command(PackedByteArray())).is_null()
	assert_object(NetWire.read_command(PackedByteArray([NetWire.Type.TICK, 1, 2]))).is_null()
	assert_dict(NetWire.read_tick(PackedByteArray([NetWire.Type.TICK]))).is_empty()
	(
		assert_dict(
			NetWire.read_welcome(
				PackedByteArray([NetWire.Type.WELCOME, 1, 1, 60, 1, 2, 3, 4, 5, 6, 7, 8])
			)
		)
		. is_empty()
	)
	# A compressed variable that claims four gigabytes is refused, not allocated.
	var lie := PackedByteArray([NetWire.Type.TICK, 0, 0, 0, 0, 1, 255, 255, 255, 255, 1, 2, 3])
	assert_dict(NetWire.read_tick(lie)).is_empty()


func test_a_welcome_and_a_tick_round_trip_small_and_large() -> void:
	var snapshot := {"round": 3, "players": {1: {"points": 500}}}
	var token := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	var welcome := NetWire.read_welcome(NetWire.welcome(2, 60, token, snapshot))
	assert_int(welcome["player_id"]).is_equal(2)
	assert_int(welcome["tick_rate"]).is_equal(60)
	assert_array(welcome["token"]).is_equal(token)
	assert_dict(welcome["snapshot"]).is_equal(snapshot)
	var big: Array = []
	for i in 200:
		big.append({"type": &"shot_fired", "shooter_id": i, "muzzle": Vector3(i, 0, 0)})
	var packet := NetWire.tick(77, big)
	assert_int(packet.size()).is_less(var_to_bytes(big).size())
	var tick := NetWire.read_tick(packet)
	assert_int(tick["step"]).is_equal(77)
	assert_array(tick["events"]).has_size(200)
	assert_int(tick["events"][199]["shooter_id"]).is_equal(199)
	assert_str(String(tick["events"][3]["type"])).is_equal("shot_fired")


func _frame(tick: int, p1: Vector3, p2: Vector3 = Vector3.ZERO) -> Dictionary:
	var players := {
		1: {"pos": p1, "facing": 0.5, "health": 100.0, "points": 500, "ack": tick},
	}
	if p2 != Vector3.ZERO:
		players[2] = {"pos": p2, "facing": 1.0, "health": 100.0, "points": 500, "ack": tick}
	return {
		"type": &"frame",
		"tick": tick,
		"round": 1,
		"fuel": 80.0,
		"doors": [],
		"zombies": PackedByteArray([1, 2, 3]),
		"players": players,
	}


func test_a_delta_carries_only_what_changed_and_rebuilds_the_frame() -> void:
	var one := _frame(10, Vector3(1, 0, 0))
	var two := _frame(12, Vector3(1.5, 0, 0))
	var delta := FrameDelta.diff(one, two)
	assert_bool(delta.get("delta", false)).is_true()
	assert_bool(delta.has("round")).is_false()
	assert_bool(delta.has("fuel")).is_false()
	assert_bool(delta.has("doors")).is_false()
	assert_bool(delta.has("zombies")).is_false()
	assert_int(delta["tick"]).is_equal(12)
	assert_array(delta["players"][1].keys()).contains_exactly_in_any_order(["pos", "ack"])
	assert_dict(FrameDelta.apply(one, delta)).is_equal(two)
	assert_bool(FrameDelta.diff({}, one) == one).is_true()


func test_a_delta_knows_a_new_player_and_a_player_who_left() -> void:
	var alone := _frame(10, Vector3(1, 0, 0))
	var together := _frame(12, Vector3(1, 0, 0), Vector3(4, 0, 0))
	var joined := FrameDelta.diff(alone, together)
	assert_bool(joined["players"].has(2)).is_true()
	assert_dict(FrameDelta.apply(alone, joined)).is_equal(together)
	var left := FrameDelta.diff(together, _frame(14, Vector3(1, 0, 0)))
	assert_array(left["gone"]).contains_exactly([2])
	assert_bool(FrameDelta.apply(together, left)["players"].has(2)).is_false()


func test_a_still_frame_is_much_smaller_as_a_delta() -> void:
	var one := _frame(10, Vector3(1, 0, 0))
	var two := _frame(12, Vector3(1, 0, 0))
	assert_int(var_to_bytes(FrameDelta.diff(one, two)).size()).is_less(var_to_bytes(two).size() / 2)


func test_a_hello_carries_the_resume_token_when_there_is_one() -> void:
	var fresh := NetWire.read_hello(NetWire.hello())
	assert_int(fresh["version"]).is_equal(NetWire.VERSION)
	assert_int((fresh["token"] as PackedByteArray).size()).is_equal(0)
	var token := PackedByteArray([8, 7, 6, 5, 4, 3, 2, 1])
	var back := NetWire.read_hello(NetWire.hello(token))
	assert_array(back["token"]).is_equal(token)
	# A hello of another length, or a token of the wrong size, is nothing (and sent as none).
	assert_dict(NetWire.read_hello(PackedByteArray([NetWire.Type.HELLO, 3, 1, 2, 3]))).is_empty()
	assert_dict(NetWire.read_hello(PackedByteArray())).is_empty()
	assert_int(NetWire.hello(PackedByteArray([1, 2, 3])).size()).is_equal(2)
	assert_bool(PeerLimits.fits(NetWire.Type.HELLO, 2)).is_true()
	assert_bool(PeerLimits.fits(NetWire.Type.HELLO, 10)).is_true()
	assert_bool(PeerLimits.fits(NetWire.Type.HELLO, 5)).is_false()
	assert_bool(PeerLimits.fits(NetWire.Type.COMMAND, 10)).is_false()
