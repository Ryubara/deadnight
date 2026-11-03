# The back lot's lights burn dimmed and failing like a dying battery (issue #851): a seeded
# function of the time and the lamp (`FailingBattery`), on the `back_lot` circuit, readable and
# not a strobe: no second holds more than three flashes (WCAG 2.3.1), the lights never go out
# while their circuit is on, and a sign can follow the flicker through the lamp it follows.
extends GdUnitTestSuite

const RATE := 60.0
## A change of this much of the brightest light, both ways, is one flash (the guidance's general
## flash threshold is 10% of the relative luminance).
const FLASH_STEP := 0.1
const MOST_FLASHES_A_SECOND := 3
const LAMPS := 6
const SECONDS := 900.0

var _lot: Node3D
var _lamps: LotLamps
var _fuel: FuelTuning


func before_test() -> void:
	_lot = await LotFixture.make_lot(self)
	auto_free(_lot.get_parent())
	var rules: GameRules = _lot.get_meta(&"rules")
	_fuel = rules.tuning.fuel
	_lamps = LotLamps.new(_lot)
	_lamps.configure(_fuel)
	_lamps.refresh(0)


func _switch_back_lot(on: bool) -> void:
	_lamps.apply_event({"type": &"circuit_changed", "circuit_id": &"back_lot", "on": on})


## The most flashes any one second holds in `samples` (taken `RATE` a second): a flash is one
## swing of at least `FLASH_STEP` down and the swing back up (or the other way round), found
## with a hysteresis so the slow wander is not counted twice.
static func most_flashes_in_a_second(samples: PackedFloat32Array) -> int:
	var swings: Array[int] = []
	var high := samples[0]
	var low := samples[0]
	var heading := 0
	var extreme := samples[0]
	for i in range(1, samples.size()):
		var value := samples[i]
		if heading == 0:
			high = maxf(high, value)
			low = minf(low, value)
			if value - low >= FLASH_STEP:
				heading = 1
				extreme = value
				swings.append(i)
			elif high - value >= FLASH_STEP:
				heading = -1
				extreme = value
				swings.append(i)
		elif heading > 0:
			if value > extreme:
				extreme = value
			elif extreme - value >= FLASH_STEP:
				heading = -1
				extreme = value
				swings.append(i)
		else:
			if value < extreme:
				extreme = value
			elif value - extreme >= FLASH_STEP:
				heading = 1
				extreme = value
				swings.append(i)
	var most := 0
	var from := 0
	for to in swings.size():
		while float(swings[to] - swings[from]) >= RATE:
			from += 1
		most = maxi(most, to - from + 1)
	# Two swings are one flash.
	return ceili(float(most) / 2.0)


static func _min_of(values: PackedFloat32Array) -> float:
	var lowest := INF
	for value in values:
		lowest = minf(lowest, value)
	return lowest


static func _max_of(values: PackedFloat32Array) -> float:
	var highest := -INF
	for value in values:
		highest = maxf(highest, value)
	return highest


func _series(lamp: int, seed_value: int = -1) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for tick in int(SECONDS * RATE):
		out.append(FailingBattery.level(float(tick) / RATE, lamp, seed_value))
	return out


func test_the_same_seed_gives_the_same_lights_and_another_gives_others() -> void:
	var a := _series(2)
	assert_array(a).is_equal(_series(2))
	assert_array(a).is_not_equal(_series(2, 7))
	assert_array(a).is_not_equal(_series(3))


func test_the_lights_are_dimmed_and_never_go_out() -> void:
	var tuning := LightTuning.current()
	for lamp in LAMPS:
		var series := _series(lamp)
		var floor_level := tuning.failing_base * tuning.failing_floor * 0.5
		assert_float(_min_of(series)).is_greater(floor_level)
		assert_float(_max_of(series)).is_less_equal(tuning.failing_base + tuning.failing_wander)
		var mean := 0.0
		for value in series:
			mean += value
		mean /= float(series.size())
		assert_float(mean).is_between(0.4, tuning.failing_base)


func test_it_stumbles_the_way_a_failing_battery_does() -> void:
	# Each kind of event comes, and the dropouts reach the floor, the sags do not.
	var seen := {}
	for cycle in 300:
		seen[FailingBattery.kind_of(cycle, LightTuning.current().failing_seed)] = true
	assert_int(seen.size()).is_equal(FailingBattery.Kind.size())
	var series := _series(0)
	assert_float(_min_of(series)).is_less(0.12)
	var calm := 0
	for value in series:
		if value > LightTuning.current().failing_base * 0.8:
			calm += 1
	# Most of the time the lot is simply lit, not in an event.
	assert_float(float(calm) / float(series.size())).is_greater(0.5)


func test_no_second_holds_more_than_three_flashes_for_a_lamp_or_for_the_lot() -> void:
	var mean := PackedFloat32Array()
	mean.resize(int(SECONDS * RATE))
	for lamp in LAMPS:
		var series := _series(lamp)
		(
			assert_int(most_flashes_in_a_second(series))
			. override_failure_message("lamp %d" % lamp)
			. is_less_equal(MOST_FLASHES_A_SECOND)
		)
		for i in series.size():
			mean[i] += series[i] / float(LAMPS)
	# What a viewer sees of the lamps together.
	assert_int(most_flashes_in_a_second(mean)).is_less_equal(MOST_FLASHES_A_SECOND)


