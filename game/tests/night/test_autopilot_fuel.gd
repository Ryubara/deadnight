# When the bot buys fuel (`AutopilotFuel`): its rule on frames alone, then in a night, where it
# walks to a can when the tank has fallen to the low line and it can pay, buys, and does not buy
# when it cannot pay or the tank is healthy. It sends the same `use` a person does.
extends GdUnitTestSuite

const DOOR := &"door_concession"
const YARD_DOOR := &"door_yard"
const STAND := Vector3(2.5, 0.0, 4.8)
const YARD := Vector3(34.3, 0.0, 15.9)
const HERE := Vector3(0.0, 0.0, -34.0)
const GIVE_UP_TICKS := 3600
## Physics frames the navigation server is given to take a new mesh.
const NAV_FRAMES := 6

var _rule: AutopilotFuel


func before_test() -> void:
	_rule = AutopilotFuel.new()
	_rule.item = RulesFixture.tuning().economy.item(&"fuel_can")
	_rule.goals = {&"SpotStand": STAND, &"SpotYard": YARD}
	_rule.doors = {&"SpotStand": DOOR, &"SpotYard": YARD_DOOR}


func _frame(open: Array, fuel: float, round_number: int = 1) -> Dictionary:
	return {"doors": open, "fuel": fuel, "round": round_number}


func _price(round_number: int = 1) -> int:
	return _rule.item.price_at(round_number)


func test_it_does_not_want_fuel_while_the_tank_is_healthy() -> void:
	assert_bool(_rule.wants(_frame([DOOR], 80.0), 5000)).is_false()
	assert_bool(_rule.wants(_frame([DOOR], 26.0), 5000)).is_false()
	assert_vector(_rule.next_goal(_frame([DOOR], 60.0), HERE, 5000)).is_equal(Vector3.INF)


func test_it_wants_fuel_at_the_low_line_when_it_can_pay_and_not_when_it_cannot() -> void:
	var low := _frame([DOOR], _rule.refuel_at * _rule.capacity)
	assert_bool(_rule.wants(low, _price())).is_true()
	assert_bool(_rule.wants(low, _price() - 1)).is_false()
	assert_vector(_rule.next_goal(low, HERE, _price() - 1)).is_equal(Vector3.INF)


func test_the_price_it_needs_is_the_cans_at_the_round() -> void:
	assert_int(_rule.price(_frame([], 10.0, 1))).is_equal(_price(1))
	assert_int(_rule.price(_frame([], 10.0, 9))).is_equal(_price(9))
	assert_int(_price(9)).is_greater(_price(1))
	var low := _frame([DOOR], 10.0, 9)
	assert_bool(_rule.wants(low, _price(9) - 1)).is_false()
	assert_bool(_rule.wants(low, _price(9))).is_true()


func test_it_walks_only_to_a_spot_whose_area_is_open_and_to_the_nearest_one() -> void:
	var low := _frame([], 10.0)
	assert_vector(_rule.next_goal(low, HERE, 1000)).is_equal(Vector3.INF)
	assert_vector(_rule.next_goal(_frame([DOOR], 10.0), HERE, 1000)).is_equal(STAND)
	var both := _frame([DOOR, YARD_DOOR], 10.0)
	assert_vector(_rule.next_goal(both, Vector3(30.0, 0.0, 10.0), 1000)).is_equal(YARD)
	assert_vector(_rule.next_goal(both, Vector3(0.0, 0.0, 0.0), 1000)).is_equal(STAND)


func test_it_keeps_buying_until_the_tank_is_back_above_its_line() -> void:
	var points := 5000
	assert_bool(_rule.wants(_frame([DOOR], 20.0), points)).is_true()
	# Past the low line but below the line it fills to: still buying.
	assert_bool(_rule.wants(_frame([DOOR], 35.0), points)).is_true()
	assert_bool(_rule.wants(_frame([DOOR], 45.0), points)).is_false()
	# And it does not start again until the tank is low once more.
	assert_bool(_rule.wants(_frame([DOOR], 35.0), points)).is_false()
	assert_bool(_rule.wants(_frame([DOOR], 25.0), points)).is_true()


