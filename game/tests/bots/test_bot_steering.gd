# The heading scorer (bots plan, phase 2): a reflex picks among twelve headings, rates them by the
# distance gained from the dead, the way to the goal, the room ahead, the light and the last
# choice, and the end of the heading it takes is on the walking mesh. The meshes are small
# (`NavArena`); a ray treats everything off the ground as wall.
extends GdUnitTestSuite

var _arena: NavArena


func after_test() -> void:
	if _arena != null:
		_arena.dispose()
		_arena = null


## A hall six squares wide and six deep: 12 m by 12 m of open ground.
func _hall() -> BotLevel:
	var rows: Array[String] = ["######", "######", "######", "######", "######", "######"]
	_arena = NavArena.from_rows(rows)
	await _arena.settle(get_tree())
	return _arena.level()


func _threat(at: Vector3, speed := 2.0) -> Array[Dictionary]:
	return [{"position": at, "speed": speed}]


func test_it_runs_from_the_dead_not_toward_them() -> void:
	var level := await _hall()
	var steering := BotSteering.new(level)
	var here := _arena.centre(3, 3)
	for angle in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]:
		var from := here + Vector3(-sin(angle), 0.0, -cos(angle)) * 4.0
		var heading := steering.pick(here, _threat(from), Vector3.ZERO, Vector3.ZERO)
		assert_bool(heading != Vector3.ZERO).is_true()
		var away := (here - from).normalized()
		# Within 60 degrees of straight away, though the walls pull it round the room.
		assert_float(heading.dot(away)).is_greater(0.5)


func test_a_heading_toward_a_point_to_keep_out_of_is_no_way_out() -> void:
	# The dead come from the south and a live grenade lies 5 m north (#872): straight away from the
	# dead is straight at the blast. With the point kept out of, the heading takes the bot no nearer
	# to it; without, it runs at it.
	var level := await _hall()
	var steering := BotSteering.new(level)
	var here := _arena.centre(3, 3)
	var blast := here + Vector3(0.0, 0.0, -5.0)
	var dead := _threat(here + Vector3(0.0, 0.0, 2.0), 6.0)
	var free := steering.pick(here, dead, Vector3.ZERO, Vector3.ZERO)
	assert_float(free.dot(Vector3(0.0, 0.0, -1.0))).is_greater(0.5)
	steering.keep_out = [blast]
	steering.keep_out_reach = 8.0
	for _i in 3:
		var kept := steering.pick(here, dead, Vector3.ZERO, Vector3.ZERO)
		if kept != Vector3.ZERO:
			var end := here + kept * BotSteering.STEP
			var before := Vector2(here.x - blast.x, here.z - blast.z).length()
			assert_float(Vector2(end.x - blast.x, end.z - blast.z).length()).is_greater_equal(
				before
			)


func test_a_wall_behind_the_bot_bends_the_escape_along_it() -> void:
	var level := await _hall()
	var steering := BotSteering.new(level)
	# In the south-west corner with the dead coming from the north-east: straight away is the
	# corner; the way out is along a wall, north or east of it, and never into the walls.
	var here := _arena.centre(0, 5)
	var heading := steering.pick(
		here, _threat(here + Vector3(5.0, 0.0, -5.0)), Vector3.ZERO, Vector3.ZERO
	)
	assert_bool(heading != Vector3.ZERO).is_true()
	var open := level.room(here, heading, BotSteering.ROOM_LIMIT)
	assert_float(open).is_greater_equal(BotSteering.WALL_STOP)


func test_a_dead_end_with_the_dead_in_it_is_boxed_in() -> void:
	var rows: Array[String] = ["###"]
	_arena = NavArena.from_rows(rows)
	await _arena.settle(get_tree())
	var level := _arena.level()
	var steering := BotSteering.new(level)
	# A corridor one square wide and three long: the bot at its west end, the dead in the middle.
	var here := _arena.centre(0, 0)
	var heading := steering.pick(here, _threat(_arena.centre(1, 0)), Vector3.ZERO, Vector3.ZERO)
	assert_vector(heading).is_equal(Vector3.ZERO)


func test_a_heading_that_leaves_the_mesh_is_never_chosen() -> void:
	# No walls to a ray (the level has no sight), a mesh that stops at the edge of a ledge: only the
	# projection keeps the bot on the ground. Whatever the dead do, the end is on the mesh.
	var level := await _hall()
	level.sight = Callable()
	var steering := BotSteering.new(level)
	var dice := RandomNumberGenerator.new()
	dice.seed = 11
	var chosen := 0
	for _i in 200:
		var here := Vector3(dice.randf_range(0.5, 11.5), 0.0, dice.randf_range(0.5, 11.5))
		var from := here + Vector3(dice.randf_range(-5, 5), 0.0, dice.randf_range(-5, 5))
		var heading := steering.pick(here, _threat(from), Vector3.ZERO, Vector3.ZERO)
		if heading == Vector3.ZERO:
			continue
		chosen += 1
		var end := here + heading * BotSteering.STEP
		var on_mesh := NavigationServer3D.map_get_closest_point(_arena.map, end)
		assert_float(Vector2(on_mesh.x - end.x, on_mesh.z - end.z).length()).is_less_equal(
			BotSteering.OFF_MESH + 0.001
		)
	assert_int(chosen).is_greater(150)


func test_the_ledge_stops_a_reflex_at_the_edge_of_the_mesh() -> void:
	var level := await _hall()
	level.sight = Callable()
	var steering := BotSteering.new(level)
	# At the north edge with the dead to the south: straight away is off the ledge.
	var here := Vector3(6.0, 0.0, 0.5)
	var heading := steering.pick(
		here, _threat(here + Vector3(0.0, 0.0, 4.0)), Vector3.ZERO, Vector3.ZERO
	)
	assert_bool(heading != Vector3.ZERO).is_true()
	# Not north: that is off the mesh.
	assert_float(heading.z).is_greater(-0.4)