func test_the_flash_counter_sees_a_strobe() -> void:
	# A negative control: twelve changes a second between full and a tenth is many flashes.
	var strobe := PackedFloat32Array()
	for tick in 600:
		strobe.append(1.0 if (tick / 5) % 2 == 0 else 0.1)
	assert_int(most_flashes_in_a_second(strobe)).is_greater(MOST_FLASHES_A_SECOND)
	var steady := PackedFloat32Array()
	steady.resize(600)
	steady.fill(0.6)
	assert_int(most_flashes_in_a_second(steady)).is_equal(0)


func test_a_fall_is_never_faster_than_a_few_frames_and_never_a_full_swing() -> void:
	var biggest := 0.0
	for lamp in LAMPS:
		var series := _series(lamp)
		for i in range(1, series.size()):
			biggest = maxf(biggest, absf(series[i] - series[i - 1]))
	# A tick (a sixtieth of a second) never moves a light by more than a fifth of its full light.
	assert_float(biggest).is_less(0.2)


func test_the_back_lots_own_lamps_burn_failing_and_nothing_else_does() -> void:
	var failing: Array[String] = []
	for lamp in _lamps.lamps:
		if lamp.failing:
			failing.append(_lot.get_path_to(lamp.light).get_concatenated_names())
			assert_str(String(lamp.circuit)).is_equal("back_lot")
	failing.sort()
	var expected: Array[String] = [
		"BackLot/Lamps/Lamp13/Light",
		"BackLot/Lamps/Lamp14/Light",
		"BackLot/Lamps/Lamp15/Light",
		"BackLot/Lamps/Lamp16/Light",
		"BackLot/Lamps/Lamp17/Light",
		"BackLot/Lamps/NeonSign",
	]
	assert_array(failing).is_equal(expected)
	# The plaza's kiosk is on the same circuit and burns steady.
	var kiosk := _lot.get_node("Road/Lamps/Kiosk")
	for lamp in _lamps.lamps:
		if lamp.light == kiosk:
			assert_bool(lamp.failing).is_false()
			assert_str(String(lamp.circuit)).is_equal("back_lot")


func test_the_back_lot_is_dark_until_its_breaker_and_then_lit_but_dim() -> void:
	var post := _lot.get_node("BackLot/Lamps/Lamp14") as LampPost
	var light := post.get_node("Light") as Light3D
	assert_bool(light.visible).is_false()
	_switch_back_lot(true)
	var energy := light.light_energy
	assert_bool(light.visible).is_true()
	var base := 2.8
	assert_float(energy).is_less(base)
	assert_float(energy).is_greater(0.0)


func test_the_lights_follow_the_flicker_and_stay_on_through_it() -> void:
	_switch_back_lot(true)
	var light := _lot.get_node("BackLot/Lamps/Lamp14/Light") as Light3D
	var seen := PackedFloat32Array()
	for tick in range(0, int(120.0 * RATE)):
		_lamps.refresh(tick)
		assert_bool(light.visible).is_true()
		seen.append(light.light_energy)
	assert_float(_max_of(seen) - _min_of(seen)).is_greater(0.3)
	# The lens, the halo and the pool follow with it, never off.
	var post := _lot.get_node("BackLot/Lamps/Lamp14") as LampPost
	assert_bool((post.get_node("Pool") as MeshInstance3D).visible).is_true()
	assert_bool((post.get_node("Halo") as MeshInstance3D).visible).is_true()


func test_the_flicker_is_only_the_picture_the_dead_see_a_lit_lot() -> void:
	var rules: GameRules = _lot.get_meta(&"rules")
	rules.generator.set_circuit(&"back_lot", true)
	_switch_back_lot(true)
	var under_lamp14 := Vector3(-40.1, 0.0, 24.0)
	for tick in range(0, int(30.0 * RATE), 7):
		_lamps.refresh(tick)
		assert_bool(_lamps.lit_at(under_lamp14, rules.generator)).is_true()
	rules.generator.set_circuit(&"back_lot", false)
	_switch_back_lot(false)
	assert_bool(_lamps.lit_at(under_lamp14, rules.generator)).is_false()


func test_a_sign_follows_the_flicker_through_the_lamp_it_follows() -> void:
	_switch_back_lot(true)
	var sign_light := _lot.get_node("BackLot/Lamps/NeonSign") as Light3D
	var follower := LightFollower.new()
	_lot.add_child(follower)
	follower.light_path = follower.get_path_to(sign_light)
	follower._ready()
	# A sign placed in the scene reads the lamp's energy before the lamps touch it.
	follower.set("_base_energy", 1.8)
	var levels := PackedFloat32Array()
	for tick in range(0, int(60.0 * RATE)):
		_lamps.refresh(tick)
		follower.advance(0.0)
		levels.append(follower.level)
	assert_float(_max_of(levels)).is_less_equal(1.0)
	assert_float(_min_of(levels)).is_greater(0.0)
	assert_float(_max_of(levels) - _min_of(levels)).is_greater(0.3)
	# It follows the lamp and so shares the flash budget.
	assert_int(most_flashes_in_a_second(levels)).is_less_equal(MOST_FLASHES_A_SECOND)


func test_a_low_tank_dims_the_failing_lights_without_adding_a_strobe() -> void:
	var series := PackedFloat32Array()
	for tick in int(SECONDS * RATE):
		series.append(LotLamps.failing_brightness(true, 0.5, tick, 1))
	assert_int(most_flashes_in_a_second(series)).is_less_equal(MOST_FLASHES_A_SECOND)
	assert_float(LotLamps.failing_brightness(true, 0.0, 10, 1)).is_equal(0.0)
	assert_float(LotLamps.failing_brightness(false, 1.0, 10, 1)).is_equal(0.0)
	assert_float(_max_of(series)).is_less(FailingBattery.level(0.0, 1) + 0.5)
