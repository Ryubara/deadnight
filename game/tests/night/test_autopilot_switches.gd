# When the bot throws a breaker (`AutopilotSwitches`): its rule on frames alone, then in a night,
# where it buys the concession, walks to the post and lights it, and puts the lights out again when
# the tank runs low. It sends the same `use` a person does.
extends GdUnitTestSuite

const DOOR := &"door_concession"
const CIRCUIT := &"concession"
const GIVE_UP_TICKS := 3600
const FIELD_POST := Vector3(0.0, 0.0, -44.8)
const CONCESSION_POST := Vector3(8.5, 0.0, -6.0)
const BOOTH_POST := Vector3(4.6, 0.0, 20.1)
const HERE := Vector3(0.0, 0.0, -34.0)

var _rule: AutopilotSwitches


func before_test() -> void:
	_rule = AutopilotSwitches.new()
	_rule.goals = {&"screen_lot": FIELD_POST, CIRCUIT: CONCESSION_POST, &"booth": BOOTH_POST}
	_rule.doors = {&"screen_lot": &"", CIRCUIT: DOOR, &"booth": &"door_booth"}


## A frame as the server sends it, with the given doors open, circuits on and tank level.
func _frame(open: Array, on: Array, fuel: float = 100.0) -> Dictionary:
	var circuits := {}
	for circuit_id: StringName in _rule.goals:
		circuits[circuit_id] = on.has(circuit_id)
	return {"doors": open, "circuits": circuits, "fuel": fuel}


func test_it_wants_the_circuit_of_a_bought_area_and_the_field_only() -> void:
	assert_bool(_rule.wanted(&"screen_lot", _frame([], []))).is_true()
	assert_bool(_rule.wanted(CIRCUIT, _frame([], []))).is_false()
	assert_bool(_rule.wanted(CIRCUIT, _frame([DOOR], []))).is_true()
	assert_bool(_rule.wanted(&"booth", _frame([DOOR], []))).is_false()


func test_it_walks_to_the_post_of_an_area_it_bought_and_to_none_before() -> void:
	assert_vector(_rule.next_goal(_frame([], [&"screen_lot"]), HERE, false)).is_equal(Vector3.INF)
	var frame := _frame([DOOR], [&"screen_lot"])
	assert_vector(_rule.next_goal(frame, HERE, false)).is_equal(CONCESSION_POST)
	assert_vector(_rule.next_goal(_frame([DOOR], [&"screen_lot", CIRCUIT]), HERE, false)).is_equal(
		Vector3.INF
	)


func test_it_picks_the_nearest_of_two_posts() -> void:
	var frame := _frame([DOOR, &"door_booth"], [&"screen_lot"])
	assert_vector(_rule.next_goal(frame, Vector3(0.0, 0.0, 18.0), false)).is_equal(BOOTH_POST)
	assert_vector(_rule.next_goal(frame, Vector3(8.0, 0.0, -8.0), false)).is_equal(CONCESSION_POST)


func test_a_low_tank_puts_an_area_out_and_it_stays_out_until_the_tank_recovers() -> void:
	var low := _rule.save_below * _rule.capacity - 1.0
	var on := _frame([DOOR], [&"screen_lot", CIRCUIT], low)
	assert_bool(_rule.wanted(CIRCUIT, on)).is_false()
	assert_bool(_rule.wanted(&"screen_lot", on)).is_true()
	# Just past the line it still holds off; past the resume line it lights again.
	var between := (_rule.save_below + _rule.resume_above) / 2.0 * _rule.capacity
	assert_bool(_rule.wanted(CIRCUIT, _frame([DOOR], [], between))).is_false()
	assert_bool(_rule.wanted(CIRCUIT, _frame([DOOR], [CIRCUIT], between))).is_true()
	assert_bool(_rule.wanted(CIRCUIT, _frame([DOOR], [], _rule.capacity))).is_true()


func test_a_trip_to_turn_a_circuit_off_waits_for_the_break() -> void:
	var low := 10.0
	var frame := _frame([DOOR], [&"screen_lot", CIRCUIT], low)
	assert_vector(_rule.next_goal(frame, HERE, false)).is_equal(Vector3.INF)
	assert_vector(_rule.next_goal(frame, HERE, true)).is_equal(CONCESSION_POST)


