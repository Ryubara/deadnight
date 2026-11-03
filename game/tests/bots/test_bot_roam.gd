# Where a roaming bot goes (bots plan, orders): a place across the lot, looked about from, then
# another. Pure rules on plain data, a level with a few places and no walking mesh.
extends GdUnitTestSuite

const HERE := Vector3.ZERO
const FAR := Vector3(0.0, 0.0, -20.0)
const OTHER := Vector3(25.0, 0.0, 0.0)


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
