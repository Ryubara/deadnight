# The lot's lamps hang on the generator's circuits (docs/design/map.md, Light and dark): which
# ground is lit is the rules' word, and how the lights are drawn is a function of the events.
extends GdUnitTestSuite

const CONCESSION_FLOOR := Vector3(0.0, 0.0, 3.0)
const BOOTH_FLOOR := Vector3(0.0, 0.0, 27.0)
const FIELD_LAMP := Vector3(-4.6, 0.0, -34.0)
const YARD_LAMP := Vector3(35.0, 0.0, 12.0)
const HEADLIGHTS := Vector3(-31.0, 0.0, 55.8)
## Under the screen glow, clear of every lamp post.
const SCREEN_GLOW := Vector3(0.0, 0.0, -44.0)

var _lot: Node3D
var _generator: GeneratorState
var _lamps: LotLamps
var _fuel: FuelTuning


func before_test() -> void:
	_lot = await LotFixture.make_lot(self)
	auto_free(_lot.get_parent())
	var rules: GameRules = _lot.get_meta(&"rules")
	_generator = rules.generator
	_fuel = rules.tuning.fuel
	_lamps = LotLamps.new(_lot)
	_lamps.configure(_fuel)
	_lamps.refresh(0)


func _lamp(path: String) -> LotLamps.Lamp:
	var light := _lot.get_node(path)
	for lamp in _lamps.lamps:
		if lamp.light == light:
			return lamp
	return null


func test_every_lamp_hangs_on_a_known_circuit_and_every_circuit_has_lamps() -> void:
	var group_size := _lot.get_tree().get_nodes_in_group(&"powered_light").size()
	assert_int(_lamps.lamps.size()).is_equal(group_size)
	assert_int(group_size).is_greater(20)
	var known: Array = _fuel.circuit_drain.keys() + [LotLamps.MAINS, LotLamps.BATTERY]
	for lamp in _lamps.lamps:
		(
			assert_bool(known.has(lamp.circuit))
			. override_failure_message(str(lamp.light.get_path()))
			. is_true()
		)
	for circuit_id: StringName in _fuel.circuit_drain:
		(
			assert_int(_lamps.lamps_on(circuit_id).size())
			. override_failure_message(str(circuit_id))
			. is_greater(0)
		)


func test_ground_is_lit_by_the_circuit_the_generator_has_on() -> void:
	assert_bool(_lamps.lit_at(FIELD_LAMP, _generator)).is_true()
	assert_bool(_lamps.lit_at(CONCESSION_FLOOR, _generator)).is_false()
	_generator.set_circuit(&"concession", true)
	assert_bool(_lamps.lit_at(CONCESSION_FLOOR, _generator)).is_true()
	assert_bool(_lamps.lit_at(BOOTH_FLOOR, _generator)).is_false()
	_generator.set_circuit(&"concession", false)
	_generator.set_circuit(&"screen_lot", false)
	assert_bool(_lamps.lit_at(CONCESSION_FLOOR, _generator)).is_false()
	assert_bool(_lamps.lit_at(FIELD_LAMP, _generator)).is_false()


func test_a_dry_tank_darkens_every_circuit_and_the_mains_but_not_a_battery() -> void:
	for circuit_id: StringName in _fuel.circuit_drain:
		_generator.set_circuit(circuit_id, true)
	assert_bool(_lamps.lit_at(YARD_LAMP, _generator)).is_true()
	_generator.restore({"fuel": 0.0, "circuits": _generator.circuits})
	for point in [FIELD_LAMP, CONCESSION_FLOOR, BOOTH_FLOOR, YARD_LAMP]:
		(
			assert_bool(_lamps.lit_at(point, _generator))
			. override_failure_message(str(point))
			. is_false()
		)
	assert_bool(_lamps.lit_at(HEADLIGHTS, _generator)).is_true()


func test_the_yard_has_no_switch_and_is_lit_while_the_tank_has_fuel() -> void:
	_generator.set_circuit(&"screen_lot", false)
	assert_bool(_lamps.lit_at(YARD_LAMP, _generator)).is_true()


func test_without_a_generator_every_lamp_is_lit() -> void:
	assert_bool(_lamps.lit_at(BOOTH_FLOOR, null)).is_true()


func test_a_circuit_event_switches_only_its_lamps() -> void:
	var interior := _lamp("Concession/Lamps/InteriorW")
	var beam := _lamp("ProjectionBooth/Lamps/ProjectorBeam")
	assert_bool(interior.light.visible).is_false()
	_lamps.apply_event({"type": &"circuit_changed", "circuit_id": &"concession", "on": true})
	assert_bool(interior.light.visible).is_true()
	assert_float(interior.light.light_energy).is_equal(interior.energy)
	assert_bool(beam.light.visible).is_false()
	_lamps.apply_event({"type": &"circuit_changed", "circuit_id": &"concession", "on": false})
	assert_bool(interior.light.visible).is_false()


