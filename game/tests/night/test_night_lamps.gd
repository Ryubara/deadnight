# The lamps in a night: the rules switch a circuit or run the tank dry, the events reach the
# client, the lamps change, and the dead move at full speed on ground that is no longer lit.
extends GdUnitTestSuite

const CONCESSION_FLOOR := Vector3(0.0, 0.0, 3.0)
const FIELD_LAMP := Vector3(-4.6, 0.0, -34.0)
const FAR := Vector3(0.0, 0.0, -300.0)
const ZOMBIE_SPEED := 2.0


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	return night


func _lamp(night: Night, path: String) -> Light3D:
	return night.world.greybox.get_node(path)


## Speed of a zombie dropped on `point` after the sim has asked about its ground.
func _speed_on(night: Night, point: Vector3) -> float:
	var sim := night.server.sim
	var zombie := sim.spawn(900, ZOMBIE_SPEED, point)
	zombie.enter(ZombieBody.Mode.CHASE)
	for _i in 30:
		sim.tick(ZombieSim.STEP, {1: FAR})
	var speed := zombie.move_speed
	sim.despawn(900)
	return speed


func test_switching_a_circuit_changes_its_lamps_and_the_dead_speed_on_its_ground() -> void:
	var night := await _start()
	var rules := night.server.rules
	var interior := _lamp(night, "Concession/Lamps/InteriorW")
	var lit_speed := ZOMBIE_SPEED * rules.tuning.rounds.lit_speed_multiplier
	assert_bool(interior.visible).is_false()
	assert_bool(night.world.is_lit(CONCESSION_FLOOR)).is_false()
	assert_float(_speed_on(night, CONCESSION_FLOOR)).is_equal_approx(ZOMBIE_SPEED, 0.01)

	night.state.apply_events(rules.apply(RulesAction.set_circuit(&"concession", true)))
	assert_bool(interior.visible).is_true()
	assert_bool(night.world.is_lit(CONCESSION_FLOOR)).is_true()
	assert_float(_speed_on(night, CONCESSION_FLOOR)).is_equal_approx(lit_speed, 0.01)

	night.state.apply_events(rules.apply(RulesAction.set_circuit(&"concession", false)))
	assert_bool(interior.visible).is_false()
	assert_bool(night.world.is_lit(CONCESSION_FLOOR)).is_false()
	assert_float(_speed_on(night, CONCESSION_FLOOR)).is_equal_approx(ZOMBIE_SPEED, 0.01)
	night.queue_free()


func test_the_field_starts_lit_and_the_dead_are_slowed_there() -> void:
	var night := await _start()
	var lit_speed := ZOMBIE_SPEED * night.server.rules.tuning.rounds.lit_speed_multiplier
	assert_bool(_lamp(night, "Field/Lamps/Lamp1/Light").visible).is_true()
	assert_float(_speed_on(night, FIELD_LAMP)).is_equal_approx(lit_speed, 0.01)
	night.queue_free()


func test_a_dry_tank_darkens_the_lamps_and_frees_the_dead_and_a_can_brings_it_back() -> void:
	var night := await _start()
	var rules := night.server.rules
	var post_light := _lamp(night, "Field/Lamps/Lamp1/Light")
	var yard_light := _lamp(night, "GeneratorYard/Lamps/WorkLamp1/Light")
	var headlight := _lamp(night, "Road/Headlights/WreckHeadlightL")
	var lit_speed := ZOMBIE_SPEED * rules.tuning.rounds.lit_speed_multiplier
	night.state.apply_events(rules.apply(RulesAction.skip_break()))
	rules.generator.fuel = 0.05
	NightFixture.run(night, 90)
	assert_float(rules.generator.fuel).is_equal(0.0)
	assert_bool(post_light.visible).is_false()
	assert_bool(yard_light.visible).is_false()
	assert_bool(headlight.visible).is_true()
	assert_bool(night.world.is_lit(FIELD_LAMP)).is_false()
	assert_float(_speed_on(night, FIELD_LAMP)).is_equal_approx(ZOMBIE_SPEED, 0.01)

	night.state.apply_events(rules.apply(RulesAction.grant_points(1, 5000)))
	night.state.apply_events(rules.apply(RulesAction.buy(1, &"fuel_can")))
	NightFixture.run(night, 3)
	assert_bool(post_light.visible).is_true()
	assert_bool(yard_light.visible).is_true()
	assert_bool(night.world.is_lit(FIELD_LAMP)).is_true()
	assert_float(_speed_on(night, FIELD_LAMP)).is_equal_approx(lit_speed, 0.01)
	night.queue_free()


func test_the_lights_flicker_as_the_tank_runs_low_and_the_server_still_calls_it_lit() -> void:
	var night := await _start()
	var rules := night.server.rules
	var post_light := _lamp(night, "Field/Lamps/Lamp1/Light")
	var base := post_light.light_energy
	rules.generator.fuel = rules.tuning.fuel.capacity * rules.tuning.fuel.brownout_fraction * 0.5
	var energies := {}
	# The link delivers a tick late.
	NightFixture.run(night, 3)
	for _i in 120:
		NightFixture.run(night, 1)
		energies[snappedf(post_light.light_energy, 0.001)] = true
	assert_int(energies.size()).is_greater(1)
	for energy: float in energies:
		assert_float(energy).is_less(base)
	assert_bool(night.world.is_lit(FIELD_LAMP)).is_true()
	night.queue_free()
