# The generator panel is not always on: it shows for a moment when the night makes progress at
# the generator (fuel added, a circuit switched, a warning), slides in, holds, leaves. Time is
# stepped by hand (`advance`), never read from a clock (#218).
extends GdUnitTestSuite

const STEP := 0.1
const TOTAL := HudFuel.IN_TIME + HudFuel.HOLD_TIME + HudFuel.OUT_TIME

var _host: Control
var _fixture: HudFixture
var _hud: Hud


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)
	_fixture = HudFixture.make(_host, 2)
	_hud = _fixture.hud


func after_test() -> void:
	UIMotion.reduced = false


func _step(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(STEP, left)
		_hud.fuel.advance(step)
		left -= step


func _refill() -> void:
	_hud.state.apply_event({"type": &"fuel_changed", "fuel": 80.0, "delta": 5.0})


func test_it_is_hidden_until_the_generator_makes_progress() -> void:
	assert_bool(_hud.fuel.showing).is_false()
	assert_bool(_hud.fuel.visible).is_false()
	assert_float(_hud.fuel.get_combined_minimum_size().y).is_equal(0.0)
	_step(30.0)
	assert_bool(_hud.fuel.visible).is_false()


func test_burning_fuel_is_not_progress_and_does_not_show_it() -> void:
	for fuel in [99.0, 98.0, 97.0]:
		_hud.state.apply_event({"type": &"fuel_changed", "fuel": fuel, "delta": -1.0})
	assert_bool(_hud.fuel.showing).is_false()
	assert_bool(HudFuel.is_progress({"type": &"fuel_changed", "delta": -1.0})).is_false()
	assert_bool(HudFuel.is_progress({"type": &"zombie_removed"})).is_false()


func test_each_step_of_progress_shows_it() -> void:
	var progress: Array[Dictionary] = [
		{"type": &"fuel_changed", "fuel": 50.0, "delta": 5.0},
		{"type": &"circuit_changed", "circuit_id": &"booth", "on": true},
		{"type": &"fuel_low"},
		{"type": &"fuel_empty"},
		{"type": &"fuel_restored"},
	]
	for event in progress:
		var fixture := HudFixture.make(_host, 1)
		fixture.hud.state.apply_event(event)
		assert_bool(fixture.hud.fuel.showing).override_failure_message(str(event)).is_true()
		fixture.hud.get_parent().remove_child(fixture.hud)
		fixture.hud.free()


func test_it_comes_in_holds_and_leaves_on_the_stepped_clock() -> void:
	_refill()
	assert_bool(_hud.fuel.showing).is_true()
	assert_float(_hud.fuel.presence()).is_equal(0.0)
	_step(HudFuel.IN_TIME * 0.5)
	assert_float(_hud.fuel.presence()).is_equal_approx(0.5, 0.001)
	_step(HudFuel.IN_TIME * 0.5)
	assert_float(_hud.fuel.presence()).is_equal_approx(1.0, 0.001)
	# Held for its seconds, at full strength.
	_step(HudFuel.HOLD_TIME * 0.5)
	assert_float(_hud.fuel.presence()).is_equal(1.0)
	assert_bool(_hud.fuel.visible).is_true()
	_step(HudFuel.HOLD_TIME * 0.5)
	assert_float(_hud.fuel.presence()).is_equal(1.0)
	# Out: halfway through the exit it is half as strong.
	_step(HudFuel.OUT_TIME * 0.5)
	assert_float(_hud.fuel.presence()).is_equal_approx(0.5, 0.01)
	_step(HudFuel.OUT_TIME * 0.5 + STEP)
	assert_bool(_hud.fuel.showing).is_false()
	assert_bool(_hud.fuel.visible).is_false()
	assert_float(_hud.fuel.presence()).is_equal(0.0)


func test_more_progress_while_it_shows_keeps_it_up_for_another_hold() -> void:
	_refill()
	_step(HudFuel.IN_TIME + 3.0)
	_refill()
	_step(3.0)
	assert_bool(_hud.fuel.showing).is_true()
	assert_float(_hud.fuel.presence()).is_equal(1.0)
	_step(HudFuel.HOLD_TIME + HudFuel.OUT_TIME + STEP)
	assert_bool(_hud.fuel.showing).is_false()


func test_progress_during_the_exit_brings_it_back_without_a_jump() -> void:
	_refill()
	_step(HudFuel.IN_TIME + HudFuel.HOLD_TIME + HudFuel.OUT_TIME * 0.5)
	var before := _hud.fuel.presence()
	_refill()
	assert_float(_hud.fuel.presence()).is_less_equal(before + 0.001)
	_step(HudFuel.IN_TIME)
	assert_float(_hud.fuel.presence()).is_equal(1.0)


func test_it_slides_in_and_the_feed_under_it_follows() -> void:
	_hud.events_feed.push("RUBY OPENED THE CONCESSION STAND")
	await await_idle_frame()
	await await_idle_frame()
	var resting := _hud.events_feed.global_position.y
	_refill()
	_step(HudFuel.IN_TIME * 0.5)
	await await_idle_frame()
	await await_idle_frame()
	var halfway := _hud.events_feed.global_position.y
	_step(HudFuel.IN_TIME)
	await await_idle_frame()
	await await_idle_frame()
	var full := _hud.events_feed.global_position.y
	assert_float(halfway).is_greater(resting)
	assert_float(full).is_greater(halfway)
	# The ticket's full height is what the feed made room for, with the gap.
	assert_float(full - resting).is_equal_approx(
		_hud.fuel.panel.get_combined_minimum_size().y + HudStyle.GAP, 1.0
	)
	# Out again: the feed is back where it was.
	_step(HudFuel.HOLD_TIME + HudFuel.OUT_TIME + STEP)
	await await_idle_frame()
	await await_idle_frame()
	assert_float(_hud.events_feed.global_position.y).is_equal_approx(resting, 0.5)


func test_the_panel_slides_down_from_above_its_slot() -> void:
	_refill()
	_step(HudFuel.IN_TIME * 0.25)
	assert_float(_hud.fuel.panel.position.y).is_less(0.0)
	_step(HudFuel.IN_TIME)
	assert_float(_hud.fuel.panel.position.y).is_equal_approx(0.0, 0.001)


func test_with_reduced_motion_it_fades_without_sliding() -> void:
	UIMotion.reduced = true
	_refill()
	_step(HudFuel.IN_TIME * 0.25)
	assert_float(_hud.fuel.panel.position.y).is_equal_approx(0.0, 0.001)
	assert_float(_hud.fuel.panel.modulate.a).is_less(1.0)
	assert_float(_hud.fuel.panel.modulate.a).is_greater(0.0)
	_step(HudFuel.IN_TIME)
	assert_float(_hud.fuel.panel.modulate.a).is_equal(1.0)


func test_a_snapshot_does_not_show_it() -> void:
	_fixture.rules.apply(RulesAction.start())
	_hud.state.load_snapshot(_fixture.rules.to_dict())
	assert_bool(_hud.fuel.showing).is_false()


func test_a_held_panel_costs_no_layout() -> void:
	_refill()
	_step(HudFuel.IN_TIME + 0.5)
	var changes := [0]
	_hud.fuel.minimum_size_changed.connect(func() -> void: changes[0] += 1)
	_step(2.0)
	assert_int(changes[0]).is_equal(0)
