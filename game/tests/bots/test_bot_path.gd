# The bots' way over the mesh (bots plan, phase 2): a cached path with a look-ahead, at most three
# questions a second, a goal the mesh does not reach marked and not asked about again, and a door
# that drops the cache. Built on small meshes of squares (`NavArena`); no clock, `now` is a number
# the test counts.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0

var _arena: NavArena


func after_test() -> void:
	if _arena != null:
		_arena.dispose()
		_arena = null


## A room of ten by five squares with an island of ground that nothing joins at the east.
func _room_and_island() -> BotPath:
	var rows: Array[String] = [
		"##########  ##",
		"##########  ##",
		"##########  ##",
		"##########  ##",
		"##########  ##",
	]
	_arena = NavArena.from_rows(rows)
	await _arena.settle(get_tree())
	return BotPath.new(_arena.map)


## An L: the way from the west end to the north end bends round the corner at (6, 6).
func _l_shape() -> BotPath:
	var rows: Array[String] = [
		"      ####",
		"      ####",
		"      ####",
		"##########",
		"##########",
	]
	_arena = NavArena.from_rows(rows)
	await _arena.settle(get_tree())
	return BotPath.new(_arena.map)


func test_a_path_is_asked_for_once_and_followed_with_a_look_ahead() -> void:
	var path := await _room_and_island()
	var here := _arena.centre(0, 2)
	var goal := _arena.centre(8, 2)
	var status := path.ask(here, goal, 0.0)
	assert_int(status).is_equal(BotPath.Status.OK)
	assert_int(path.queries).is_equal(1)
	var direction := path.direction(here)
	assert_float(direction.x).is_greater(0.9)
	# 300 more asks at the same place and goal ask nothing more.
	for i in 300:
		path.ask(here, goal, float(i) * STEP)
	assert_int(path.queries).is_equal(1)
	# The point aimed at is more than the look-ahead away.
	assert_float(path.remaining(here)).is_equal_approx(here.distance_to(goal), 0.5)


func test_the_end_of_the_path_is_never_read_past() -> void:
	var path := await _room_and_island()
	var goal := _arena.centre(8, 2)
	path.ask(_arena.centre(7, 2), goal, 0.0)
	# At the goal and beside it: a direction that exists and is finite, or zero.
	for here in [goal, goal + Vector3(0.3, 0.0, 0.0), goal + Vector3(0.0, 0.0, -0.4)]:
		var direction := path.direction(here)
		assert_bool(direction.is_finite()).is_true()
		assert_float(direction.length()).is_less_equal(1.001)
	assert_bool(path.arrived(goal, 0.5)).is_true()


func test_a_goal_that_moves_every_tick_costs_three_questions_a_second() -> void:
	var path := await _room_and_island()
	var here := _arena.centre(0, 2)
	var seconds := 10.0
	var clock := 0.0
	var step := 0
	while clock < seconds:
		# The goal runs away at 8 m a second: more than the goal-moved distance each question.
		var goal := _arena.centre(2, 2) + Vector3(0.0, 0.0, sin(clock * 3.0) * 4.0)
		goal.x += fmod(clock * 8.0, 12.0)
		path.ask(here, goal, clock)
		clock += STEP
		step += 1
	assert_int(path.queries).is_less_equal(int(seconds * BotPath.QUERY_BUDGET) + 1)
	assert_int(path.queries).is_greater(int(seconds * BotPath.QUERY_BUDGET) - 3)


func test_a_goal_the_mesh_does_not_reach_is_marked_and_not_asked_again() -> void:
	var path := await _room_and_island()
	var here := _arena.centre(0, 2)
	var island := _arena.centre(12, 2)
	assert_int(path.ask(here, island, 0.0)).is_equal(BotPath.Status.UNREACHABLE)
	assert_int(path.unreachable_marks).is_equal(1)
	var asked := path.queries
	# Ask every tick for 4.9 seconds: no new question, no new mark.
	var clock := 0.0
	while clock < 4.9:
		clock += STEP
		assert_int(path.ask(here, island, clock)).is_equal(BotPath.Status.UNREACHABLE)
	assert_int(path.queries).is_equal(asked)
	assert_int(path.unreachable_marks).is_equal(1)
	# After the five seconds it is tried once more.
	path.ask(here, island, 5.2)
	assert_int(path.unreachable_marks).is_equal(2)


func test_a_goal_off_the_mesh_is_unreachable_without_a_path_question() -> void:
	var path := await _room_and_island()
	var here := _arena.centre(0, 2)
	var far_off := Vector3(40.0, 0.0, 2.0)
	assert_int(path.ask(here, far_off, 0.0)).is_equal(BotPath.Status.UNREACHABLE)
	assert_int(path.queries).is_equal(0)
	assert_int(path.empty_answers).is_equal(0)


func test_the_way_bends_round_a_corner_and_the_corner_is_not_cut() -> void:
	var path := await _l_shape()
	var here := _arena.centre(0, 3)
	var goal := _arena.centre(8, 0)
	assert_int(path.ask(here, goal, 0.0)).is_equal(BotPath.Status.OK)
	# Walk it as a body would: a step toward the direction; the whole way takes a bounded number of
	# steps and every position stays on the ground.
	var steps := 0
	while not path.arrived(here, 0.6) and steps < 1500:
		var direction := path.direction(here)
		assert_bool(direction.is_finite()).is_true()
		here += direction * 4.8 * STEP
		# Never farther off the ground than the corner rule lets it cut.
		var nearest := NavigationServer3D.map_get_closest_point(_arena.map, here)
		assert_float(Vector2(nearest.x - here.x, nearest.z - here.z).length()).is_less(0.3)
		steps += 1
	assert_bool(path.arrived(here, 0.6)).is_true()
	assert_int(steps).is_less(800)


