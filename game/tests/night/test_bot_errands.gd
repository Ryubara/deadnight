# Bots that spend points and keep the lot running (bots plan, phase 4), scenarios 8, 9, 11, 21 and
# 22 in the real lot with the real server: a door whose price a person at the door holds too is left
# to them until the grace has passed, a refused buy backs off thirty seconds with no loop, a breach
# with a board down is repaired in a break and left when a zombie comes to the boards, a tank under
# a quarter is fed by one bot, and a door a person pinged is bought when it can be paid. The
# generator care (the field's breaker on, an area's while people are in it) is here too. Ticks are
# run by hand; the only awaits are the few physics frames the navigation server needs.
extends GdUnitTestSuite

const STEP := Night.STEP
const TICKS_PER_SECOND := 60
const SEED := 41
## A break longer than any test: nothing spawns and no round begins while a bot walks.
const LONG_BREAK := 3000.0
## Physics frames the navigation server is given to take a new mesh.
const SETTLE_FRAMES := 60
## The lot's doors in the order they can be bought.
const DOORS: Array[StringName] = [
	&"door_concession", &"door_booth", &"door_back_lot", &"door_yard", &"door_road"
]
const DOOR := &"door_concession"
const BOOTH_DOOR := &"door_booth"

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


## A tuning with a break that does not end.
func _tuning() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	return tuning


## A night with `humans` stand-ins (seats 1 to humans) and `bots` hosted bots after them, in a long
## first break, the bots shopping.
func _night(humans: int, bots: int, profile: BotProfile = null) -> SeatedNight:
	var night := await NightFixture.seat(self, humans + bots, _tuning(), SEED, true)
	for id in range(1, humans + 1):
		night.human(id)
	for id in range(humans + 1, humans + bots + 1):
		night.stand_still = true
		night.seat(id, profile if profile != null else BotProfile.regular(), SEED + id)
	await night.settle(12)
	_catcher.start()
	return night


func _give(night: SeatedNight, id: int, points: int) -> void:
	# Set outright: the rules grant points but never take them back.
	night.server.rules.players[id].points = points


func _place(night: SeatedNight, id: int, at: Vector3) -> void:
	night.server.body_of(id).teleport(at + Vector3(0.0, 0.1, 0.0))


func _seconds(night: SeatedNight, seconds: float) -> void:
	night.run(int(seconds * TICKS_PER_SECOND))


## Runs until `done` is true or `seconds` pass; returns the seconds it took, or -1.
func _until(night: SeatedNight, seconds: float, done: Callable) -> float:
	for tick in int(seconds * TICKS_PER_SECOND):
		night.tick()
		if done.call():
			return float(tick) / TICKS_PER_SECOND
	return -1.0


func _door_open(night: SeatedNight, id: StringName) -> bool:
	return night.server.rules.is_door_open(id)


func _stand(night: SeatedNight, door_id: StringName) -> Vector3:
	var at: Vector3 = night.level.shop.door_stands[door_id][0]
	return NavigationServer3D.map_get_closest_point(night.world.map(), at)


func _bot(night: SeatedNight, id: int) -> BotClient:
	for candidate in night.host.bots:
		if candidate.state.player_id == id:
			return candidate
	return null


## Sells doors to seat 1 through the rules and waits for the navigation mesh to take them in.
func _open(night: SeatedNight, doors: Array[StringName]) -> void:
	for door_id in doors:
		night.open_door(door_id)
	await night.settle(SETTLE_FRAMES)


