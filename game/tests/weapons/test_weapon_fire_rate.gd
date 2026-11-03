extends GdUnitTestSuite
## A held trigger reaches each weapon's nominal rate on average (the tick's leftover is carried,
## #708), never fires twice in a tick, and a pause banks nothing.

const STEP := 1.0 / 60.0
const SECONDS := 30.0
## A rate within a fifth of a percent over a long hold: the step loses at most one shot.
const SLACK := 0.002


## Ticks (0-based) on which a held trigger fires, over `ticks`.
func _held(state: WeaponState, ticks: int) -> Array[int]:
	var fired: Array[int] = []
	state.ammo = 999999
	for tick in ticks:
		if state.fire_block() == &"":
			state.fire()
			fired.append(tick)
		state.tick(STEP)
	return fired


func _defs() -> Array[WeaponDef]:
	return WeaponsFixture.all_defs()


func test_a_held_trigger_reaches_the_nominal_rate_for_every_weapon() -> void:
	for def in _defs():
		var state := WeaponState.new(def)
		var shots := _held(state, roundi(SECONDS / STEP)).size()
		var nominal := SECONDS * def.rounds_per_second()
		# The first shot is at once, so the count is floor(T / interval) + 1 at the exact rate.
		(
			assert_float(float(shots))
			. override_failure_message(
				"%s fired %d shots in %.0f s, nominal %.1f" % [def.id, shots, SECONDS, nominal]
			)
			. is_between(nominal * (1.0 - SLACK), nominal * (1.0 + SLACK) + 1.0)
		)


func test_a_faster_interval_gets_its_whole_share() -> void:
	# What a faster-fire multiplier does to the def (x1.33): 4.06 ticks, which used to land on 5.
	for id in [&"smg", &"pistol"]:
		var def := WeaponsFixture.def(id).duplicate() as WeaponDef
		def.fire_interval = def.fire_interval / 1.33
		var shots := _held(WeaponState.new(def), roundi(SECONDS / STEP)).size()
		var nominal := SECONDS * def.rounds_per_second()
		(
			assert_float(float(shots))
			. override_failure_message("%s fired %d, nominal %.1f" % [id, shots, nominal])
			. is_between(nominal * (1.0 - SLACK), nominal * (1.0 + SLACK) + 1.0)
		)


func test_no_shot_is_ever_ahead_of_the_nominal_schedule() -> void:
	for def in _defs():
		var fired := _held(WeaponState.new(def), 600)
		for i in fired.size():
			var due := float(fired[0]) * STEP + float(i) * def.fire_interval
			(
				assert_float(float(fired[i]) * STEP)
				. override_failure_message(
					(
						"%s shot %d came at %.4f s, due %.4f s"
						% [def.id, i, float(fired[i]) * STEP, due]
					)
				)
				. is_greater_equal(due - WeaponState.READY_EPSILON)
			)


func test_a_weapon_fires_once_a_tick_even_when_its_interval_is_shorter() -> void:
	var def := WeaponsFixture.def(&"smg").duplicate() as WeaponDef
	def.fire_interval = STEP * 0.4
	var state := WeaponState.new(def)
	state.ammo = 100
	for _tick in 30:
		state.fire()
		assert_str(state.fire_block()).is_equal("cooldown")
		state.tick(STEP)
	assert_int(state.ammo).is_equal(70)


func test_a_pause_banks_nothing() -> void:
	# The smg's interval is 4.5 ticks: a banked leftover would let the first shot after the pause
	# be followed by a second one a tick early.
	var def := WeaponsFixture.def(&"smg")
	var state := WeaponState.new(def)
	state.ammo = 100
	_held(state, 40)
	for _idle in 120:
		state.tick(STEP)
	assert_float(state.carry).is_equal(0.0)
	assert_float(state.cooldown).is_equal(0.0)
	var fired := _held(state, 60)
	assert_int(fired[0]).is_equal(0)
	# 4.5 ticks to the next shot is 5 steps; with a bank of 0.5 it would be 4.
	assert_int(fired[1] - fired[0]).is_equal(5)


func test_a_whole_tick_interval_is_unchanged() -> void:
	var def := WeaponsFixture.def(&"pistol").duplicate() as WeaponDef
	def.fire_interval = STEP * 6.0
	var fired := _held(WeaponState.new(def), 60)
	assert_array(fired).is_equal([0, 6, 12, 18, 24, 30, 36, 42, 48, 54])
