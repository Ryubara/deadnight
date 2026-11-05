# Where a roaming bot goes (bots plan, orders): a place across the lot, looked about from, then
# another. Pure rules on plain data, a level with a few places and no walking mesh.
extends GdUnitTestSuite

const HERE := Vector3.ZERO
const FAR := Vector3(0.0, 0.0, -20.0)
const OTHER := Vector3(25.0, 0.0, 0.0)
## A point of the mesh that is a piece of its own (#1041).
const CUT_OFF := Vector3(-3.0, 0.0, 0.0)


func _roam() -> BotRoam:
	var level := BotLevel.new()
	level.roam_spots = [FAR, OTHER]
	return BotRoam.new(level, 1)


func _plan(roam: BotRoam, here: Vector3, now: float, stopped_short_of := Vector3.INF) -> Vector3:
	var none: Array[Vector3] = []
	return roam.plan(here, now, none, none, none, none, Callable(), Callable(), 0, stopped_short_of)


func test_a_bot_two_metres_short_of_its_place_with_no_path_left_counts_itself_there() -> void:
	# The mesh ended 2 m short of the place, past the 1.5 m a bot counts itself arrived within: the
	# legs stood at the end of the path, and the place was kept for ever (a Roam bot 92 s idle in
	# the soak).
	var roam := _roam()
	var spot := _plan(roam, HERE, 0.0)
	assert_bool(spot.is_finite()).is_true()
	var short := spot + Vector3(2.0, 0.0, 0.0)
	assert_vector(_plan(roam, short, 1.0)).is_equal(spot)
	assert_bool(roam.dwelling).is_false()
	assert_vector(_plan(roam, short, 2.0, spot)).is_equal(Vector3.INF)
	assert_bool(roam.dwelling).is_true()
	assert_bool(roam.visited.has(spot)).is_true()


func test_the_legs_stopping_short_of_another_place_does_not_end_this_one() -> void:
	var roam := _roam()
	var spot := _plan(roam, HERE, 0.0)
	var elsewhere := spot + Vector3(9.0, 0.0, 0.0)
	assert_vector(_plan(roam, spot + Vector3(2.0, 0.0, 0.0), 1.0, elsewhere)).is_equal(spot)
	assert_bool(roam.dwelling).is_false()


func test_after_looking_about_the_bot_chooses_another_place() -> void:
	var roam := _roam()
	var spot := _plan(roam, HERE, 0.0)
	var short := spot + Vector3(2.0, 0.0, 0.0)
	assert_vector(_plan(roam, short, 1.0, spot)).is_equal(Vector3.INF)
	var later := _plan(roam, short, 1.0 + BotRoam.DWELL.y + 0.1)
	assert_bool(later.is_finite()).is_true()


# --- A bot cut off from the rest of the mesh (#1041) ---


## A walking mesh in which the point `CUT_OFF` is a piece of its own: a path from there reaches
## nothing, a path from anywhere else reaches every place. `blocked` is what the legs say of the
## place the bot was walking to.
func _mesh_with_a_piece(cut: Dictionary) -> Array[Callable]:
	var reach := func(here: Vector3, _spot: Vector3) -> bool: return not cut["on_it"]
	var blocked := func(_spot: Vector3) -> bool: return cut["on_it"]
	return [reach, blocked]


func _plan_on_mesh(roam: BotRoam, here: Vector3, now: float, mesh: Array[Callable]) -> Vector3:
	var none: Array[Vector3] = []
	roam.exact = mesh[0]
	return roam.plan(here, now, none, none, none, none, mesh[1], mesh[0])


func test_a_bot_cut_off_from_the_mesh_walks_back_and_keeps_its_places() -> void:
	var roam := _roam()
	var cut := {"on_it": false}
	var mesh := _mesh_with_a_piece(cut)
	var spot := _plan_on_mesh(roam, HERE, 0.0, mesh)
	assert_bool(spot.is_finite()).is_true()
	# Set down on the piece a few metres off, every place is refused for as long as it stays: the
	# walk back to the spot it chose from is the way out (no path starts on the piece).
	cut["on_it"] = true
	var now := 1.0
	for _think in 6:
		assert_vector(_plan_on_mesh(roam, CUT_OFF, now, mesh)).is_equal(Vector3.INF)
		assert_vector(roam.rejoin).is_equal(HERE)
		now += 0.3
	assert_int(roam.strandings).is_equal(1)
	# Back on the mesh the places the piece refused are not banned: it goes to one of the level's
	# places again (a ban of ten minutes on all of them left a bot standing for good).
	cut["on_it"] = false
	var again := _plan_on_mesh(roam, HERE + Vector3(0.2, 0.0, 0.0), now, mesh)
	assert_bool(roam.rejoin.is_finite()).is_false()
	assert_bool([FAR, OTHER].has(again)).is_true()


func test_a_bot_whose_places_are_all_behind_doors_is_not_cut_off() -> void:
	# The spot the bot chose from is as unreachable as the places: nothing says it is cut off, so
	# nothing changes (the places are banned until a door opens, and the ring about it is tried).
	var roam := _roam()
	var none: Array[Vector3] = []
	var reach := func(_here: Vector3, _spot: Vector3) -> bool: return false
	var blocked := func(_spot: Vector3) -> bool: return false
	roam.exact = reach
	roam.plan(HERE, 0.0, none, none, none, none, blocked)
	for _think in 4:
		roam.plan(HERE + Vector3(2.0, 0.0, 0.0), 1.0, none, none, none, none, blocked, reach, 0)
	assert_bool(roam.rejoin.is_finite()).is_false()
	assert_int(roam.strandings).is_equal(0)


func test_the_walk_back_ends_when_the_bot_is_on_the_mesh_or_has_had_its_time() -> void:
	var roam := _roam()
	var cut := {"on_it": false}
	var mesh := _mesh_with_a_piece(cut)
	_plan_on_mesh(roam, HERE, 0.0, mesh)
	cut["on_it"] = true
	_plan_on_mesh(roam, CUT_OFF, 1.0, mesh)
	assert_bool(roam.rejoin.is_finite()).is_true()
	# Still on the piece when the time is up: the bot goes back to choosing (and banning).
	_plan_on_mesh(roam, CUT_OFF, 1.0 + BotRoam.REJOIN_SECONDS + 0.1, mesh)
	assert_bool(roam.rejoin.is_finite()).is_false()
