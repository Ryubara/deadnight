# The standing orders of the bots (#641): the data class on its own, with no night. The server keeps
# one order for the team and one for a bot that was given its own, answers with an event, and puts
# the lot in every frame; a client sends one command through the sender it was given.
extends GdUnitTestSuite

const AT := Vector3(4.0, 0.0, -6.0)


func test_a_night_with_no_order_given_roams() -> void:
	var orders := BotOrders.new()
	var now := orders.order_for(0)
	assert_str(str(now["order"])).is_equal("roam")
	assert_int(now["issuer_id"]).is_equal(0)
	assert_bool((now["at"] as Vector3).is_finite()).is_false()
	# A frame that carries no orders at all (an older server) says the same.
	assert_str(str(BotOrders.current({}, 3)["order"])).is_equal("roam")


func test_the_wheel_reads_the_order_with_a_string_name_key() -> void:
	# `BotOrderLink` asks `answer.get(&"order")`: the keys are strings here and must still be found.
	var orders := BotOrders.new()
	orders.issue(BotOrders.HOLD, 1, AT)
	var frame := {BotOrders.FRAME_KEY: orders.to_frame()}
	assert_str(str(BotOrders.current(frame).get(&"order", &""))).is_equal("hold")
	assert_str(str(BotOrders.current({}).get(&"order", &""))).is_equal("roam")


func test_the_three_orders_are_the_only_ones() -> void:
	assert_array(BotOrders.ORDERS).is_equal([&"follow", &"roam", &"hold"])
	assert_bool(BotOrders.is_order(&"charge")).is_false()
	assert_str(str(BotOrders.DEFAULT)).is_equal("roam")


func test_the_server_keeps_the_order_and_answers_with_the_event() -> void:
	var orders := BotOrders.new()
	var event := orders.issue(BotOrders.HOLD, 1, AT)
	assert_str(str(event["type"])).is_equal("bot_order_set")
	assert_str(str(event["order"])).is_equal("hold")
	assert_int(event["issuer_id"]).is_equal(1)
	assert_vector(event["at"]).is_equal(AT)
	var kept := orders.order_for(5)
	assert_str(str(kept["order"])).is_equal("hold")
	assert_vector(kept["at"]).is_equal(AT)
	# And it is what a bot reads out of the frame.
	var frame := {BotOrders.FRAME_KEY: orders.to_frame()}
	assert_str(str(BotOrders.current(frame, 5)["order"])).is_equal("hold")


func test_an_order_to_one_bot_beats_the_teams_until_the_next_team_order() -> void:
	var orders := BotOrders.new()
	orders.issue(BotOrders.FOLLOW, 1, AT)
	orders.step(1.0)
	orders.issue(BotOrders.HOLD, 1, AT, 3)
	assert_str(str(orders.order_for(3)["order"])).is_equal("hold")
	assert_str(str(orders.order_for(2)["order"])).is_equal("follow")
	assert_str(str(orders.order_for(0)["order"])).is_equal("follow")
	orders.step(1.0)
	orders.issue(BotOrders.ROAM, 1, AT)
	assert_str(str(orders.order_for(3)["order"])).is_equal("roam")


func test_a_person_may_not_order_twice_inside_the_gap() -> void:
	var orders := BotOrders.new()
	assert_str(str(orders.issue(BotOrders.FOLLOW, 1, AT)["type"])).is_equal("bot_order_set")
	var refused := orders.issue(BotOrders.HOLD, 1, AT)
	assert_str(str(refused["type"])).is_equal("bot_order_refused")
	assert_str(str(refused["reason"])).is_equal("too_soon")
	# Another person is not held up by it, and the first may again after the gap.
	assert_str(str(orders.issue(BotOrders.ROAM, 2, AT)["type"])).is_equal("bot_order_set")
	orders.step(BotOrders.GAP + 0.01)
	assert_str(str(orders.issue(BotOrders.HOLD, 1, AT)["type"])).is_equal("bot_order_set")
	assert_str(str(orders.order_for(0)["order"])).is_equal("hold")


func test_an_unknown_order_or_a_place_that_is_not_one_changes_nothing() -> void:
	var orders := BotOrders.new()
	orders.issue(BotOrders.FOLLOW, 1, AT)
	orders.step(1.0)
	assert_str(str(orders.issue(&"charge", 1, AT)["reason"])).is_equal("unknown")
	assert_str(str(orders.issue(BotOrders.HOLD, 1, Vector3(NAN, 0, 0))["reason"])).is_equal(
		"bad_position"
	)
	assert_str(str(orders.order_for(0)["order"])).is_equal("follow")


func test_a_client_sends_one_command_and_keeps_nothing() -> void:
	var sent: Array[Dictionary] = []
	var orders := BotOrders.new()
	orders.sender = func(action: Dictionary) -> void: sent.append(action)
	var action := orders.issue(BotOrders.HOLD, 2, AT)
	assert_int(sent.size()).is_equal(1)
	assert_dict(sent[0]).is_equal(action)
	assert_str(str(action["type"])).is_equal("order")
	assert_str(str(action["order"])).is_equal("hold")
	assert_vector(action["at"]).is_equal(AT)
	assert_int(action["bot_id"]).is_equal(0)
	# It is the server that decides: nothing was kept on this end.
	assert_str(str(orders.order_for(0)["order"])).is_equal("roam")
	# An order that cannot be sends nothing.
	assert_dict(orders.issue(&"charge", 2, AT)).is_empty()
	assert_dict(orders.issue(BotOrders.HOLD, 2, Vector3.INF)).is_empty()
	assert_int(sent.size()).is_equal(1)


func test_the_action_name_is_the_servers() -> void:
	# The bots may not name the night server, so its constant is the bots' string.
	assert_str(str(NightServer.ORDER)).is_equal(str(BotOrders.ACTION))


func test_a_bots_seat_left_takes_its_own_order_with_it() -> void:
	var orders := BotOrders.new()
	orders.issue(BotOrders.FOLLOW, 1, AT)
	orders.step(1.0)
	orders.issue(BotOrders.HOLD, 1, AT, 4)
	orders.forget(4)
	assert_str(str(orders.order_for(4)["order"])).is_equal("follow")
