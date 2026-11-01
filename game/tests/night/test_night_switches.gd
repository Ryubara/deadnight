# The breaker posts in a night: a player walks up to one, the prompt names the lights and what they
# cost, `use` throws the breaker through the rules, and the lamps, the post, the HUD and the dead
# follow. Driven like a client: commands in, events and frames out.
extends GdUnitTestSuite

const CIRCUIT := &"concession"
const HELD_TICKS := 20
const ZOMBIE_SPEED := 2.0
const CONCESSION_FLOOR := Vector3(0.0, 0.0, 3.0)
const FAR := Vector3(0.0, 0.0, -300.0)
## A spot in the field with no door, breach or post in reach.
const NOWHERE := Vector3(0.0, 0.1, -20.0)

var _events: Array[Dictionary] = []


func _start(hud: Hud = null) -> Night:
	_events = []
	var night := await NightFixture.start(self, Night.Mode.MANUAL, null, 7, hud)
	night.state.event_received.connect(func(event: Dictionary) -> void: _events.append(event))
	NightFixture.run(night, 30)
	return night


func _changes() -> Array[Dictionary]:
	return _events.filter(
		func(event: Dictionary) -> bool: return event["type"] == &"circuit_changed"
	)


func _stand_at(night: Night, circuit_id: StringName) -> void:
	night.player().teleport(
		night.world.switches.standing_point(circuit_id) + Vector3(0.0, 0.1, 0.0)
	)
	NightFixture.run(night, 2)


func _use() -> NightCommand:
	var command := NightCommand.new()
	command.use = true
	return command


func _speed_on(night: Night, point: Vector3) -> float:
	var sim := night.server.sim
	var zombie := sim.spawn(900, ZOMBIE_SPEED, point)
	zombie.enter(ZombieBody.Mode.CHASE)
	for _i in 30:
		sim.tick(ZombieSim.STEP, {1: FAR})
	var speed := zombie.move_speed
	sim.despawn(900)
	return speed


func test_the_prompt_names_the_circuit_and_how_it_stands_and_goes_when_the_player_leaves() -> void:
	var night := await _start()
	_stand_at(night, CIRCUIT)
	var prompt: Dictionary = night.state.me()["prompt"]
	assert_str(prompt["kind"]).is_equal("circuit")
	assert_str(prompt["id"]).is_equal(CIRCUIT)
	assert_bool(prompt["on"]).is_false()
	night.player().teleport(NOWHERE)
	NightFixture.run(night, 2)
	assert_dict(night.state.me()["prompt"]).is_empty()
	night.queue_free()


func test_use_at_a_post_switches_the_circuit_and_the_lot_follows() -> void:
	var night := await _start()
	var rules := night.server.rules
	var interior: Light3D = night.world.greybox.get_node("Concession/Lamps/InteriorW")
	var lit_speed := ZOMBIE_SPEED * rules.tuning.rounds.lit_speed_multiplier
	var post := night.world.switches.post(CIRCUIT)
	assert_bool(interior.visible).is_false()
	assert_bool(post.is_on()).is_false()
	assert_float(_speed_on(night, CONCESSION_FLOOR)).is_equal_approx(ZOMBIE_SPEED, 0.01)
	var before := rules.generator.drain_per_second(1, false)
	_stand_at(night, CIRCUIT)

	NightFixture.run(night, 1, _use())
	NightFixture.run(night, 2)
	assert_bool(rules.generator.circuits[CIRCUIT]).is_true()
	assert_int(_changes().size()).is_equal(1)
	assert_str(_changes()[0]["circuit_id"]).is_equal(CIRCUIT)
	assert_bool(_changes()[0]["on"]).is_true()
	assert_bool(post.is_on()).is_true()
	assert_bool(interior.visible).is_true()
	assert_bool(night.state.me()["prompt"]["on"]).is_true()
	assert_bool(night.state.frame["circuits"][CIRCUIT]).is_true()
	assert_float(_speed_on(night, CONCESSION_FLOOR)).is_equal_approx(lit_speed, 0.01)
	# The switch costs what the circuit draws.
	var draw := rules.tuning.fuel.circuit_drain[CIRCUIT]
	assert_float(rules.generator.drain_per_second(1, false) - before).is_equal_approx(draw, 0.0001)

	NightFixture.run(night, 40)
	NightFixture.run(night, 1, _use())
	NightFixture.run(night, 2)
	assert_bool(rules.generator.circuits[CIRCUIT]).is_false()
	assert_bool(post.is_on()).is_false()
	assert_bool(interior.visible).is_false()
	assert_float(_speed_on(night, CONCESSION_FLOOR)).is_equal_approx(ZOMBIE_SPEED, 0.01)
	night.queue_free()


