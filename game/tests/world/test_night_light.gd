# The night closing in (issue #314): the lot's ambient, moon, sky and fog follow the round
# the client hears (`NightLight`), from the rules' `ambient_for_round`, eased over the break,
# and never so dark that the field stops being readable. What it looks like is in the captures
# of `night_closes_in.tscn`; these tests keep the numbers a capture cannot.
extends GdUnitTestSuite

const SCENE := "res://world/drive_in_greybox.tscn"
## The darkest night keeps at least this much ambient plus moon light (round 1 has 0.60).
const MIN_FILL := 0.2
## Fog at 25 m, where a zombie must still read, stays under this fraction.
const MAX_FOG_AT_25M := 0.5

var _lot: Node3D
var _lighting: Node3D
var _state: ClientState
var _rounds: RoundTuning
var _light: NightLight


func before_test() -> void:
	_lot = auto_free(load(SCENE).instantiate()) as Node3D
	_lighting = _lot.get_node("Lighting")
	_state = ClientState.new()
	_rounds = RoundTuning.new()
	_light = auto_free(NightLight.new(_lighting, _rounds, _state)) as NightLight


func _env() -> Environment:
	return (_lighting.get_node("WorldEnvironment") as WorldEnvironment).environment


func _moon() -> DirectionalLight3D:
	return _lighting.get_node("Moon") as DirectionalLight3D


## The round announced by a break, settled (a change takes `EASE_SECONDS`).
func _settle_at(round_number: int) -> void:
	_state.apply_events([{"type": &"break_started", "next_round": round_number, "seconds": 20.0}])
	_light.advance(LightTuning.current().ease_seconds)


func _fill() -> float:
	return _env().ambient_light_energy + _moon().light_energy


func test_round_one_is_the_night_as_built() -> void:
	var built := load(SCENE).instantiate() as Node3D
	var built_env := (built.get_node("Lighting/WorldEnvironment") as WorldEnvironment).environment
	_settle_at(1)
	assert_float(_env().ambient_light_energy).is_equal_approx(
		built_env.ambient_light_energy, 0.0001
	)
	assert_float(_env().fog_density).is_equal_approx(built_env.fog_density, 0.0001)
	assert_float(_env().background_energy_multiplier).is_equal(1.0)
	built.free()


func test_the_ambient_follows_the_round() -> void:
	var last := INF
	for round_number in range(1, 15):
		_settle_at(round_number)
		var ambient := _env().ambient_light_energy
		(
			assert_float(ambient)
			. override_failure_message("round %d did not darken" % round_number)
			. is_less(last)
		)
		last = ambient
		assert_float(_light.level).is_equal_approx(_rounds.ambient_for_round(round_number), 0.0001)


func test_the_light_follows_the_rules_number_and_stops_at_its_floor() -> void:
	_settle_at(14)
	var darkest := _env().ambient_light_energy
	_settle_at(40)
	assert_float(_env().ambient_light_energy).is_equal_approx(darkest, 0.0001)
	assert_float(_light.darkness()).is_equal_approx(1.0, 0.0001)


func test_every_part_of_the_night_darkens_together() -> void:
	var moon := _moon().light_energy
	var fog := _env().fog_density
	_settle_at(10)
	assert_float(_moon().light_energy).is_less(moon)
	assert_float(_env().fog_density).is_greater(fog)
	assert_float(_env().background_energy_multiplier).is_less(1.0)
	# The fog is matched to the sky's horizon by hand: they dim by the same factor.
	assert_float(_env().fog_light_energy).is_equal(_env().background_energy_multiplier)


func test_the_darkest_round_is_still_readable() -> void:
	_settle_at(14)
	assert_float(_fill()).is_greater(MIN_FILL)
	assert_float(1.0 - exp(-_env().fog_density * 25.0)).is_less(MAX_FOG_AT_25M)
	assert_float(_env().fog_sky_affect).is_equal(0.0)


func test_a_new_round_eases_in_with_no_pop() -> void:
	_settle_at(1)
	var before := _env().ambient_light_energy
	_state.apply_events([{"type": &"break_started", "next_round": 10, "seconds": 20.0}])
	assert_float(_env().ambient_light_energy).is_equal(before)
	var last := before
	var biggest_step := 0.0
	var frames := int(LightTuning.current().ease_seconds * 60.0)
	for _i in frames:
		_light.advance(1.0 / 60.0)
		var now := _env().ambient_light_energy
		assert_float(now).is_less_equal(last)
		biggest_step = maxf(biggest_step, last - now)
		last = now
	assert_float(last).is_less(before * 0.85)
	# The whole fall happens in 12 s at 60 frames a second: no frame takes more than a few percent.
	assert_float(biggest_step).is_less((before - last) * 0.03)
	# The round starting later changes nothing: the break already announced it.
	_state.apply_events([{"type": &"round_started", "round": 10, "zombie_count": 5}])
	assert_float(_env().ambient_light_energy).is_equal(last)


func test_a_client_joining_in_round_eight_starts_there() -> void:
	_state.apply_events([{"type": &"frame", "round": 8, "zombies": PackedByteArray()}])
	assert_float(_light.level).is_equal_approx(_rounds.ambient_for_round(8), 0.0001)
	var ambient := _env().ambient_light_energy
	_settle_at(8)
	assert_float(_env().ambient_light_energy).is_equal_approx(ambient, 0.0001)


func test_one_night_does_not_darken_the_next() -> void:
	_settle_at(14)
	var next := auto_free(load(SCENE).instantiate()) as Node3D
	var env := (next.get_node("Lighting/WorldEnvironment") as WorldEnvironment).environment
	assert_float(env.ambient_light_energy).is_equal_approx(0.24, 0.0001)


func test_the_real_night_darkens_when_its_round_begins() -> void:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	var light := night.get_node("NightLight") as NightLight
	var env := (
		(night.world.greybox.get_node("Lighting/WorldEnvironment") as WorldEnvironment).environment
	)
	var round_one := env.ambient_light_energy
	night.server.rules.round_number = 9
	night.server.rules.apply(RulesAction.skip_break())
	NightFixture.run(night, 3)
	assert_int(light.round_target).is_equal(10)
	light.advance(LightTuning.current().ease_seconds)
	assert_float(env.ambient_light_energy).is_less(round_one * 0.8)
	night.queue_free()