func test_it_uses_a_spot_only_when_it_wants_fuel_and_the_tank_has_room() -> void:
	var low := _frame([DOOR], 10.0)
	var prompt := {"kind": &"fuel", "id": &"SpotStand", "item": &"fuel_can", "units": 25.0}
	assert_bool(_rule.wants_use(prompt, low, 1000)).is_true()
	assert_bool(_rule.wants_use(prompt, low, _price() - 1)).is_false()
	var full := prompt.duplicate()
	full["units"] = 0.0
	assert_bool(_rule.wants_use(full, low, 1000)).is_false()
	assert_bool(_rule.wants_use(prompt, _frame([DOOR], 90.0), 1000)).is_false()
	(
		assert_bool(_rule.wants_use({"kind": &"circuit", "id": &"booth", "on": false}, low, 1000))
		. is_false()
	)
	assert_bool(_rule.wants_use({}, low, 1000)).is_false()


# --- In a night ---


## A night in autopilot with a long first break, so the bot works undisturbed, the concession
## bought and its circuit left alone.
func _night() -> Night:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 300.0
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT, tuning)
	NightFixture.run(night, 10)
	return night


func _purchases(events: Array[Dictionary]) -> Array[Dictionary]:
	return events.filter(
		func(event: Dictionary) -> bool:
			return event["type"] == &"purchase_made" and event["item_id"] == &"fuel_can"
	)


func test_the_bot_goes_to_the_cans_when_the_tank_is_low_and_buys_one() -> void:
	var night := await _night()
	var rules := night.server.rules
	var events: Array[Dictionary] = []
	night.state.event_received.connect(func(event: Dictionary) -> void: events.append(event))
	rules.apply(RulesAction.grant_points(1, 1000))
	rules.apply(RulesAction.buy(1, DOOR))
	await NightFixture.settle_bake(night)
	# The navigation server takes the new mesh on its next steps.
	for _i in NAV_FRAMES:
		await get_tree().physics_frame
	rules.generator.fuel = rules.tuning.fuel.capacity * rules.tuning.fuel.low_fraction * 0.5
	var low := rules.generator.fuel
	var line := night.autopilot.fuel.fill_to * rules.tuning.fuel.capacity
	var ticks := 0
	while _purchases(events).is_empty() and ticks < GIVE_UP_TICKS:
		night.tick()
		ticks += 1
	assert_int(_purchases(events).size()).is_greater_equal(1)
	assert_float(rules.generator.fuel).is_greater(low + 20.0)
	# It keeps buying until the tank is back above the line it fills to, and then buys no more.
	while rules.generator.fuel <= line and ticks < GIVE_UP_TICKS:
		night.tick()
		ticks += 1
	assert_float(rules.generator.fuel).is_greater(line)
	# The client hears a purchase a tick or two later.
	NightFixture.run(night, 3)
	var bought := _purchases(events).size()
	NightFixture.run(night, 300)
	assert_int(_purchases(events).size()).is_equal(bought)
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_the_bot_buys_nothing_while_the_tank_is_healthy() -> void:
	var night := await _night()
	var rules := night.server.rules
	var events: Array[Dictionary] = []
	night.state.event_received.connect(func(event: Dictionary) -> void: events.append(event))
	rules.apply(RulesAction.grant_points(1, 1000))
	rules.apply(RulesAction.buy(1, DOOR))
	NightFixture.run(night, 900)
	assert_int(_purchases(events).size()).is_equal(0)
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_a_poor_bot_with_a_low_tank_does_not_try_to_buy() -> void:
	var night := await _night()
	var rules := night.server.rules
	var events: Array[Dictionary] = []
	night.state.event_received.connect(func(event: Dictionary) -> void: events.append(event))
	rules.apply(RulesAction.grant_points(1, 150))
	rules.apply(RulesAction.buy(1, DOOR))
	var poorer := rules.points_of(1)
	assert_int(poorer).is_less(rules.price_of(&"fuel_can"))
	rules.generator.fuel = 10.0
	NightFixture.run(night, 600)
	assert_int(_purchases(events).size()).is_equal(0)
	var denied := events.filter(
		func(event: Dictionary) -> bool: return event["type"] == &"purchase_denied"
	)
	assert_int(denied.size()).is_equal(0)
	await NightFixture.settle_bake(night)
	night.queue_free()