func test_it_uses_a_post_only_when_it_is_thrown_the_wrong_way() -> void:
	var frame := _frame([DOOR], [&"screen_lot"])
	var off := {"kind": &"circuit", "id": CIRCUIT, "on": false}
	var on := {"kind": &"circuit", "id": CIRCUIT, "on": true}
	assert_bool(_rule.wants_use(off, frame)).is_true()
	assert_bool(_rule.wants_use(on, frame)).is_false()
	# A bought area's post is left alone when it is off for a reason (the door is still closed).
	assert_bool(_rule.wants_use(off, _frame([], []))).is_false()
	assert_bool(_rule.wants_use({"kind": &"door", "id": DOOR, "price": 350}, frame)).is_false()
	assert_bool(_rule.wants_use({}, frame)).is_false()


# --- In a night ---


## A night in autopilot with a long first break, so the bot works undisturbed.
func _night() -> Night:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 300.0
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT, tuning)
	NightFixture.run(night, 10)
	return night


func _changes_of(events: Array[Dictionary], circuit_id: StringName) -> Array[Dictionary]:
	return events.filter(
		func(event: Dictionary) -> bool:
			return event["type"] == &"circuit_changed" and event["circuit_id"] == circuit_id
	)


func test_the_bot_buys_the_concession_walks_to_its_post_and_lights_the_stand() -> void:
	var night := await _night()
	var rules := night.server.rules
	var events: Array[Dictionary] = []
	night.state.event_received.connect(func(event: Dictionary) -> void: events.append(event))
	var interior: Light3D = night.world.greybox.get_node("Concession/Lamps/InteriorW")
	assert_bool(interior.visible).is_false()
	night.state.apply_events(rules.apply(RulesAction.grant_points(1, 500)))
	var ticks := 0
	while not rules.generator.circuits[CIRCUIT] and ticks < GIVE_UP_TICKS:
		night.tick()
		ticks += 1
	# The client hears it a tick or two later.
	NightFixture.run(night, 3)
	assert_bool(rules.is_door_open(DOOR)).is_true()
	assert_bool(rules.generator.circuits[CIRCUIT]).is_true()
	assert_bool(interior.visible).is_true()
	assert_bool(night.world.switches.post(CIRCUIT).is_on()).is_true()
	# Once, and it stays lit: the bot does not flick it back and forth while it stands there.
	NightFixture.run(night, 300)
	assert_int(_changes_of(events, CIRCUIT).size()).is_equal(1)
	assert_bool(rules.generator.circuits[CIRCUIT]).is_true()
	# It threw nothing it had no reason to.
	assert_int(_changes_of(events, &"booth").size()).is_equal(0)
	assert_int(_changes_of(events, &"back_lot").size()).is_equal(0)
	assert_int(_changes_of(events, &"screen_lot").size()).is_equal(0)
	await NightFixture.settle_bake(night)
	night.queue_free()


func test_the_bot_leaves_every_post_alone_while_no_door_is_bought() -> void:
	var night := await _night()
	var events: Array[Dictionary] = []
	night.state.event_received.connect(func(event: Dictionary) -> void: events.append(event))
	NightFixture.run(night, 600)
	(
		assert_array(
			events.filter(func(e: Dictionary) -> bool: return e["type"] == &"circuit_changed")
		)
		. is_empty()
	)
	night.queue_free()


func test_the_bot_puts_the_stand_out_when_the_tank_runs_low_and_keeps_the_field_lit() -> void:
	var night := await _night()
	var rules := night.server.rules
	rules.apply(RulesAction.grant_points(1, 500))
	rules.apply(RulesAction.buy(1, DOOR))
	rules.apply(RulesAction.set_circuit(CIRCUIT, true))
	rules.generator.fuel = rules.tuning.fuel.capacity * rules.tuning.fuel.low_fraction * 0.5
	var ticks := 0
	while rules.generator.circuits[CIRCUIT] and ticks < GIVE_UP_TICKS:
		night.tick()
		ticks += 1
	assert_bool(rules.generator.circuits[CIRCUIT]).is_false()
	assert_bool(rules.generator.circuits[&"screen_lot"]).is_true()
	assert_bool(night.world.switches.post(CIRCUIT).is_on()).is_false()
	await NightFixture.settle_bake(night)
	night.queue_free()