func test_a_lamp_post_bulb_glows_with_its_own_light_only() -> void:
	var near := _lamp("Field/Lamps/Lamp1/Light").post
	var yard := _lamp("GeneratorYard/Lamps/WorkLamp1/Light").post
	var bulb := near.get_node("Head") as CSGBox3D
	var yard_bulb := yard.get_node("Head") as CSGBox3D
	assert_object(bulb.material).is_not_same(yard_bulb.material)
	assert_float((bulb.material as StandardMaterial3D).emission_energy_multiplier).is_equal(
		LampPost.BULB_ENERGY
	)
	_lamps.apply_event({"type": &"circuit_changed", "circuit_id": &"screen_lot", "on": false})
	assert_float((bulb.material as StandardMaterial3D).emission_energy_multiplier).is_equal(0.0)
	assert_float((yard_bulb.material as StandardMaterial3D).emission_energy_multiplier).is_equal(
		LampPost.BULB_ENERGY
	)


func test_a_dry_tank_puts_the_lights_out_and_a_refill_brings_them_back() -> void:
	var field := _lamp("Field/Lamps/Lamp1/Light")
	var yard := _lamp("GeneratorYard/Lamps/WorkLamp1/Light")
	var headlight := _lamp("Road/Headlights/WreckHeadlightL")
	_lamps.apply_event({"type": &"fuel_empty"})
	assert_bool(field.light.visible).is_false()
	assert_bool(yard.light.visible).is_false()
	assert_bool(headlight.light.visible).is_true()
	_lamps.apply_event({"type": &"frame", "tick": 10, "fuel": _fuel.capacity})
	_lamps.apply_event({"type": &"fuel_restored"})
	assert_bool(field.light.visible).is_true()
	assert_bool(yard.light.visible).is_true()


func test_the_screen_glow_outlasts_the_generator_but_lights_no_ground() -> void:
	var glow := _lamp("Field/Lamps/ScreenGlow")
	assert_bool(_lamps.lit_at(SCREEN_GLOW, _generator)).is_true()
	_generator.set_circuit(&"screen_lot", false)
	_lamps.apply_event({"type": &"circuit_changed", "circuit_id": &"screen_lot", "on": false})
	assert_bool(glow.light.visible).is_true()
	assert_float(glow.light.light_energy).is_equal_approx(glow.energy * glow.afterglow, 0.001)
	assert_bool(_lamps.lit_at(SCREEN_GLOW, _generator)).is_false()


func test_a_failing_tank_flickers_the_same_way_every_time() -> void:
	var run_a: Array[float] = []
	var run_b: Array[float] = []
	var other: Array[float] = []
	for tick in 120:
		run_a.append(LotLamps.brightness(true, 0.5, tick, 3))
		run_b.append(LotLamps.brightness(true, 0.5, tick, 3))
		other.append(LotLamps.brightness(true, 0.5, tick, 4))
	assert_array(run_a).is_equal(run_b)
	assert_float(run_a.min()).is_less(0.2)
	assert_float(run_a.max()).is_greater(0.5)
	# A lamp changes at most once per slot, not every tick, and not in step with the next lamp.
	var changes := 0
	for tick in range(1, 120):
		if run_a[tick] != run_a[tick - 1]:
			changes += 1
	assert_int(changes).is_less_equal(120 / LotLamps.FLICKER_TICKS)
	assert_array(other).is_not_equal(run_a)


func test_brightness_is_full_when_healthy_and_none_when_off_or_dry() -> void:
	assert_float(LotLamps.brightness(true, 1.0, 77, 2)).is_equal(1.0)
	assert_float(LotLamps.brightness(false, 1.0, 77, 2)).is_equal(0.0)
	assert_float(LotLamps.brightness(true, 0.0, 77, 2)).is_equal(0.0)
	for tick in 200:
		assert_float(LotLamps.brightness(true, 0.1, tick, 5)).is_between(0.0, 0.5)


func test_the_tank_fails_the_lights_over_its_last_tenth_only() -> void:
	_lamps.fuel = _fuel.capacity * _fuel.brownout_fraction
	assert_float(_lamps.power()).is_equal(1.0)
	_lamps.fuel = _fuel.capacity * _fuel.brownout_fraction * 0.5
	assert_float(_lamps.power()).is_equal_approx(0.5, 0.001)
	_lamps.fuel = 0.0
	assert_float(_lamps.power()).is_equal(0.0)
