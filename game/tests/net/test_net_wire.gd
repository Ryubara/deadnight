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


func test_a_command_is_47_bytes_and_comes_back_whole() -> void:
	var bytes := NetWire.command(_command())
	assert_int(bytes.size()).is_equal(NetWire.COMMAND_SIZE)
	var back := NetWire.read_command(bytes)
	assert_int(back.seq).is_equal(4_000_000_000)
	# A move longer than 1 is shortened on the way in.
	var shortened := Vector2(0.5, -1.0).limit_length(1.0)
	assert_float(back.motion.move.x).is_equal_approx(shortened.x, 0.001)
	assert_float(back.motion.move.y).is_equal_approx(shortened.y, 0.001)
	assert_float(back.motion.yaw).is_equal_approx(1.25, 0.0001)
	assert_float(back.motion.pitch).is_equal_approx(-0.4, 0.0001)
	assert_bool(back.motion.sprint).is_true()
	assert_bool(back.motion.swap_shoulder).is_true()
	assert_bool(back.motion.jump).is_false()
	assert_bool(back.fire).is_true()
	assert_bool(back.use).is_true()
	assert_bool(back.use_held).is_true()
	assert_bool(back.reload).is_false()
	assert_float(back.origin.distance_to(Vector3(3.0, 1.5, -7.25))).is_less(0.001)


func test_a_command_with_poison_numbers_is_made_harmless() -> void:
	var bytes := NetWire.command(_command())
	bytes.encode_float(5, NAN)
	bytes.encode_float(13, INF)
	bytes.encode_float(35, 0.0)
	bytes.encode_float(39, 0.0)
	bytes.encode_float(43, 0.0)
	var back := NetWire.read_command(bytes)
	assert_vector(back.motion.move).is_equal(Vector2.ZERO)
	assert_float(back.motion.yaw).is_equal(0.0)
	assert_vector(back.dir).is_equal(Vector3.FORWARD)
	bytes.encode_float(5, 90.0)
	bytes.encode_float(9, 0.0)
	assert_float(NetWire.read_command(bytes).motion.move.length()).is_less_equal(1.0001)


func test_wrong_sized_or_unknown_packets_read_as_nothing() -> void:
	var bytes := NetWire.command(_command())
	assert_object(NetWire.read_command(bytes.slice(0, 46))).is_null()
	bytes.append(0)
	assert_object(NetWire.read_command(bytes)).is_null()
	assert_object(NetWire.read_command(PackedByteArray())).is_null()
	assert_object(NetWire.read_command(PackedByteArray([NetWire.Type.TICK, 1, 2]))).is_null()
	assert_dict(NetWire.read_tick(PackedByteArray([NetWire.Type.TICK]))).is_empty()
	assert_dict(NetWire.read_welcome(PackedByteArray([NetWire.Type.WELCOME, 1, 1, 60]))).is_empty()
	# A compressed variable that claims four gigabytes is refused, not allocated.
	var lie := PackedByteArray([NetWire.Type.TICK, 0, 0, 0, 0, 1, 255, 255, 255, 255, 1, 2, 3])
	assert_dict(NetWire.read_tick(lie)).is_empty()


func test_a_welcome_and_a_tick_round_trip_small_and_large() -> void:
	var snapshot := {"round": 3, "players": {1: {"points": 500}}}
	var welcome := NetWire.read_welcome(NetWire.welcome(2, 60, snapshot))
	assert_int(welcome["player_id"]).is_equal(2)
	assert_int(welcome["tick_rate"]).is_equal(60)
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
