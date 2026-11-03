# The order message: nine bytes from a client, checked on the way in, never trusted (#641).
extends GdUnitTestSuite


func test_the_protocol_moved_past_twelve_for_the_new_message() -> void:
	assert_int(NetWire.VERSION).is_greater(12)
	assert_int(NetWire.MIN_VERSION).is_greater(12)
	assert_bool(NetWire.accepts(12)).is_false()
	assert_bool(NetWire.accepts(NetWire.VERSION)).is_true()


func test_an_order_is_nine_bytes_and_comes_back_whole() -> void:
	var bytes := NetWire.order(BotOrders.HOLD, Vector3(3.25, 0.5, -17.5), 6)
	assert_int(bytes.size()).is_equal(NetWire.ORDER_SIZE)
	assert_int(NetWire.ORDER_SIZE).is_equal(9)
	var action := NetWire.read_order(bytes)
	assert_str(str(action["type"])).is_equal("order")
	assert_str(str(action["order"])).is_equal("hold")
	assert_vector(action["at"]).is_equal_approx(Vector3(3.25, 0.5, -17.5), Vector3.ONE * 0.01)
	assert_int(action["bot_id"]).is_equal(6)


func test_every_order_has_its_own_index() -> void:
	for order in BotOrders.ORDERS:
		var back := NetWire.read_order(NetWire.order(order, Vector3.ZERO, 0))
		assert_str(str(back["order"])).is_equal(str(order))
	assert_bool(NetWire.Type.ORDER in [1, 2, 3, 4, 6, 7, 10, 11, 12]).is_false()


func test_an_order_of_another_size_or_kind_is_nothing() -> void:
	var bytes := NetWire.order(BotOrders.ROAM, Vector3.ZERO, 0)
	assert_dict(NetWire.read_order(bytes.slice(0, 8))).is_empty()
	var long := bytes.duplicate()
	long.append(0)
	assert_dict(NetWire.read_order(long)).is_empty()
	bytes[1] = BotOrders.ORDERS.size()
	assert_dict(NetWire.read_order(bytes)).is_empty()
	bytes[1] = 0
	bytes[0] = NetWire.Type.COMMAND
	assert_dict(NetWire.read_order(bytes)).is_empty()


func test_the_host_limits_let_an_order_in_but_not_a_flood() -> void:
	assert_bool(PeerLimits.fits(NetWire.Type.ORDER, NetWire.ORDER_SIZE)).is_true()
	assert_bool(PeerLimits.fits(NetWire.Type.ORDER, 8)).is_false()
	var limits := PeerLimits.new()
	var bytes := NetWire.order(BotOrders.HOLD, Vector3.ZERO, 0)
	var verdicts: Array = []
	for _i in 12:
		verdicts.append(limits.judge(bytes, 1.0))
	assert_int(verdicts[0]).is_equal(PeerLimits.Verdict.ACCEPT)
	assert_int(verdicts[11]).is_equal(PeerLimits.Verdict.DROP)
