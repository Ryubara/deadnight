# Where a bot fires its flare (bots plan, phase 5; #646): a pure function of positions, pinned one
# case at a time on open ground and with a wall. The spot is far from the body, never within 4 m
# of a teammate, within the lure's reach of every zombie to be drawn, off the bot's side of the
# body, and reachable by a real flight of the real projectile.
extends GdUnitTestSuite

const HERE := Vector3(0.0, 0.0, 10.0)
const BODY := Vector3(-14.0, 0.0, 0.0)
## A wall along the plane x = WALL_X (the world answer of `_world`), when a test wants one.
const WALL_X := 4.0
const SEEDS := 300

var _wall := false
var _flare := BotFlare.new()


## The world of a test: the ground at y = 0 and, when `_wall` is set, a wall at x = WALL_X.
func _world(from: Vector3, to: Vector3) -> float:
	var best := -1.0
	var length := from.distance_to(to)
	if from.y >= 0.0 and to.y < 0.0:
		best = length * from.y / (from.y - to.y)
	if _wall and (from.x - WALL_X) * (to.x - WALL_X) < 0.0:
		var hit := length * (WALL_X - from.x) / (to.x - from.x)
		best = hit if best < 0.0 else minf(best, hit)
	return best


func _level() -> BotLevel:
	return BotLevel.new(Callable(self, &"_world"))


## `count` zombies about `centre`, 2.5 to 4.5 m out.
func _pack(centre: Vector3, count: int) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for i in count:
		var around := TAU * float(i) / float(count)
		found.append(centre + Vector3(sin(around), 0.0, cos(around)) * (2.5 + float(i % 3)))
	return found


func _mate(at: Vector3) -> Dictionary:
	return {"pos": at, "velocity": Vector3.ZERO, "dead": false}


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_the_table_of_flights_rises_with_the_pitch_and_answers_the_distances_it_covers() -> void:
	var table := _flare.landings()
	assert_int(table.size()).is_greater(20)
	for i in range(1, table.size()):
		assert_float(table[i].y).is_greater(table[i - 1].y)
		assert_float(table[i].x).is_greater(table[i - 1].x)
	for distance in [10.0, 15.0, 20.0, 26.0]:
		var pitch := _flare.pitch_for(distance)
		assert_bool(is_nan(pitch)).is_false()
		var end := _flare.fly(Vector3.ZERO, 0.0, pitch, Callable(self, &"_world"))
		assert_float(Vector2(end.x, end.z).length()).is_equal_approx(distance, 0.3)
	assert_bool(is_nan(_flare.pitch_for(1.0))).is_true()
	assert_bool(is_nan(_flare.pitch_for(500.0))).is_true()


func test_on_open_ground_the_flare_lands_where_it_was_aimed_far_from_the_body_and_the_players(
) -> void:
	var lured := _pack(BODY, 6)
	var mates: Array[Dictionary] = [_mate(BODY), _mate(Vector3(10.0, 0.0, 14.0))]
	var shot := _flare.plan(HERE, BODY, lured, mates, _level())
	assert_object(shot).is_not_null()
	assert_float(_flat(shot.landing, shot.spot)).is_less(BotFlare.TOLERANCE)
	assert_float(_flat(shot.spot, BODY)).is_greater_equal(BotFlare.MIN_FROM_BODY)
	assert_float(_flat(shot.landing, BODY)).is_greater_equal(BotFlare.LANDED_FROM_BODY)
	for mate in mates:
		assert_float(_flat(shot.landing, mate["pos"])).is_greater(4.0)
	for at in lured:
		assert_float(_flat(at, shot.landing)).is_less_equal(25.0)
	# The shot is the flight it says: flown again from the bot, it ends there.
	var end := _flare.fly(HERE, shot.yaw, shot.pitch, Callable(self, &"_world"))
	assert_float(_flat(end, shot.landing)).is_less(0.01)


