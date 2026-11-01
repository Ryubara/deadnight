# The fuel cans in a night: a player walks to a spot, the card names the can and its price, `use`
# sends the shop's purchase through the rules, and the tank, the lamps, the dead's speed and the
# generator's card follow. Driven like a client: commands in, events and frames out.
extends GdUnitTestSuite

const SPOT := &"SpotYard"
const YARD_FLOOR := Vector3(36.0, 0.0, 12.0)
const ZOMBIE_SPEED := 2.0
const FAR := Vector3(0.0, 0.0, -300.0)
const NOWHERE := Vector3(0.0, 0.1, -20.0)

var _events: Array[Dictionary] = []


func _start(hud: Hud = null) -> Night:
	_events = []
	var night := await NightFixture.start(self, Night.Mode.MANUAL, null, 7, hud)
	night.state.event_received.connect(func(event: Dictionary) -> void: _events.append(event))
	NightFixture.run(night, 30)
	return night


func _stand_at(night: Night, spot: StringName = SPOT) -> void:
	night.player().teleport(night.world.fuel.standing_point(spot) + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 2)


func _use() -> NightCommand:
	var command := NightCommand.new()
	command.use = true
	return command


func _purchases() -> Array[Dictionary]:
	return _events.filter(
		func(event: Dictionary) -> bool:
			return event["type"] == &"purchase_made" and event["item_id"] == &"fuel_can"
	)


func _speed_on(night: Night, point: Vector3) -> float:
	var sim := night.server.sim
	var zombie := sim.spawn(900, ZOMBIE_SPEED, point)
	zombie.enter(ZombieBody.Mode.CHASE)
	for _i in 30:
		sim.tick(ZombieSim.STEP, {1: FAR})
	var speed := zombie.move_speed
	sim.despawn(900)
	return speed


func test_the_prompt_names_the_can_and_its_price_and_goes_when_the_player_leaves() -> void:
	var night := await _start()
	var rules := night.server.rules
	rules.generator.fuel = 40.0
	_stand_at(night)
	var prompt: Dictionary = night.state.me()["prompt"]
	assert_str(prompt["kind"]).is_equal("fuel")
	assert_str(prompt["item"]).is_equal("fuel_can")
	assert_int(prompt["price"]).is_equal(rules.price_of(&"fuel_can"))
	assert_float(prompt["units"]).is_equal(25.0)
	night.player().teleport(NOWHERE)
	NightFixture.run(night, 2)
	assert_dict(night.state.me()["prompt"]).is_empty()
	night.queue_free()


func test_use_buys_a_can_and_the_tank_and_the_points_follow() -> void:
	var night := await _start()
	var rules := night.server.rules
	rules.generator.fuel = 40.0
	var price := rules.price_of(&"fuel_can")
	var points := rules.points_of(1)
	_stand_at(night)
	NightFixture.run(night, 1, _use())
	NightFixture.run(night, 2)
	assert_float(rules.generator.fuel).is_equal_approx(65.0, 0.5)
	assert_int(_purchases().size()).is_equal(1)
	assert_int(_purchases()[0]["price"]).is_equal(price)
	assert_int(rules.points_of(1)).is_equal(points - price)
	assert_float(night.state.frame["fuel"]).is_equal_approx(65.0, 0.5)
	night.queue_free()


func test_a_dry_tank_is_refuelled_and_the_lights_and_the_dead_follow() -> void:
	var night := await _start()
	var rules := night.server.rules
	rules.generator.fuel = 0.0
	NightFixture.run(night, 2)
	assert_bool(night.world.is_lit(YARD_FLOOR)).is_false()
	assert_float(_speed_on(night, YARD_FLOOR)).is_equal_approx(ZOMBIE_SPEED, 0.01)
	_stand_at(night)
	NightFixture.run(night, 1, _use())
	NightFixture.run(night, 2)
	assert_bool(rules.generator.is_powered()).is_true()
	assert_bool(night.world.is_lit(YARD_FLOOR)).is_true()
	var lit_speed := ZOMBIE_SPEED * rules.tuning.rounds.lit_speed_multiplier
	assert_float(_speed_on(night, YARD_FLOOR)).is_equal_approx(lit_speed, 0.01)
	night.queue_free()


