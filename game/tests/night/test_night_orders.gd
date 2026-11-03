# The server's side of the bots' orders (#641): `NightServer` takes an `order` action as a person's
# command, decides it (a seated person who is up, an order that exists, not twice in half a second),
# tells everyone with `bot_order_set` and puts the order in every frame. No bots are seated: the
# frame is what they read.
extends GdUnitTestSuite

const SEED := 61
const PERSON := 1


func _night() -> SeatedNight:
	var night := await NightFixture.seat(self, 2, null, SEED)
	await night.settle(12)
	return night


func _events(night: SeatedNight, type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in night.last_events:
		if event["type"] == type:
			found.append(event)
	return found


func test_a_person_orders_the_bots_and_everyone_hears_it_and_every_frame_carries_it() -> void:
	var night := await _night()
	var at := night.server.body_of(PERSON).global_position
	assert_str(str(BotOrders.current(night.frame, 2)["order"])).is_equal("roam")
	var sent := night.give_order(BotOrders.HOLD, PERSON, at)
	assert_str(str(sent["order"])).is_equal("hold")
	night.tick()
	var heard := _events(night, &"bot_order_set")
	assert_int(heard.size()).is_equal(1)
	assert_int(heard[0]["issuer_id"]).is_equal(PERSON)
	var now := BotOrders.current(night.frame, 2)
	assert_str(str(now["order"])).is_equal("hold")
	assert_int(now["issuer_id"]).is_equal(PERSON)
	assert_float(Vector2(now["at"].x - at.x, now["at"].z - at.z).length()).is_less(1.0)
	# And it stays in the frames that follow.
	night.run(30)
	assert_str(str(BotOrders.current(night.frame, 2)["order"])).is_equal("hold")
	night.dispose()


func test_the_issuer_is_the_connection_not_the_message() -> void:
	var night := await _night()
	# A message from seat 2 that says it is from seat 1 is seat 2's.
	var action := BotOrders.command(BotOrders.FOLLOW, Vector3.ZERO)
	action["issuer_id"] = PERSON
	night.server.apply(action, 2)
	night.tick()
	assert_int(BotOrders.current(night.frame, 3)["issuer_id"]).is_equal(2)
	night.dispose()


func test_a_downed_person_gives_no_order_and_an_unknown_one_changes_nothing() -> void:
	var night := await _night()
	night.server.rules.apply(RulesAction.skip_break())
	night.server.rules.apply(RulesAction.blow(PERSON, 500.0))
	night.give_order(BotOrders.HOLD, PERSON, Vector3.ZERO)
	night.tick()
	var refused := _events(night, &"bot_order_refused")
	assert_int(refused.size()).is_equal(1)
	assert_str(str(refused[0]["reason"])).is_equal("down")
	assert_str(str(BotOrders.current(night.frame, 2)["order"])).is_equal("roam")
	# A name nobody knows, from a person on their feet (seat 2).
	var answered := night.server.apply(
		{"type": NightServer.ORDER, "order": &"charge", "at": Vector3.ZERO}, 2
	)
	assert_int(answered.size()).is_equal(1)
	assert_str(str(answered[0]["reason"])).is_equal("unknown")
	assert_str(str(BotOrders.current(night.frame, 3)["order"])).is_equal("roam")
	night.dispose()


func test_a_seat_that_is_not_at_the_table_gives_no_order() -> void:
	var night := await _night()
	var answered := night.server.apply(BotOrders.command(BotOrders.HOLD, Vector3.ZERO), 9)
	assert_int(answered.size()).is_equal(1)
	assert_str(str(answered[0]["reason"])).is_equal("no_seat")
	night.tick()
	assert_str(str(BotOrders.current(night.frame, 2)["order"])).is_equal("roam")
	night.dispose()


func test_one_order_every_half_second_and_the_place_is_the_persons_when_the_one_named_is_far(
) -> void:
	var night := await _night()
	var here := night.server.body_of(PERSON).global_position
	night.give_order(BotOrders.FOLLOW, PERSON, here)
	night.give_order(BotOrders.HOLD, PERSON, here)
	night.tick()
	assert_str(str(BotOrders.current(night.frame, 2)["order"])).is_equal("follow")
	night.run(40)
	# A place a long way off is not taken: the order is given where the person stands.
	night.give_order(BotOrders.HOLD, PERSON, here + Vector3(500.0, 0.0, 0.0))
	night.tick()
	var at: Vector3 = BotOrders.current(night.frame, 2)["at"]
	assert_float(Vector2(at.x - here.x, at.z - here.z).length()).is_less(2.0)
	night.dispose()


func test_a_bots_own_order_goes_with_its_seat_and_the_teams_clears_it() -> void:
	var night := await _night()
	var here := night.server.body_of(PERSON).global_position
	night.give_order(BotOrders.HOLD, PERSON, here, 2)
	night.tick()
	assert_str(str(BotOrders.current(night.frame, 2)["order"])).is_equal("hold")
	assert_str(str(BotOrders.current(night.frame, 3)["order"])).is_equal("roam")
	night.run(40)
	night.give_order(BotOrders.FOLLOW, PERSON, here)
	night.tick()
	assert_str(str(BotOrders.current(night.frame, 2)["order"])).is_equal("follow")
	night.dispose()
