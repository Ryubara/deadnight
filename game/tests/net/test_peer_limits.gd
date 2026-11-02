# What one connection may send: the sizes, the rates, and the strikes that end in a hang-up. Time
# is fed by hand, so the numbers are exact.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0


func _command(seq: int) -> PackedByteArray:
	var command := NightCommand.new()
	command.seq = seq
	return NetWire.command(command)


func _junk(size: int, type: int = 99) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(size)
	data.fill(7)
	if size > 0:
		data[0] = type
	return data


func test_an_honest_client_is_never_dropped() -> void:
	var limits := PeerLimits.new()
	var now := 0.0
	assert_int(limits.judge(NetWire.hello(), now)).is_equal(PeerLimits.Verdict.ACCEPT)
	assert_int(limits.judge(LookWire.look(CharacterLook.default_look()), now)).is_equal(
		PeerLimits.Verdict.ACCEPT
	)
	for tick in 60 * 60:
		now = tick * STEP
		assert_int(limits.judge(_command(tick), now)).is_equal(PeerLimits.Verdict.ACCEPT)
		if tick % 30 == 0:
			assert_int(limits.judge(NetWire.ping(tick), now)).is_equal(PeerLimits.Verdict.ACCEPT)
	assert_float(limits.strikes).is_equal(0.0)
	assert_int(limits.dropped + limits.malformed).is_equal(0)


func test_a_stall_followed_by_everything_at_once_is_forgiven() -> void:
	# Three seconds of silence (a stalled connection), then the 180 commands that were late all
	# together: inside the burst.
	var limits := PeerLimits.new()
	limits.judge(_command(0), 0.0)
	for i in 180:
		assert_int(limits.judge(_command(i + 1), 3.0)).is_equal(PeerLimits.Verdict.ACCEPT)
	assert_float(limits.strikes).is_equal(0.0)


func test_a_flood_of_commands_is_dropped_and_then_cut_off() -> void:
	var limits := PeerLimits.new()
	var kicked_at := -1
	var accepted := 0
	for i in 5000:
		# 5000 commands in half a second.
		var verdict := limits.judge(_command(i), 0.5 * i / 5000.0)
		if verdict == PeerLimits.Verdict.ACCEPT:
			accepted += 1
		elif verdict == PeerLimits.Verdict.KICK:
			kicked_at = i
			break
	assert_int(kicked_at).is_between(300, 700)
	# What got through is the burst plus the half second's share, not the flood.
	assert_int(accepted).is_less(300)


func test_packets_that_are_not_messages_cost_more_and_end_in_a_hang_up() -> void:
	var cases: Array[PackedByteArray] = [
		PackedByteArray(),
		_junk(PeerLimits.MAX_PACKET + 1, NetWire.Type.COMMAND),
		_junk(1, NetWire.Type.COMMAND),
		_junk(NetWire.COMMAND_SIZE, 99),
		_junk(NetWire.COMMAND_SIZE - 1, NetWire.Type.COMMAND),
		_junk(1, NetWire.Type.HELLO),
		_junk(NetWire.MAX_HELLO + 1, NetWire.Type.HELLO),
		_junk(6, NetWire.Type.PING),
		# The ping of protocol 4, before it carried the round trip.
		_junk(5, NetWire.Type.PING),
		_junk(40_000, NetWire.Type.COMMAND),
	]
	for data in cases:
		var limits := PeerLimits.new()
		assert_int(limits.judge(data, 0.0)).is_equal(PeerLimits.Verdict.DROP)
		assert_int(limits.malformed).is_equal(1)
		var kicked := false
		for i in 40:
			kicked = limits.judge(data, 0.0) == PeerLimits.Verdict.KICK
			if kicked:
				break
		assert_bool(kicked).is_true()


func test_a_server_message_sent_by_a_client_is_not_taken() -> void:
	# TICK, WELCOME, PONG and REFUSED only ever go from the server to a client.
	for type in [NetWire.Type.TICK, NetWire.Type.WELCOME, NetWire.Type.PONG, NetWire.Type.REFUSED]:
		assert_int(PeerLimits.size_of(type)).is_equal(-1)
		assert_int(PeerLimits.new().judge(_junk(9, type), 0.0)).is_equal(PeerLimits.Verdict.DROP)


func test_strikes_wear_off() -> void:
	var limits := PeerLimits.new()
	for i in 10:
		limits.judge(_junk(1), 0.0)
	assert_float(limits.strikes).is_equal(50.0)
	limits.judge(_command(1), 10.0)
	assert_float(limits.strikes).is_equal(0.0)


func test_an_ordinary_stream_with_a_few_bad_packets_stays() -> void:
	# One malformed packet in a hundred, over a minute, wears off faster than it builds.
	var limits := PeerLimits.new()
	var kicked := false
	for tick in 3600:
		var data := _junk(2) if tick % 100 == 0 else _command(tick)
		kicked = kicked or limits.judge(data, tick * STEP) == PeerLimits.Verdict.KICK
	assert_bool(kicked).is_false()


func test_a_content_fault_counts_like_a_malformed_packet() -> void:
	var limits := PeerLimits.new()
	var verdict := PeerLimits.Verdict.DROP
	for i in 30:
		verdict = limits.fault(0.0)
		if verdict == PeerLimits.Verdict.KICK:
			break
	assert_int(verdict).is_equal(PeerLimits.Verdict.KICK)


func test_the_sizes_match_the_wire() -> void:
	assert_int(PeerLimits.size_of(NetWire.Type.COMMAND)).is_equal(_command(1).size())
	assert_int(PeerLimits.size_of(NetWire.Type.HELLO)).is_equal(NetWire.hello().size())
	assert_int(PeerLimits.size_of(NetWire.Type.PING)).is_equal(NetWire.ping(1).size())
	var look := LookWire.look(CharacterLook.default_look())
	assert_int(PeerLimits.size_of(LookWire.Type.LOOK)).is_equal(look.size())
	assert_int(look.size()).is_less_equal(PeerLimits.MAX_PACKET)


func test_a_token_bucket_refills_at_its_rate_up_to_its_burst() -> void:
	var bucket := TokenBucket.new(2.0, 3.0)
	assert_bool(bucket.take(0.0)).is_true()
	assert_bool(bucket.take(0.0)).is_true()
	assert_bool(bucket.take(0.0)).is_true()
	assert_bool(bucket.take(0.0)).is_false()
	assert_bool(bucket.take(0.4)).is_false()
	assert_bool(bucket.take(0.5)).is_true()
	# A long rest fills to the burst and no further.
	assert_bool(bucket.take(100.0)).is_true()
	assert_bool(bucket.take(100.0)).is_true()
	assert_bool(bucket.take(100.0)).is_true()
	assert_bool(bucket.take(100.0)).is_false()


func test_the_version_policy() -> void:
	assert_bool(NetWire.accepts(NetWire.VERSION)).is_true()
	assert_bool(NetWire.accepts(NetWire.VERSION + 1)).is_false()
	assert_bool(NetWire.accepts(NetWire.MIN_VERSION - 1)).is_false()
	assert_bool(NetWire.accepts(0)).is_false()
	assert_bool(NetWire.accepts(255)).is_false()
	var refusal := NetWire.refused(NetWire.Refusal.VERSION)
	assert_int(refusal.size()).is_equal(3)
	assert_int(refusal[2]).is_equal(NetWire.VERSION)