func test_holding_use_buys_one_can_each_interval() -> void:
	var night := await _start()
	var rules := night.server.rules
	rules.generator.fuel = 10.0
	_stand_at(night)
	NightFixture.run(night, 20, _use())
	assert_int(_purchases().size()).is_equal(1)
	NightFixture.run(night, int(night.server.tuning.fuel_interval / Night.STEP), _use())
	assert_int(_purchases().size()).is_equal(2)
	night.queue_free()


func test_a_full_tank_refuses_the_can_and_charges_nothing() -> void:
	var night := await _start()
	var rules := night.server.rules
	_stand_at(night)
	assert_float(night.state.me()["prompt"]["units"]).is_equal(0.0)
	assert_int(night.state.me()["prompt"]["price"]).is_equal(0)
	var points := rules.points_of(1)
	NightFixture.run(night, 1, _use())
	NightFixture.run(night, 2)
	assert_int(rules.points_of(1)).is_equal(points)
	var denied := _events.filter(
		func(event: Dictionary) -> bool: return event["type"] == &"purchase_denied"
	)
	assert_int(denied.size()).is_equal(1)
	assert_int(denied[0]["result"]).is_equal(GameRules.BuyResult.TANK_FULL)
	night.queue_free()


func test_a_player_who_cannot_pay_is_refused() -> void:
	var night := await _start()
	var rules := night.server.rules
	rules.generator.fuel = 10.0
	rules.players[1].points = 0
	_stand_at(night)
	NightFixture.run(night, 1, _use())
	NightFixture.run(night, 2)
	assert_float(rules.generator.fuel).is_less_equal(10.0)
	assert_int(_purchases().size()).is_equal(0)
	night.queue_free()


func test_use_out_of_reach_or_downed_buys_nothing() -> void:
	var night := await _start()
	var rules := night.server.rules
	rules.generator.fuel = 10.0
	night.player().teleport(NOWHERE)
	NightFixture.run(night, 2)
	NightFixture.run(night, 5, _use())
	assert_int(_purchases().size()).is_equal(0)
	_stand_at(night)
	night.state.apply_events(rules.apply(RulesAction.set_downed(1, true)))
	NightFixture.run(night, 5, _use())
	assert_int(_purchases().size()).is_equal(0)
	night.queue_free()


func test_the_stand_has_its_own_spot() -> void:
	var night := await _start()
	night.server.rules.generator.fuel = 30.0
	_stand_at(night, &"SpotStand")
	assert_str(night.state.me()["prompt"]["kind"]).is_equal("fuel")
	assert_str(night.state.me()["prompt"]["id"]).is_equal("SpotStand")
	night.queue_free()


func test_the_hud_card_names_the_can_and_a_partial_fill_and_a_full_tank() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var night := await _start(hud)
	var rules := night.server.rules
	assert_bool(hud.prompt.visible).is_false()
	rules.generator.fuel = 40.0
	_stand_at(night)
	assert_bool(hud.prompt.visible).is_true()
	assert_str(hud.prompt.title_text).is_equal("FUEL CAN")
	assert_str(hud.prompt.detail_text).is_equal("+25 UNITS OF FUEL")
	assert_str(hud.prompt.price_text).is_equal("%d POINTS" % rules.price_of(&"fuel_can"))
	rules.generator.fuel = 90.0
	NightFixture.run(night, 2)
	assert_str(hud.prompt.detail_text).is_equal("FILLS UP: +10 UNITS")
	rules.generator.fuel = 100.0
	NightFixture.run(night, 2)
	assert_str(hud.prompt.detail_text).is_equal("THE TANK IS FULL")
	night.queue_free()
	hud.queue_free()


func test_the_generator_card_shows_on_a_refill_and_not_on_the_burn() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var night := await _start(hud)
	var rules := night.server.rules
	rules.generator.fuel = 60.0
	NightFixture.run(night, 90)
	hud.fuel.advance(20.0)
	assert_bool(hud.fuel.showing).is_false()
	_stand_at(night)
	NightFixture.run(night, 1, _use())
	NightFixture.run(night, 2)
	assert_bool(hud.fuel.showing).is_true()
	assert_int(hud.fuel.lit_segments).is_equal(ceili(rules.generator.fraction() * 20.0))
	night.queue_free()
	hud.queue_free()