func test_leaving_the_path_asks_for_a_new_one() -> void:
	var path := await _room_and_island()
	var goal := _arena.centre(8, 2)
	path.ask(_arena.centre(0, 2), goal, 0.0)
	assert_int(path.queries).is_equal(1)
	# Knocked 3 m off: more than the off-path distance. Not before the budget allows it.
	var knocked := _arena.centre(0, 2) + Vector3(0.0, 0.0, 4.0)
	path.ask(knocked, goal, 0.1)
	assert_int(path.queries).is_equal(1)
	path.ask(knocked, goal, 0.4)
	assert_int(path.queries).is_equal(2)


func test_a_door_drops_the_cache_and_holds_the_questions_until_the_mesh_is_in() -> void:
	var path := await _room_and_island()
	var here := _arena.centre(0, 2)
	var goal := _arena.centre(8, 2)
	path.note_doors(0, 0.0)
	path.ask(here, goal, 0.0)
	assert_int(path.queries).is_equal(1)
	# A door opened: nothing is asked for at least the hold, and the cache is gone.
	path.note_doors(1, 1.0)
	assert_bool(path.points.is_empty()).is_true()
	assert_int(path.door_drops).is_equal(1)
	assert_int(path.ask(here, goal, 1.05)).is_equal(BotPath.Status.HOLD)
	assert_int(path.queries).is_equal(1)
	# The map takes a new mesh in (its iteration moves) and the hold is over.
	var before := NavigationServer3D.map_get_iteration_id(_arena.map)
	_arena.swap_in()
	for _i in 30:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(_arena.map) != before:
			break
	assert_int(NavigationServer3D.map_get_iteration_id(_arena.map)).is_not_equal(before)
	assert_int(path.ask(here, goal, 1.3)).is_equal(BotPath.Status.OK)
	assert_int(path.queries).is_equal(2)


func test_the_hold_ends_by_itself_when_the_map_never_moves() -> void:
	var path := await _room_and_island()
	path.note_doors(0, 0.0)
	path.note_doors(1, 1.0)
	assert_bool(path.holding(1.5)).is_true()
	assert_bool(path.holding(1.0 + BotPath.DOOR_HOLD_MAX + 0.1)).is_false()


func test_a_door_forgets_what_was_unreachable() -> void:
	var path := await _room_and_island()
	var here := _arena.centre(0, 2)
	var island := _arena.centre(12, 2)
	path.note_doors(0, 0.0)
	path.ask(here, island, 0.0)
	assert_bool(path.is_blocked(island, 0.5)).is_true()
	path.note_doors(1, 1.0)
	assert_bool(path.is_blocked(island, 1.0)).is_false()


func test_with_no_map_the_way_is_the_straight_line() -> void:
	var path := BotPath.new(RID())
	var here := Vector3.ZERO
	var goal := Vector3(10.0, 0.0, 0.0)
	assert_int(path.ask(here, goal, 0.0)).is_equal(BotPath.Status.OK)
	assert_float(path.direction(here).x).is_equal_approx(1.0, 0.001)
	assert_int(path.queries).is_equal(0)


## A path of three legs along x, 4 m each, and a level whose `walk` finds a wall across x = `wall_x`
## (as a ray along the way would: the distance to it, or -1.0 when it is not on the segment).
func _walled_way(wall_x: float) -> Array:
	var level := BotLevel.new()
	level.walk = func(from: Vector3, to: Vector3) -> float:
		var low := minf(from.x, to.x)
		var high := maxf(from.x, to.x)
		return absf(wall_x - from.x) if wall_x >= low and wall_x <= high else -1.0
	var way := PackedVector3Array(
		[Vector3.ZERO, Vector3(4.0, 0.0, 0.0), Vector3(8.0, 0.0, 0.0), Vector3(12.0, 0.0, 0.0)]
	)
	return [BotPath.new(RID(), level), way]


func test_a_path_through_a_wall_with_more_than_a_metre_past_it_is_not_walkable() -> void:
	var made := _walled_way(5.0)
	var way: PackedVector3Array = (made[0] as BotPath).walkable(made[1])
	assert_bool(way.is_empty()).is_true()


func test_a_path_stopped_by_a_wall_at_its_end_is_cut_short_of_it() -> void:
	var made := _walled_way(11.5)
	var way: PackedVector3Array = (made[0] as BotPath).walkable(made[1])
	assert_int(way.size()).is_equal(4)
	assert_float(way[way.size() - 1].x).is_equal_approx(11.5 - BotPath.BODY_STANDOFF, 0.001)


func test_a_path_with_nothing_in_the_way_is_walkable_as_it_is() -> void:
	var made := _walled_way(20.0)
	var way: PackedVector3Array = (made[0] as BotPath).walkable(made[1])
	assert_int(way.size()).is_equal(4)
	assert_float(way[3].x).is_equal_approx(12.0, 0.001)


func test_a_level_that_does_not_check_walks_lets_every_path_through() -> void:
	var path := BotPath.new(RID(), BotLevel.new())
	var way := PackedVector3Array([Vector3.ZERO, Vector3(4.0, 0.0, 0.0)])
	assert_int(path.walkable(way).size()).is_equal(2)
