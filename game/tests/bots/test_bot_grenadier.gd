# When and where a bot throws its grenade (bots plan, phase 3): a pack it would take, a throw it
# aims with the real arc's help, and the rule that no blast is ever put where it reaches the bot.
extends GdUnitTestSuite

const STEP := 1.0 / 60.0
const HERE := Vector3.ZERO


func _level() -> BotLevel:
	return BotLevel.new()


## A zombie standing (or walking at `velocity`) at `at`.
func _zombie(id: int, at: Vector3, velocity := Vector3.ZERO) -> Dictionary:
	return {"id": id, "position": at, "velocity": velocity, "mode": ZombieBody.Mode.CHASE}


## The flat ground at the feet as a grenade's world: the first thing a segment going down meets.
static func _ground(from: Vector3, to: Vector3) -> Dictionary:
	if from.y < 0.0 or to.y >= 0.0:
		return {}
	var along := from.y / (from.y - to.y)
	return {"distance": from.distance_to(to) * along, "normal": Vector3.UP}


func _pack(at: Vector3, count := 4) -> Array[Dictionary]:
	var pack: Array[Dictionary] = []
	for i in count:
		pack.append(_zombie(i + 1, at + Vector3(float(i % 2) * 1.2, 0.0, float(i / 2) * 1.2)))
	return pack


func test_a_pack_in_the_open_gets_a_throw_and_a_lone_zombie_does_not() -> void:
	var grenadier := BotGrenadier.new(_level())
	var throw := grenadier.plan(HERE, _pack(Vector3(0, 0, -10)), 2, 0.0)
	assert_object(throw).is_not_null()
	assert_int(throw.pack).is_equal(4)
	assert_float(throw.yaw).is_equal_approx(0.0, 0.2)
	var lone: Array[Dictionary] = [_zombie(1, Vector3(0, 0, -10))]
	assert_object(grenadier.plan(HERE, lone, 2, 0.0)).is_null()


func test_no_throw_without_a_grenade_and_not_again_inside_the_cooldown() -> void:
	var grenadier := BotGrenadier.new(_level())
	assert_object(grenadier.plan(HERE, _pack(Vector3(0, 0, -10)), 0, 0.0)).is_null()
	assert_object(grenadier.plan(HERE, _pack(Vector3(0, 0, -10)), 1, 0.0)).is_not_null()
	grenadier.last_throw = 0.0
	assert_object(grenadier.plan(HERE, _pack(Vector3(0, 0, -10)), 1, 3.0)).is_null()
	var later := BotGrenadier.COOLDOWN + 0.1
	assert_object(grenadier.plan(HERE, _pack(Vector3(0, 0, -10)), 1, later)).is_not_null()


func test_a_pack_too_near_the_bot_or_too_far_is_left_alone() -> void:
	var grenadier := BotGrenadier.new(_level())
	assert_object(grenadier.plan(HERE, _pack(Vector3(0, 0, -3)), 2, 0.0)).is_null()
	assert_object(grenadier.plan(HERE, _pack(Vector3(0, 0, -30)), 2, 0.0)).is_null()


func test_crawlers_count_from_a_smaller_pack() -> void:
	var grenadier := BotGrenadier.new(_level())
	var two := _pack(Vector3(0, 0, -10), 2)
	assert_object(grenadier.plan(HERE, two, 2, 0.0)).is_null()
	assert_object(grenadier.plan(HERE, two, 2, 0.0, true)).is_not_null()


func test_the_walk_of_the_dead_is_allowed_for() -> void:
	# A pack that walks at the bot for the whole fuse (3 s at 2 m/s) is 6 m nearer when it blows.
	var grenadier := BotGrenadier.new(_level())
	var pack: Array[Dictionary] = []
	for i in 3:
		pack.append(_zombie(i + 1, Vector3(float(i), 0.0, -14.0), Vector3(0, 0, 2.0)))
	var throw := grenadier.plan(HERE, pack, 2, 0.0)
	assert_object(throw).is_not_null()
	assert_float(HERE.distance_to(throw.landing)).is_between(7.0, 8.5)
	# The same pack 3 m nearer would be on the bot when it blows: no throw.
	for zombie in pack:
		zombie["position"].z += 3.0
	assert_object(grenadier.plan(HERE, pack, 2, 0.0)).is_null()


