extends GdUnitTestSuite
## The touch aim assist as pure functions (#286): which zombie it helps with, how much it slows the
## look drag, how far it turns the view, and when the crosshair counts as on a zombie. No scene.

const EYE := Vector3(0.0, 1.6, 0.0)
const AHEAD := Vector3(0.0, 0.0, -1.0)

var _tuning := AimAssistTuning.new()


## A walker `distance` metres ahead and `right` metres to the right of the view axis.
func _zombie(distance: float, right := 0.0) -> Dictionary:
	return {"position": Vector3(right, 0.0, -distance), "yaw": 0.0, "scale": 1.0}


func _chest(target: Dictionary) -> Vector3:
	return (target["position"] as Vector3) + Vector3.UP * _tuning.aim_height


func test_no_strength_helps_with_nothing() -> void:
	var found := AimAssist.pick(EYE, AHEAD, [_zombie(8.0)], 0.0, _tuning)
	assert_bool(found.is_empty()).is_true()
	assert_float(AimAssist.friction(found, 0.0, _tuning)).is_equal(1.0)


func test_the_ray_through_the_chest_is_closeness_one() -> void:
	var target := _zombie(8.0)
	var dir := (_chest(target) - EYE).normalized()
	var found := AimAssist.pick(EYE, dir, [target], 0.5, _tuning)
	assert_float(found["closeness"]).is_equal_approx(1.0, 0.001)
	assert_float(found["distance"]).is_equal_approx(EYE.distance_to(_chest(target)), 0.001)


func test_closeness_falls_to_nothing_at_the_edge_of_the_capture() -> void:
	var radius := AimAssist.capture_radius(1.0, _tuning)
	var inside := _zombie(8.0, radius * 0.5)
	var outside := _zombie(8.0, radius * 1.3)
	var level := (_chest(_zombie(8.0)) - EYE).normalized()
	var near := AimAssist.pick(EYE, level, [inside], 1.0, _tuning)
	assert_float(near["closeness"]).is_between(0.35, 0.65)
	assert_bool(AimAssist.pick(EYE, level, [outside], 1.0, _tuning).is_empty()).is_true()


func test_a_stronger_setting_reaches_further_from_the_crosshair() -> void:
	var level := (_chest(_zombie(8.0)) - EYE).normalized()
	var off_axis := _zombie(8.0, 0.7)
	assert_bool(AimAssist.pick(EYE, level, [off_axis], 0.2, _tuning).is_empty()).is_true()
	assert_bool(AimAssist.pick(EYE, level, [off_axis], 1.0, _tuning).is_empty()).is_false()


func test_it_picks_the_zombie_nearest_the_ray_not_the_nearest_zombie() -> void:
	var level := (_chest(_zombie(10.0)) - EYE).normalized()
	var close_but_off := _zombie(4.0, 0.9)
	var far_but_on := _zombie(10.0, 0.05)
	var found := AimAssist.pick(EYE, level, [close_but_off, far_but_on], 1.0, _tuning)
	assert_vector(found["point"]).is_equal_approx(_chest(far_but_on), Vector3.ONE * 0.01)


func test_a_zombie_behind_beyond_reach_or_under_a_wall_is_ignored() -> void:
	var behind := {"position": Vector3(0.0, 0.0, 6.0), "yaw": 0.0}
	var far := _zombie(_tuning.reach + 5.0)
	var walled := _zombie(8.0)
	var level := (_chest(walled) - EYE).normalized()
	assert_bool(AimAssist.pick(EYE, level, [behind, far], 1.0, _tuning).is_empty()).is_true()
	# A wall 3 m along the segment stands between the lens and the zombie.
	var wall := func(_from: Vector3, _to: Vector3) -> float: return 3.0
	assert_bool(AimAssist.pick(EYE, level, [walled], 1.0, _tuning, wall).is_empty()).is_true()
	# A wall behind the zombie does not.
	var behind_wall := func(_from: Vector3, _to: Vector3) -> float: return 20.0
	(
		assert_bool(AimAssist.pick(EYE, level, [walled], 1.0, _tuning, behind_wall).is_empty())
		. is_false()
	)


func test_friction_is_one_far_away_and_lowest_on_the_chest() -> void:
	var target := _zombie(8.0)
	var level := (_chest(target) - EYE).normalized()
	var on := AimAssist.pick(EYE, level, [target], 1.0, _tuning)
	assert_float(AimAssist.friction(on, 1.0, _tuning)).is_equal_approx(
		1.0 - _tuning.friction_max, 0.001
	)
	assert_float(AimAssist.friction({}, 1.0, _tuning)).is_equal(1.0)
	var half := AimAssist.friction(on, 0.5, _tuning)
	assert_float(half).is_greater(1.0 - _tuning.friction_max)
	assert_float(half).is_less(1.0)


func test_friction_grows_with_the_strength() -> void:
	var target := _zombie(8.0, 0.3)
	var level := (_chest(_zombie(8.0)) - EYE).normalized()
	var last := 1.0
	for strength in [0.25, 0.5, 0.75, 1.0]:
		var found := AimAssist.pick(EYE, level, [target], strength, _tuning)
		var factor := AimAssist.friction(found, strength, _tuning)
		assert_float(factor).is_less(last)
		last = factor