func test_holding_use_does_not_flicker_the_lights() -> void:
	var night := await _start()
	_stand_at(night, CIRCUIT)
	NightFixture.run(night, HELD_TICKS, _use())
	assert_int(_changes().size()).is_equal(1)
	NightFixture.run(night, int(night.server.tuning.switch_interval / Night.STEP), _use())
	assert_int(_changes().size()).is_equal(2)
	night.queue_free()


func test_use_out_of_reach_or_downed_throws_nothing() -> void:
	var night := await _start()
	var rules := night.server.rules
	night.player().teleport(NOWHERE)
	NightFixture.run(night, 2)
	NightFixture.run(night, 5, _use())
	assert_int(_changes().size()).is_equal(0)
	_stand_at(night, CIRCUIT)
	night.state.apply_events(rules.apply(RulesAction.set_downed(1, true)))
	NightFixture.run(night, 5, _use())
	assert_int(_changes().size()).is_equal(0)
	assert_bool(rules.generator.circuits[CIRCUIT]).is_false()
	night.queue_free()


func test_a_door_in_reach_keeps_the_prompt_over_a_post() -> void:
	var night := await _start()
	night.player().teleport(
		night.world.door_points(&"door_concession")[0] + Vector3(0.0, 0.1, -2.0)
	)
	NightFixture.run(night, 2)
	assert_str(night.state.me()["prompt"]["kind"]).is_equal("door")
	night.queue_free()


func test_a_post_throws_a_circuit_with_the_tank_dry_and_the_lights_wait_for_fuel() -> void:
	var night := await _start()
	var rules := night.server.rules
	rules.generator.fuel = 0.0
	NightFixture.run(night, 2)
	_stand_at(night, CIRCUIT)
	NightFixture.run(night, 1, _use())
	NightFixture.run(night, 2)
	assert_bool(rules.generator.circuits[CIRCUIT]).is_true()
	assert_bool(night.world.is_lit(CONCESSION_FLOOR)).is_false()
	rules.generator.add_fuel(30.0)
	assert_bool(night.world.is_lit(CONCESSION_FLOOR)).is_true()
	night.queue_free()


func test_the_hud_names_the_lights_and_what_they_cost() -> void:
	var hud := (load(Hud.SCENE) as PackedScene).instantiate() as Hud
	add_child(hud)
	var night := await _start(hud)
	assert_bool(hud.prompt.visible).is_false()
	assert_bool(hud.fuel.showing).is_false()
	_stand_at(night, CIRCUIT)
	assert_bool(hud.prompt.visible).is_true()
	assert_str(hud.prompt.title_text).is_equal("CONCESSION LIGHTS: OFF")
	# 0.05 units a second of a 100-unit tank: 3% of the tank a minute.
	assert_str(hud.prompt.detail_text).is_equal("COSTS 3% FUEL A MINUTE")
	NightFixture.run(night, 1, _use())
	NightFixture.run(night, 2)
	assert_str(hud.prompt.title_text).is_equal("CONCESSION LIGHTS: ON")
	assert_str(hud.prompt.detail_text).is_equal("SAVES 3% FUEL A MINUTE")
	# Throwing the breaker is progress at the generator: the card shows.
	assert_bool(hud.fuel.showing).is_true()
	night.queue_free()
	hud.queue_free()