func test_a_teammate_beside_the_pack_does_not_stop_the_throw() -> void:
	# Only the thrower takes a grenade's damage (#856): the bots no longer keep off their teammates.
	# `plan` is not even told where they stand.
	var grenadier := BotGrenadier.new(_level())
	var throw := grenadier.plan(HERE, _pack(Vector3(0, 0, -10)), 2, 0.0)
	assert_object(throw).is_not_null()
	assert_float(Vector2(throw.landing.x, throw.landing.z).length()).is_greater_equal(
		BotGrenadier.SAFE_FROM_SELF
	)


## A low throw along -z (yaw 0) whose arc is `height` metres up at `distance` metres out: the pitch
## found by scanning, the arc worked out as `arc_is_open` does.
func _throw_low_at(grenadier: BotGrenadier, distance: float, height: float) -> BotGrenadier.Throw:
	var def := grenadier.def
	var throw := BotGrenadier.Throw.new()
	throw.yaw = 0.0
	var pitch := -0.6
	while pitch < 0.6:
		var angle := pitch + deg_to_rad(def.over_lift_deg)
		var vx := def.over_speed * cos(angle)
		var vy := def.over_speed * sin(angle)
		var t := (distance - BotGrenadier.HAND_REACH) / vx
		if def.hand_height + vy * t - 0.5 * def.gravity * t * t >= height:
			break
		pitch += 0.01
	throw.pitch = pitch
	throw.landing = Vector3(0.0, 0.0, -10.0)
	return throw


func test_a_zombie_that_would_stop_the_grenade_short_stops_the_throw() -> void:
	# A zombie in the way of a low arc nearer than the safe distance drops the grenade at the bot's
	# feet (#872); one met beyond it only lands it among the dead, and one off the line is no
	# matter. (A lob flies over a zombie at the bot's side, as the real grenade does.)
	var grenadier := BotGrenadier.new(_level())
	var at_four := _throw_low_at(grenadier, 4.0, 1.0)
	var in_line: Array[Dictionary] = [_zombie(9, Vector3(0.0, 0.0, -4.0))]
	assert_bool(grenadier.arc_is_open(HERE, at_four, [])).is_true()
	assert_bool(grenadier.arc_is_open(HERE, at_four, in_line)).is_false()
	var beside: Array[Dictionary] = [_zombie(9, Vector3(3.0, 0.0, -4.0))]
	assert_bool(grenadier.arc_is_open(HERE, at_four, beside)).is_true()
	var at_nine := _throw_low_at(grenadier, 9.0, 1.0)
	var far: Array[Dictionary] = [_zombie(9, Vector3(0.0, 0.0, -9.0))]
	assert_bool(grenadier.arc_is_open(HERE, at_nine, far)).is_true()


func test_a_zombie_that_walks_into_the_line_in_time_stops_the_throw() -> void:
	# Where the zombie will stand as the grenade passes is what counts: one now two metres off the
	# line but crossing it is in the way by then.
	var grenadier := BotGrenadier.new(_level())
	var at_four := _throw_low_at(grenadier, 4.0, 1.0)
	var crossing: Array[Dictionary] = [_zombie(9, Vector3(2.0, 0.0, -4.0), Vector3(-6.0, 0.0, 0.0))]
	assert_bool(grenadier.arc_is_open(HERE, at_four, crossing)).is_false()
	var standing: Array[Dictionary] = [_zombie(9, Vector3(2.0, 0.0, -4.0))]
	assert_bool(grenadier.arc_is_open(HERE, at_four, standing)).is_true()


