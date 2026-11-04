# The arrival message: two bytes from a client, checked on the way in, never trusted (#1057).
extends GdUnitTestSuite


func test_the_protocol_moved_for_the_new_message() -> void:
	assert_int(NetWire.VERSION).is_greater_equal(15)
	assert_int(NetWire.MIN_VERSION).is_greater_equal(15)
	assert_bool(NetWire.accepts(14)).is_false()
	assert_bool(NetWire.accepts(NetWire.VERSION)).is_true()


func test_an_arrival_is_two_bytes_and_comes_back_whole() -> void:
	for begin in [true, false]:
		var bytes := NetWire.arrival(begin)
		assert_int(bytes.size()).is_equal(NetWire.ARRIVAL_SIZE)
		assert_int(NetWire.ARRIVAL_SIZE).is_equal(2)
		assert_int(bytes[0]).is_equal(NetWire.Type.ARRIVAL)
		assert_int(NetWire.read_arrival(bytes)).is_equal(1 if begin else 0)


func test_its_type_is_its_own() -> void:
	var others := [
		NetWire.Type.HELLO,
		NetWire.Type.WELCOME,
		NetWire.Type.COMMAND,
		NetWire.Type.TICK,
		NetWire.Type.PING,
		NetWire.Type.PONG,
		NetWire.Type.REFUSED,
		NetWire.Type.MARK,
		NetWire.Type.PLATFORM,
		NetWire.Type.ORDER,
		LookWire.Type.LOOK,
	]
	assert_bool(NetWire.Type.ARRIVAL in others).is_false()


func test_an_arrival_of_another_size_or_kind_is_nothing() -> void:
	var bytes := NetWire.arrival(true)
	assert_int(NetWire.read_arrival(bytes.slice(0, 1))).is_equal(-1)
	var long := bytes.duplicate()
	long.append(0)
	assert_int(NetWire.read_arrival(long)).is_equal(-1)
	bytes[1] = 2
	assert_int(NetWire.read_arrival(bytes)).is_equal(-1)
	bytes[1] = 1
	bytes[0] = NetWire.Type.PLATFORM
	assert_int(NetWire.read_arrival(bytes)).is_equal(-1)


func test_the_server_takes_it_at_two_bytes_and_a_rate() -> void:
	assert_int(PeerLimits.size_of(NetWire.Type.ARRIVAL)).is_equal(2)
	assert_bool(PeerLimits.fits(NetWire.Type.ARRIVAL, 2)).is_true()
	assert_bool(PeerLimits.fits(NetWire.Type.ARRIVAL, 3)).is_false()
	var limits := PeerLimits.new()
	var verdicts := []
	for _i in 8:
		verdicts.append(limits.judge(NetWire.arrival(true), 0.0))
	assert_bool(verdicts.has(PeerLimits.Verdict.DROP)).is_true()
