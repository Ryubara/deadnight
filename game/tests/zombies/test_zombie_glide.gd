extends GdUnitTestSuite
## A client of a server is sent the zombies every second physics tick (30 Hz); a view that jumped to
## each entry stood still every other tick (issue #105). It walks to each entry over the ticks
## since the last one, one entry behind.


func _view() -> ZombieView:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(), 1, 0.25, 0.7)
	return view


func _entry(x: float, yaw: float = 0.0) -> Dictionary:
	return {
		"id": 1,
		"position": Vector3(x, 0, 0),
		"yaw": yaw,
		"mode": ZombieBody.Mode.CHASE,
		"episode": 1,
		"speed": 3.0,
	}


## Where the view stands after each physics tick of a run that feeds it an entry every `every`th
## tick, the zombie walking 0.05 m a tick.
func _run(view: ZombieView, ticks: int, every: int) -> Array[float]:
	var seen: Array[float] = []
	var x := 0.0
	for tick in ticks:
		await get_tree().physics_frame
		seen.append(view.position.x)
		if tick % every == 0:
			x += 0.05 * every
			view.apply(_entry(x), 1.0 / 60.0)
	return seen


func _steps(seen: Array[float]) -> Array[float]:
	var steps: Array[float] = []
	for i in range(1, seen.size()):
		steps.append(seen[i] - seen[i - 1])
	return steps


func test_a_view_fed_every_tick_is_set_at_once_as_before() -> void:
	var view := _view()
	view.apply(_entry(1.0, 0.5), 1.0 / 60.0)
	assert_vector(view.position).is_equal(Vector3(1, 0, 0))
	var seen := await _run(view, 12, 1)
	for step in _steps(seen).slice(3):
		assert_float(step).is_equal_approx(0.05, 0.001)


func test_a_view_fed_every_second_tick_moves_as_evenly_as_one_fed_every_tick() -> void:
	var view := _view()
	var seen := await _run(view, 40, 2)
	var steps := _steps(seen).slice(6)
	var most := 0.0
	var least := 1.0
	for step in steps:
		most = maxf(most, step)
		least = minf(least, step)
	# Jumping to each entry this was 0 and 0.1 in turn.
	assert_float(least).is_greater(0.045)
	assert_float(most).is_less(0.055)


func test_the_glide_ends_on_the_entry_and_is_never_more_than_an_entry_behind() -> void:
	var view := _view()
	var seen := await _run(view, 30, 2)
	var newest := 0.05 * 2 * 15  # the last entry sent, at tick 28
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_float(view.position.x).is_equal_approx(newest, 0.001)
	# Mid-run the view trailed the newest entry by less than two entries.
	assert_float(newest - 0.1 - seen[seen.size() - 1]).is_less(0.1)


func test_the_yaw_turns_with_the_walk_the_short_way_round() -> void:
	var view := _view()
	view.apply(_entry(0.0, 3.0), 1.0 / 60.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	view.apply(_entry(0.1, -3.0), 1.0 / 60.0)
	await get_tree().physics_frame
	# Half way from 3.0 to -3.0 across pi is near pi, not near 0.
	assert_float(absf(view.rotation.y)).is_greater(2.8)


func test_a_jump_a_stall_or_a_new_life_is_set_down_at_once() -> void:
	var view := _view()
	view.apply(_entry(0.0), 1.0 / 60.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	view.apply(_entry(30.0), 1.0 / 60.0)
	assert_float(view.position.x).is_equal(30.0)
	for _i in ZombieView.GLIDE_MAX_TICKS + 2:
		await get_tree().physics_frame
	view.apply(_entry(30.1), 1.0 / 60.0)
	assert_float(view.position.x).is_equal_approx(30.1, 0.001)
	# A parked body starts its next life where its first entry says.
	view.park()
	view.setup(ZombieModels.scene(), 2, 0.0, 0.7)
	await get_tree().physics_frame
	await get_tree().physics_frame
	view.apply(_entry(2.0), 1.0 / 60.0)
	assert_float(view.position.x).is_equal(2.0)