func test_the_safe_distances_keep_a_blast_from_reaching_anyone() -> void:
	# A blast hurts its thrower all the way out to its radius (`PlayerBlast`), so the bot's distances
	# are where it takes under a tenth of the health: held to the real curve, not a number to tune.
	# (A teammate takes nothing, #856, so there is no teammate distance.)
	var grenadier := BotGrenadier.new(_level())
	var harmless := grenadier.harmless_apart()
	assert_float(BotGrenadier.SAFE_FROM_SELF).is_greater_equal(harmless)
	var def := grenadier.def
	var at_that := PlayerBlast.share(harmless, def.player_full_radius, def.blast_radius)
	assert_float(at_that).is_less_equal(BotGrenadier.HARMLESS_SHARE + 0.001)


func test_no_throw_lands_where_it_would_hurt_the_bot() -> void:
	# Every throw planned over a spread of packs leaves the bot where the blast takes at most a
	# fiftieth of its health, at the spot it was aimed at (a metre of slack before a tenth).
	var picker := RandomNumberGenerator.new()
	picker.seed = 805
	var thrown := 0
	for _i in 120:
		var grenadier := BotGrenadier.new(_level())
		var def := grenadier.def
		var pack := _pack(Vector3(picker.randf_range(-6, 6), 0, picker.randf_range(-13, -7)))
		var throw := grenadier.plan(HERE, pack, 2, 0.0)
		if throw == null:
			continue
		thrown += 1
		var apart := Vector2(throw.landing.x, throw.landing.z).length()
		var share := PlayerBlast.share(apart, def.player_full_radius, def.blast_radius)
		assert_float(share).is_less_equal(0.03)
	assert_int(thrown).is_greater(10)


func test_a_blast_close_to_the_bot_itself_is_not_thrown() -> void:
	var grenadier := BotGrenadier.new(_level())
	assert_bool(grenadier.is_safe(Vector3(0, 0, -5.0), HERE)).is_false()
	assert_bool(grenadier.is_safe(Vector3(0, 0, -6.5), HERE)).is_false()
	assert_bool(grenadier.is_safe(Vector3(0, 0, -7.5), HERE)).is_true()


func test_a_wall_across_the_arc_stops_the_throw() -> void:
	# A wall 4 m out, as tall as the sky: the arc cannot clear it.
	var wall := func(from: Vector3, to: Vector3) -> float:
		var along_z: float = from.z - to.z
		if from.z > -4.0 and to.z <= -4.0 and absf(along_z) > 0.001:
			return from.distance_to(to) * ((from.z + 4.0) / along_z)
		return -1.0
	var level := BotLevel.new(wall)
	var grenadier := BotGrenadier.new(level)
	assert_object(grenadier.plan(HERE, _pack(Vector3(0, 0, -10)), 2, 0.0)).is_null()


func test_the_pitch_lands_the_real_arc_near_the_pack() -> void:
	var grenadier := BotGrenadier.new(_level())
	var def := grenadier.def
	for distance in [3.5, 6.5, 8.0, 9.0, 11.0, 12.0]:
		var style := &"under" if distance <= BotGrenadier.UNDERARM_UP_TO else &"over"
		var pitch := grenadier.solve_pitch(distance, style)
		assert_bool(is_nan(pitch)).is_false()
		var aim := Basis.from_euler(Vector3(pitch, 0.0, 0.0)) * Vector3.FORWARD
		var hand := Vector3(0.0, def.hand_height, 0.0) + Vector3.FORWARD * BotGrenadier.HAND_REACH
		var release := (
			BotGrenadier.RELEASE_UNDER if style == &"under" else BotGrenadier.RELEASE_OVER
		)
		var flight := GrenadeArc.predict(
			def,
			hand,
			aim,
			Vector3.ZERO,
			style == &"under",
			_ground,
			STEP,
			def.fuse - release - BotGrenadier.COOK_SECONDS
		)
		var landed: float = Vector2(flight["landing"].x, flight["landing"].z).length()
		assert_float(landed).is_between(distance - 1.0, distance + 1.0)


func test_a_distance_no_throw_reaches_has_no_pitch() -> void:
	var grenadier := BotGrenadier.new(_level())
	assert_bool(is_nan(grenadier.solve_pitch(80.0, &"over"))).is_true()
	assert_bool(is_nan(grenadier.solve_pitch(0.1, &"over"))).is_true()