func test_the_pull_turns_toward_the_zombie_on_the_left_with_a_positive_yaw() -> void:
	var left := _zombie(8.0, -0.6)
	var found := AimAssist.pick(EYE, AHEAD, [left], 1.0, _tuning)
	var step := AimAssist.pull(EYE, AHEAD, found, 1.0, 0.0, 1.0 / 60.0, _tuning)
	# Yaw is positive to the left, the way the camera rig counts it.
	assert_float(step.x).is_greater(0.0)
	# The chest is below the lens: the view tips down a little.
	assert_float(step.y).is_less(0.0)


func test_the_pull_closes_the_angle_without_overshooting() -> void:
	var target := _zombie(8.0, -0.5)
	var yaw := 0.0
	var pitch := 0.0
	for _i in 600:
		var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		var found := AimAssist.pick(EYE, dir, [target], 1.0, _tuning)
		var step := AimAssist.pull(EYE, dir, found, 1.0, 0.0, 1.0 / 60.0, _tuning)
		yaw += step.x
		pitch += step.y
	var wanted := AimAssist.view_angles((_chest(target) - EYE).normalized())
	assert_float(yaw).is_equal_approx(wanted.x, 0.01)
	assert_float(pitch).is_equal_approx(wanted.y, 0.01)


func test_the_pull_never_turns_faster_than_its_cap() -> void:
	var target := _zombie(3.0, -1.0)
	var found := AimAssist.pick(EYE, AHEAD, [target], 1.0, _tuning)
	var delta := 1.0 / 60.0
	var step := AimAssist.pull(EYE, AHEAD, found, 1.0, 0.0, delta, _tuning)
	assert_float(step.length()).is_less_equal(_tuning.magnetism_max_rate * delta + 0.00001)


func test_a_quick_turn_by_the_player_switches_the_pull_off() -> void:
	var target := _zombie(8.0, -0.6)
	var found := AimAssist.pick(EYE, AHEAD, [target], 1.0, _tuning)
	var resting := AimAssist.pull(EYE, AHEAD, found, 1.0, 0.0, 1.0 / 60.0, _tuning)
	var flicking := AimAssist.pull(EYE, AHEAD, found, 1.0, _tuning.flick_speed, 1.0 / 60.0, _tuning)
	assert_float(resting.length()).is_greater(0.0)
	assert_float(flicking.length()).is_equal(0.0)


func test_no_strength_and_no_zombie_pull_nothing() -> void:
	assert_vector(AimAssist.pull(EYE, AHEAD, {}, 1.0, 0.0, 0.016, _tuning)).is_equal(Vector2.ZERO)
	var found := AimAssist.pick(EYE, AHEAD, [_zombie(8.0, -0.3)], 1.0, _tuning)
	assert_vector(AimAssist.pull(EYE, AHEAD, found, 0.0, 0.0, 0.016, _tuning)).is_equal(
		Vector2.ZERO
	)


func test_on_target_is_the_shots_own_test() -> void:
	var target := _zombie(8.0)
	var on := (_chest(target) - EYE).normalized()
	assert_bool(AimAssist.on_target(EYE, on, [target], 30.0)).is_true()
	# Two metres to the side is nowhere near a hit zone.
	var off := (_chest(_zombie(8.0, 2.0)) - EYE).normalized()
	assert_bool(AimAssist.on_target(EYE, off, [target], 30.0)).is_false()
	# Out of reach: the same ray, a shorter reach.
	assert_bool(AimAssist.on_target(EYE, on, [target], 5.0)).is_false()


func test_on_target_does_not_see_through_a_wall() -> void:
	var target := _zombie(8.0)
	var on := (_chest(target) - EYE).normalized()
	var wall := func(_from: Vector3, _to: Vector3) -> float: return 3.0
	assert_bool(AimAssist.on_target(EYE, on, [target], 30.0, wall)).is_false()


func test_the_view_angles_are_the_rigs_convention() -> void:
	var angles := AimAssist.view_angles(Vector3(-1.0, 0.0, -1.0).normalized())
	assert_float(angles.x).is_equal_approx(PI / 4.0, 0.001)
	assert_float(angles.y).is_equal_approx(0.0, 0.001)
	var up := AimAssist.view_angles(Vector3(0.0, 1.0, -1.0).normalized())
	assert_float(up.y).is_equal_approx(PI / 4.0, 0.001)


func test_the_simulators_accuracy_only_adds_and_never_passes_one() -> void:
	assert_float(AimAssist.assisted_accuracy(0.45, 0.0, _tuning)).is_equal(0.45)
	var weak := AimAssist.assisted_accuracy(0.45, 1.0, _tuning)
	assert_float(weak).is_greater(0.45)
	assert_float(weak).is_less(1.0)
	assert_float(AimAssist.assisted_accuracy(0.99, 1.0, _tuning)).is_less_equal(1.0)
	assert_float(AimAssist.assisted_accuracy(0.45, 0.5, _tuning)).is_less(weak)
