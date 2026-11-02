# The ping message: ten bytes from a client, checked on the way in, never trusted.
extends GdUnitTestSuite


func test_a_mark_is_ten_bytes_and_comes_back_whole() -> void:
	var bytes := NetWire.mark(PingBoard.ENEMY, Vector3(3.25, 0.5, -17.5), 4242)
	assert_int(bytes.size()).is_equal(NetWire.MARK_SIZE)
	assert_int(NetWire.MARK_SIZE).is_equal(10)
	var action := NetWire.read_mark(bytes)
	assert_str(action["type"]).is_equal("ping")
	assert_str(action["kind"]).is_equal("enemy")
	assert_vector(action["pos"]).is_equal_approx(Vector3(3.25, 0.5, -17.5), Vector3.ONE * 0.01)
	assert_int(action["subject"]).is_equal(4242)


func test_every_kind_has_its_own_index() -> void:
	for kind in PingBoard.KINDS:
		var back := NetWire.read_mark(NetWire.mark(kind, Vector3.ZERO, 0))
		assert_str(back["kind"]).is_equal(str(kind))


func test_a_mark_of_another_size_or_kind_is_nothing() -> void:
	var bytes := NetWire.mark(PingBoard.HERE, Vector3.ZERO, 0)
	assert_dict(NetWire.read_mark(bytes.slice(0, 9))).is_empty()
	var long := bytes.duplicate()
	long.append(0)
	assert_dict(NetWire.read_mark(long)).is_empty()
	bytes[1] = PingBoard.KINDS.size()
	assert_dict(NetWire.read_mark(bytes)).is_empty()
	bytes[1] = 0
	bytes[0] = NetWire.Type.COMMAND
	assert_dict(NetWire.read_mark(bytes)).is_empty()


func test_the_host_limits_let_a_mark_in_but_not_a_flood() -> void:
	assert_bool(PeerLimits.fits(NetWire.Type.MARK, NetWire.MARK_SIZE)).is_true()
	assert_bool(PeerLimits.fits(NetWire.Type.MARK, 9)).is_false()
	var limits := PeerLimits.new()
	var bytes := NetWire.mark(PingBoard.HERE, Vector3.ZERO, 0)
	var verdicts: Array = []
	for _i in 12:
		verdicts.append(limits.judge(bytes, 1.0))
	assert_int(verdicts[0]).is_equal(PeerLimits.Verdict.ACCEPT)
	assert_int(verdicts[11]).is_equal(PeerLimits.Verdict.DROP)