func test_a_bot_with_the_price_walks_to_the_first_door_and_buys_it() -> void:
	var night := await _night(0, 1)
	_give(night, 1, 400)
	var took := _until(night, 90.0, func() -> bool: return _door_open(night, DOOR))
	assert_float(took).is_greater(0.0)
	assert_int(night.server.rules.points_of(1)).is_less(400)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_bot_in_the_ticket_plaza_buys_the_holster_at_its_machine_and_stays_inside() -> void:
	# The road door's area is the plaza and nothing past it (#686): the bot's way to the machine at
	# the south wall is the lot's mesh, and no tick of the walk is past the wall.
	var profile := BotProfile.regular()
	# The plaza's machine is the Third Holster (#687), the dearest perk.
	profile.shopping.assign([&"tonic_third_holster"])
	var night := await _night(0, 1, profile)
	await _open(night, DOORS)
	await night.settle(SETTLE_FRAMES * 4)
	# The plaza is lit by the back lot's circuit; with it on the bot has no breaker to go and throw.
	for circuit in [&"concession", &"booth", &"back_lot"]:
		night.server.rules.apply(RulesAction.set_circuit(circuit, true))
	_give(night, 1, 6000)
	var machine := Vector3(0.0, 0.0, 56.0)
	var start := NavigationServer3D.map_get_closest_point(night.world.map(), Vector3(-10, 0, 45))
	assert_float(start.z).override_failure_message("no plaza in the mesh: %s" % start).is_greater(
		44.0
	)
	_place(night, 1, start)
	var farthest := -INF
	var took := _until(
		night,
		60.0,
		func() -> bool:
			farthest = maxf(farthest, night.server.body_of(1).global_position.z)
			return night.server.rules.players[1].tonics.has(&"tonic_third_holster")
	)
	assert_float(took).is_greater(0.0)
	var at := night.server.body_of(1).global_position
	assert_float(Vector2(at.x - machine.x, at.z - machine.z).length()).is_less(3.2)
	assert_float(farthest).is_less(58.0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- Scenario 8: a person at the door holds the price too ---


## Seconds a bot with 400 points takes to open the concession door, with a person (seat 1) standing
## at the door who holds `person_points`.
func _door_time(person_points: int) -> float:
	var night := await _night(1, 1)
	var door_at := _stand(night, DOOR)
	_place(night, 1, door_at)
	_give(night, 1, person_points)
	_give(night, 2, 400)
	var took := _until(night, 120.0, func() -> bool: return _door_open(night, DOOR))
	night.dispose()
	return took


func test_scenario_8_a_person_at_the_door_with_the_price_is_given_the_grace_first() -> void:
	var free := await _door_time(100)
	var claimed := await _door_time(400)
	assert_float(free).is_greater(0.0)
	assert_float(claimed).is_greater(0.0)
	# The person could not pay: the bot walked and bought. The person could: it waited the grace.
	assert_float(claimed).is_greater(BotErrands.CLAIM_GRACE)
	assert_float(free).is_less(claimed)


# --- Scenario 9: a refused buy backs off ---


func test_scenario_9_a_refused_buy_backs_off_thirty_seconds_and_does_not_loop() -> void:
	var night := await _night(0, 1)
	var door_at := _stand(night, DOOR)
	_place(night, 1, door_at)
	night.run(30)
	# The bot is told it holds 400; the server holds none: every purchase is refused.
	var denied: Array[float] = []
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"frame":
			night.server.rules.players[1].points = 0
			event["players"][1]["points"] = 400
		elif event["type"] == &"purchase_denied":
			denied.append(float(night.server.tick_count) / TICKS_PER_SECOND)
	_seconds(night, 25.0)
	assert_int(denied.size()).is_equal(1)
	assert_bool(_door_open(night, DOOR)).is_false()
	# After the back-off it tries once more, and again only thirty seconds later.
	_seconds(night, 40.0)
	assert_int(denied.size()).is_between(2, 3)
	for i in range(1, denied.size()):
		assert_float(denied[i] - denied[i - 1]).is_greater(BotErrands.BACK_OFF - 0.5)
	assert_int(_bot(night, 1).telemetry.counters[&"rejected_buys"]).is_equal(denied.size())
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- Scenario 11: boards ---


## The breach `id` with `down` boards torn off.
func _tear(night: SeatedNight, id: StringName, down: int) -> void:
	for _i in down:
		night.server.rules.barricades.tear(id)


func _boards(night: SeatedNight, id: StringName) -> int:
	return night.server.rules.barricades.boards_of(id)


func test_scenario_11_a_breach_is_repaired_in_a_break_and_paid_for() -> void:
	var night := await _night(0, 1)
	var id: StringName = night.level.shop.repair_stands.keys()[0]
	_tear(night, id, 3)
	var whole := night.level.shop.boards
	var points := night.server.rules.points_of(1)
	var took := _until(night, 90.0, func() -> bool: return _boards(night, id) >= whole)
	assert_float(took).is_greater(0.0)
	assert_int(night.server.rules.points_of(1)).is_equal(points + 3 * 12)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_scenario_11_the_repair_stops_while_a_zombie_is_at_the_boards() -> void:
	var night := await _night(0, 1)
	var id: StringName = night.level.shop.repair_stands.keys()[0]
	var whole := night.level.shop.boards
	_tear(night, id, 4)
	# The bot walks to the breach and puts the first board back.
	var started := _until(night, 90.0, func() -> bool: return _boards(night, id) > whole - 4)
	assert_float(started).is_greater(0.0)
	var centre: Vector3 = night.level.shop.repair_centres[id]
	var stand: Vector3 = night.level.shop.repair_stands[id]
	var outside := centre + (centre - stand).normalized() * 1.5
	night.hold_fire = true
	var zombie := night.server.sim.spawn(2000, 0.0, outside)
	zombie.enter(ZombieBody.Mode.CHASE)
	night.run(60)
	var before := _boards(night, id)
	_seconds(night, 5.0)
	assert_int(_boards(night, id)).is_equal(before)
	assert_bool(_bot(night, 1).intent.use_held).is_false()
	# The zombie goes; the bot goes back to the boards and finishes.
	night.hold_fire = false
	night.server.sim.despawn(2000)
	var done := _until(night, 60.0, func() -> bool: return _boards(night, id) >= whole)
	assert_float(done).is_greater(0.0)
	night.dispose()


func test_a_breach_a_person_is_working_at_is_left_to_them() -> void:
	var night := await _night(1, 1)
	var id: StringName = night.level.shop.repair_stands.keys()[0]
	_tear(night, id, 2)
	_place(night, 1, night.level.shop.repair_stands[id])
	_seconds(night, 30.0)
	assert_int(_boards(night, id)).is_equal(night.level.shop.boards - 2)
	night.dispose()


# --- Scenario 21: the tank is low ---


func _fuel_buyers(night: SeatedNight) -> Array[int]:
	var buyers: Array[int] = []
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"purchase_made" and event["item_id"] == &"fuel_can":
			buyers.append(event["player_id"])
	return buyers


func test_scenario_21_a_tank_under_a_quarter_is_fed_by_one_bot() -> void:
	var night := await _night(0, 3)
	await _open(night, DOORS)
	for id in [1, 2, 3]:
		_give(night, id, 500)
	night.server.rules.generator.fuel = 20.0
	var buyers := _fuel_buyers(night)
	var took := _until(
		night, 150.0, func() -> bool: return night.server.rules.generator.fuel > 30.0
	)
	assert_float(took).is_greater(0.0)
	_seconds(night, 20.0)
	assert_int(buyers.size()).is_equal(1)
	var others := 0
	for bot in night.host.bots:
		if bot.state.player_id != buyers[0]:
			others += int((bot.brain as BotFightBrain).get(&"_errands").counts.get("fuel", 0))
	assert_int(others).is_equal(0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_the_turn_for_the_can_passes_to_the_next_bot_when_the_first_is_stuck() -> void:
	var night := await _night(0, 2)
	await _open(night, DOORS)
	for id in [1, 2]:
		_give(night, id, 500)
	night.server.rules.generator.fuel = 20.0
	var buyers := _fuel_buyers(night)
	# Whichever bot is nearer to the cans goes first: stop its brain so it never gets there.
	var first := 1 if _stand_distance(night, 1) <= _stand_distance(night, 2) else 2
	_bot(night, first).brain_enabled = false
	var took := _until(
		night, 200.0, func() -> bool: return night.server.rules.generator.fuel > 30.0
	)
	assert_float(took).is_greater(BotErrands.TURN_SECONDS - 1.0)
	assert_int(buyers.size()).is_equal(1)
	assert_bool(buyers[0] != first).is_true()
	night.dispose()


func _stand_distance(night: SeatedNight, id: int) -> float:
	var here := night.server.body_of(id).global_position
	var best := INF
	for at: Vector3 in night.level.shop.fuel_stands.values():
		best = minf(best, Vector2(here.x - at.x, here.z - at.z).length())
	return best


func test_a_bot_that_cannot_pay_for_a_can_does_not_go() -> void:
	var night := await _night(0, 2)
	await _open(night, DOORS)
	_give(night, 1, 0)
	_give(night, 2, 500)
	night.server.rules.generator.fuel = 20.0
	var buyers := _fuel_buyers(night)
	_until(night, 150.0, func() -> bool: return night.server.rules.generator.fuel > 30.0)
	assert_int(buyers.size()).is_equal(1)
	assert_int(buyers[0]).is_equal(2)
	night.dispose()


# --- Scenario 22: a person pings a door ---


func test_scenario_22_a_door_a_person_pinged_is_bought_when_it_can_be_paid() -> void:
	var pinged := await _ping_run(true)
	var control := await _ping_run(false)
	assert_bool(pinged).is_true()
	# The same bot with the same points saves for the re-cut and leaves the yard door shut.
	assert_bool(control).is_false()


## Whether the yard door (500) is open after a minute, with or without a person's ping on it. The
## bot holds 520 and saves for the re-cut (1500), so only an order buys the door.
func _ping_run(ping: bool) -> bool:
	var night := await _night(1, 1)
	await _open(night, [DOOR])
	_give(night, 1, 100)
	_give(night, 2, 520)
	if ping:
		var index := night.world.door_ids().find(&"door_yard")
		var at: Vector3 = night.level.shop.door_stands[&"door_yard"][0]
		var answer := night.server.ping(1, {"kind": &"door", "pos": at, "subject": index})
		assert_str(String(answer)).is_equal("")
	_seconds(night, 60.0)
	var open := _door_open(night, &"door_yard")
	night.dispose()
	return open


func test_a_ping_the_person_could_pay_for_is_left_to_them_for_a_while() -> void:
	var night := await _night(1, 1)
	await _open(night, [DOOR])
	_give(night, 1, 600)
	_give(night, 2, 520)
	var index := night.world.door_ids().find(&"door_yard")
	var at: Vector3 = night.level.shop.door_stands[&"door_yard"][0]
	night.server.ping(1, {"kind": &"door", "pos": at, "subject": index})
	var took := _until(night, 90.0, func() -> bool: return _door_open(night, &"door_yard"))
	assert_float(took).is_greater(BotErrands.PING_DEFER)
	night.dispose()


# --- Manners and care ---


func test_no_door_is_bought_while_a_teammate_is_down() -> void:
	var night := await _night(1, 1)
	_give(night, 1, 100)
	_give(night, 2, 400)
	night.server.rules.apply(RulesAction.set_downed(1, true))
	_seconds(night, 25.0)
	assert_bool(_door_open(night, DOOR)).is_false()
	night.server.rules.apply(RulesAction.set_downed(1, false))
	var took := _until(night, 90.0, func() -> bool: return _door_open(night, DOOR))
	assert_float(took).is_greater(0.0)
	night.dispose()


func test_a_bot_does_no_errand_while_a_zombie_is_near() -> void:
	var night := await _night(0, 1)
	var here := night.server.body_of(1).global_position
	night.hold_fire = true
	var zombie := night.server.sim.spawn(2001, 0.0, here + Vector3(0.0, 0.0, -3.0))
	zombie.enter(ZombieBody.Mode.CHASE)
	# The bot has made the zombie out before it holds the price.
	_seconds(night, 2.0)
	_give(night, 1, 400)
	_seconds(night, 20.0)
	assert_bool(_door_open(night, DOOR)).is_false()
	night.hold_fire = false
	night.server.sim.despawn(2001)
	var took := _until(night, 90.0, func() -> bool: return _door_open(night, DOOR))
	assert_float(took).is_greater(0.0)
	night.dispose()


func test_the_fields_breaker_is_thrown_back_on_when_someone_turns_it_off() -> void:
	var night := await _night(0, 1)
	night.server.rules.apply(RulesAction.set_circuit(&"screen_lot", false))
	var took := _until(
		night, 60.0, func() -> bool: return night.server.rules.generator.circuits[&"screen_lot"]
	)
	assert_float(took).is_greater(0.0)
	night.dispose()


func test_an_areas_breaker_is_on_while_a_person_is_in_it_and_off_when_the_area_is_empty() -> void:
	var night := await _night(1, 1)
	await _open(night, [DOOR])
	var lamps: Array = night.level.shop.circuit_lamps[&"concession"]
	_place(night, 1, NavigationServer3D.map_get_closest_point(night.world.map(), lamps[0]))
	var circuits: Dictionary = night.server.rules.generator.circuits
	assert_bool(circuits[&"concession"]).is_false()
	var on := _until(night, 90.0, func() -> bool: return circuits[&"concession"])
	assert_float(on).is_greater(0.0)
	# Everyone leaves: the circuit goes off after the area has been empty a while.
	_place(night, 1, Autopilot.HOME)
	var off := _until(night, 120.0, func() -> bool: return not circuits[&"concession"])
	assert_float(off).is_greater(BotErrands.AREA_EMPTY)
	night.dispose()


func test_an_areas_breaker_stays_off_when_the_tank_is_low() -> void:
	var night := await _night(1, 1)
	await _open(night, [DOOR])
	var lamps: Array = night.level.shop.circuit_lamps[&"concession"]
	_place(night, 1, NavigationServer3D.map_get_closest_point(night.world.map(), lamps[0]))
	_give(night, 2, 0)
	night.server.rules.generator.fuel = 20.0
	_seconds(night, 40.0)
	assert_bool(night.server.rules.generator.circuits[&"concession"]).is_false()
	night.dispose()