func test_the_goal_pulls_among_headings_that_are_equally_safe() -> void:
	var level := await _hall()
	var steering := BotSteering.new(level)
	var here := _arena.centre(3, 3)
	var from := here + Vector3(0.0, 0.0, 6.0)
	var east := Vector3(1.0, 0.0, 0.0)
	var west := Vector3(-1.0, 0.0, 0.0)
	var to_east := steering.pick(here, _threat(from), east, Vector3.ZERO)
	var to_west := steering.pick(here, _threat(from), west, Vector3.ZERO)
	assert_float(to_east.x).is_greater(0.2)
	assert_float(to_west.x).is_less(-0.2)


func test_the_last_choice_is_kept_when_two_are_close() -> void:
	var level := await _hall()
	var steering := BotSteering.new(level)
	var here := _arena.centre(3, 3)
	var from := here + Vector3(0.0, 0.0, 4.0)
	# Dead south: north-east and north-west are the same to the scorer. Whichever was taken last is
	# taken again.
	var first := steering.pick(
		here, _threat(from), Vector3.ZERO, Vector3(0.5, 0.0, -0.87).normalized()
	)
	var second := steering.pick(
		here, _threat(from), Vector3.ZERO, Vector3(-0.5, 0.0, -0.87).normalized()
	)
	assert_float(first.x).is_greater(0.0)
	assert_float(second.x).is_less(0.0)


func test_a_faster_dead_weighs_more_than_a_slower_one() -> void:
	var level := await _hall()
	var steering := BotSteering.new(level)
	var here := _arena.centre(3, 3)
	# A walker to the west and a runner to the east at the same distance: the escape leans away
	# from the runner, to the west.
	var threats: Array[Dictionary] = [
		{"position": here + Vector3(-5.0, 0.0, 0.0), "speed": 1.4},
		{"position": here + Vector3(5.0, 0.0, 0.0), "speed": 5.0},
	]
	var heading := steering.pick(here, threats, Vector3.ZERO, Vector3.ZERO)
	assert_float(heading.x).is_less(0.0)


func test_a_loop_pulls_a_kite_round_it() -> void:
	var level := await _hall()
	# A ring of 8 m round the middle of the hall: closed, in order.
	var middle := _arena.centre(3, 3)
	var ring := PackedVector3Array()
	for i in 12:
		var angle := TAU * float(i) / 12.0
		ring.append(middle + Vector3(cos(angle), 0.0, sin(angle)) * 3.0)
	level.loops = [ring]
	var steering := BotSteering.new(level)
	var here := middle + Vector3(3.0, 0.0, 0.0)
	# The dead dead ahead to the east of the ring's edge: with the pull, the heading follows the
	# ring's tangent (north or south), not straight back into the hall.
	var from := here + Vector3(3.0, 0.0, 0.0)
	var with := steering.pick(here, _threat(from), Vector3.ZERO, Vector3.ZERO)
	assert_float(absf(with.z)).is_greater(0.4)


func _pack_between(here: Vector3, person: Vector3) -> Array[Dictionary]:
	# Eight dead running at the bot from the side of the person, three to four metres off.
	var toward := (person - here).normalized()
	var side := Vector3(-toward.z, 0.0, toward.x)
	var pack: Array[Dictionary] = []
	for i in 8:
		var offset := side * (float(i) - 3.5) * 0.7 + toward * (3.0 + float(i % 2))
		pack.append({"position": here + offset, "speed": 4.0})
	return pack


func test_a_far_pull_turns_the_flight_round_a_pack_toward_the_person() -> void:
	var level := await _hall()
	var steering := BotSteering.new(level)
	var here := _arena.centre(3, 3)
	# The person is to the north, past the pack: away from the pack is south.
	var person := here + Vector3(0.0, 0.0, -30.0)
	var pack := _pack_between(here, person)
	var toward := (person - here).normalized()
	var near := steering.pick(here, pack, toward * BotRetreat.far_bend(10.0, 8), Vector3.ZERO)
	var far := steering.pick(here, pack, toward * BotRetreat.far_bend(40.0, 8), Vector3.ZERO)
	assert_bool(near != Vector3.ZERO and far != Vector3.ZERO).is_true()
	# The weak pull of a bot beside the person runs straight away; the far one bends it round
	# (more of the way to the person) and still never closes on the pack.
	assert_float(far.dot(toward)).is_greater(near.dot(toward) + 0.4)
	var gain := 0.0
	for threat in pack:
		var at: Vector3 = threat["position"]
		gain += (here + far * 2.5 - at).length() - (here - at).length()
	assert_float(gain).is_greater(-BotSteering.BOXED_IN)


func test_the_retreat_bend_grows_with_the_distance_from_the_person() -> void:
	assert_float(BotRetreat.far_bend(5.0, 8)).is_equal(BotRetreat.HOME_BEND)
	assert_float(BotRetreat.far_bend(BotRetreat.FAR_BEND_FROM, 8)).is_equal(BotRetreat.HOME_BEND)
	assert_float(BotRetreat.far_bend(BotRetreat.FAR_BEND_FULL + 30.0, 8)).is_equal(
		BotRetreat.FAR_BEND * 8.0
	)
	# One dead (or none) pulls by `FAR_BEND`, and between the two distances the pull is between.
	assert_float(BotRetreat.far_bend(100.0, 0)).is_equal(BotRetreat.FAR_BEND)
	assert_float(BotRetreat.far_bend(26.0, 4)).is_between(
		BotRetreat.HOME_BEND, BotRetreat.FAR_BEND * 4.0
	)