func test_over_seeded_nights_no_flare_lands_within_4_m_of_a_teammate_or_the_body() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 646
	var shots := 0
	for _seed in SEEDS:
		var here := Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-20.0, 20.0))
		var body := Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-20.0, 20.0))
		var lured := _pack(body, rng.randi_range(2, 10))
		var mates: Array[Dictionary] = []
		for _i in rng.randi_range(1, 4):
			var at := Vector3(rng.randf_range(-30.0, 30.0), 0.0, rng.randf_range(-30.0, 30.0))
			mates.append(_mate(at))
		var shot := _flare.plan(here, body, lured, mates, _level())
		if shot == null:
			continue
		shots += 1
		assert_float(_flat(shot.landing, body)).is_greater_equal(BotFlare.LANDED_FROM_BODY)
		for mate in mates:
			assert_float(_flat(shot.landing, mate["pos"])).is_greater_equal(4.0)
	# The rule is not a rule that never fires.
	assert_int(shots).is_greater(SEEDS / 3)


func test_with_a_player_standing_at_every_spot_there_is_no_shot() -> void:
	var lured := _pack(BODY, 6)
	var mates: Array[Dictionary] = []
	for heading in BotFlare.HEADINGS:
		var around := TAU * float(heading) / float(BotFlare.HEADINGS)
		for ring in BotFlare.RINGS:
			mates.append(_mate(HERE + Vector3(sin(around), 0.0, cos(around)) * ring))
	assert_object(_flare.plan(HERE, BODY, lured, mates, _level())).is_null()


func test_dead_that_no_spot_is_within_the_lures_reach_of_are_not_drawn() -> void:
	var lured: Array[Vector3] = [BODY, BODY + Vector3(0.0, 0.0, 60.0)]
	assert_object(_flare.plan(HERE, BODY, lured, [], _level())).is_null()


func test_a_spot_on_the_bots_side_of_the_body_is_not_off_the_line_to_the_reviver() -> void:
	var lured := _pack(BODY, 4)
	var spot := BODY + Vector3(13.0, 0.0, 0.0)
	# The same spot, the bot east of the body (its side) or south of it (a quarter turn off).
	var east := BODY + Vector3(24.0, 0.0, 0.0)
	var south := BODY + Vector3(0.0, 0.0, -11.0)
	assert_bool(_flare.is_fit(spot, east, BODY, lured, [])).is_false()
	assert_bool(_flare.is_fit(spot, south, BODY, lured, [])).is_true()


func test_the_dead_are_not_drawn_past_the_bot_that_fires() -> void:
	# The bot stands at the body, so it has no side; a zombie west of it would walk past it to a
	# spot in the east, and not to one in the north.
	var lured: Array[Vector3] = [Vector3(-10.0, 0.0, 0.0)]
	(
		assert_bool(_flare.is_fit(Vector3(14.0, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO, lured, []))
		. is_false()
	)
	(
		assert_bool(_flare.is_fit(Vector3(0.0, 0.0, 14.0), Vector3.ZERO, Vector3.ZERO, lured, []))
		. is_true()
	)


func test_a_spot_nearer_than_twelve_metres_to_the_body_is_not_fit() -> void:
	var lured := _pack(BODY, 4)
	var near := BODY + Vector3(0.0, 0.0, -11.0)
	assert_bool(_flare.is_fit(near, HERE, BODY, lured, [])).is_false()


func test_a_wall_in_the_way_gives_the_shot_up() -> void:
	# The body is south of the bot, a player stands at the one spot in the west: the only way is
	# east, across the plane x = 4. Without the wall the flare is fired there; with it, not at all.
	var body := Vector3(0.0, 0.0, -14.0)
	var here := Vector3(0.0, 0.0, 6.0)
	var lured := _pack(body, 4)
	var mates: Array[Dictionary] = [_mate(Vector3(-13.0, 0.0, -8.0))]
	var open := _flare.plan(here, body, lured, mates, _level())
	assert_object(open).is_not_null()
	assert_float(open.landing.x).is_greater(WALL_X)
	_wall = true
	var shut := _flare.plan(here, body, lured, mates, _level())
	_wall = false
	assert_object(shut).is_null()
