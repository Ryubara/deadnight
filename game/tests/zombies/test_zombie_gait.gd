extends GdUnitTestSuite
## The dead's gait follows their speed: the clips blend and play at a rate that keeps the planted
## foot on the ground (docs/research/zombie-gait.md). Each zombie is measured on the real rig and
## clips, stepped at a fixed 60 Hz.

const STEP := 1.0 / 60.0
## A planted foot is one within this share of its own lift from its lowest point.
const PLANTED := 0.2
## Seconds of walking measured (several cycles even at the slowest gait).
const SECONDS := 5.0
## The planted foot may slide this much against the ground (ground speed over foot speed), either
## way: the clips are poses blended and scaled, not root motion, and the foot is read off 60 Hz
## samples; the median must be close, and no gait far off.
const SLIDE_LOW := 0.7
const SLIDE_HIGH := 1.8
const FEET: Array[String] = ["Foot.L", "Foot.R"]
const HANDS: Array[String] = ["LowerArm.L", "LowerArm.R"]


func _view(look: StringName) -> ZombieView:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(look), 1, 0.0, 0.7, look)
	return view


func _entry(speed: float) -> Dictionary:
	return {
		"id": 1,
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"mode": ZombieBody.Mode.CHASE,
		"episode": 1,
		"speed": speed,
	}


## The ground speed the planted foot (or hand, for a crawler) moves backward at in the pose the
## view plays at `speed` (median over the planted frames). With `hold` at a blend position, the
## move state is held there at its authored rate instead: the speed one clip covers.
func _foot_speed(look: StringName, speed: float, hold: float = -1.0) -> float:
	var view := _view(look)
	view.apply(_entry(speed), STEP)
	if hold >= 0.0:
		view.tree.set(ZombieRig.BLEND_PARAMETER, hold)
		view.tree.set(ZombieRig.MOVE_RATE_PARAMETER, 1.0)
	view.tree.advance(0.0)
	var skeleton := view.model().find_child("Skeleton3D", true, false) as Skeleton3D
	var names := HANDS if ZombieModels.crawls(look) else FEET
	var bones: Array[int] = []
	for bone_name in names:
		bones.append(skeleton.find_bone(bone_name))
	# Settle the blend, then sample.
	view.tree.advance(0.5)
	var along: Array = []
	var up: Array = []
	for i in roundi(SECONDS / STEP):
		view.tree.advance(STEP)
		var row_along: Array[float] = []
		var row_up: Array[float] = []
		for bone in bones:
			var at := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
			row_along.append(at.z)
			row_up.append(at.y)
		along.append(row_along)
		up.append(row_up)
	# A planted frame is one where the foot is in the lowest part of its own lift; the foot must
	# travel back there as fast as the ground goes by (median, so a step's lift does not count).
	var speeds: Array[float] = []
	for j in bones.size():
		var low := INF
		var high := -INF
		for i in up.size():
			low = minf(low, up[i][j])
			high = maxf(high, up[i][j])
		var limit: float = low + (high - low) * PLANTED
		for i in range(1, up.size()):
			if up[i][j] <= limit and up[i - 1][j] <= limit:
				speeds.append(absf(along[i][j] - along[i - 1][j]) / STEP)
	speeds.sort()
	return speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0


## The speeds of the round curve (docs/research/movement-speeds.md): the round's walking pace,
## times the type, lit or in the dark.
func _pace(round_number: int, type_multiplier: float, dark: bool) -> float:
	var tuning := RoundTuning.new()
	var speed := minf(tuning.speed_for_round(round_number) * type_multiplier, tuning.speed_cap)
	return tuning.speed_on_ground(speed, not dark)


func test_the_blend_goes_from_idle_to_walk_to_run_by_speed() -> void:
	var walker := ZombieModels.DEFAULT
	assert_float(ZombieRig.blend_position(walker, 0.0)).is_equal(0.0)
	assert_float(ZombieRig.blend_position(walker, ZombieRig.IDLE_FADE)).is_equal_approx(
		ZombieRig.WALK_AT, 0.001
	)
	# Creeping, it is the walk, not a half idle.
	assert_float(ZombieRig.blend_position(walker, 0.7)).is_equal(ZombieRig.WALK_AT)
	assert_float(ZombieRig.blend_position(walker, ZombieRig.CROSS_FROM)).is_equal(ZombieRig.WALK_AT)
	var mid := ZombieRig.blend_position(walker, 2.2)
	assert_float(mid).is_between(ZombieRig.WALK_AT, ZombieRig.RUN_AT)
	assert_float(ZombieRig.blend_position(walker, 2.6)).is_greater(mid)
	assert_float(ZombieRig.blend_position(walker, ZombieRig.CROSS_TO)).is_equal(ZombieRig.RUN_AT)
	assert_float(ZombieRig.blend_position(walker, ZombieRig.RUN_AT)).is_equal(ZombieRig.RUN_AT)
	# Past the run, the sprint comes in linearly (the two share a cycle), and holds past its speed.
	assert_float(ZombieRig.blend_position(walker, 5.5)).is_equal_approx(5.5, 0.001)
	assert_float(ZombieRig.blend_position(walker, ZombieRig.SPRINT_AT + 1.0)).is_equal(
		ZombieRig.SPRINT_AT
	)
	assert_float(ZombieRig.blend_position(&"crawler", 6.25)).is_less_equal(ZombieRig.RUN_AT)


func test_the_rate_makes_the_gait_cover_the_ground() -> void:
	var walker := ZombieModels.DEFAULT
	# Wherever the rate is not at a limit, the gait at that rate covers exactly the ground speed.
	for speed in [0.6, 1.0, 1.4, 2.0, 2.2, 2.8, 3.0, 4.4, 5.0, 6.25, 8.0]:
		var rate := ZombieRig.gait_rate(walker, speed)
		var native := ZombieRig.blend_speed(
			ZombieRig.run_weight(walker, speed), ZombieRig.sprint_weight(walker, speed)
		)
		var covered := native * rate
		assert_float(covered).override_failure_message("at %s m/s" % speed).is_equal_approx(
			speed, 0.01
		)
	# Within the band: the walk is played up to 1.5x, the run down to 0.7x at the crossing.
	assert_float(ZombieRig.gait_rate(walker, ZombieRig.CROSS_FROM)).is_between(1.3, 1.5)
	assert_float(ZombieRig.gait_rate(walker, ZombieRig.CROSS_TO)).is_between(0.65, 0.75)
	# From the run to the sprint the clips play at their own rate; faster still, the sprint is
	# played faster, up to the limit.
	for speed in [ZombieRig.RUN_AT, 5.0, 6.25, ZombieRig.SPRINT_AT]:
		assert_float(ZombieRig.gait_rate(walker, speed)).is_equal_approx(1.0, 0.001)
	assert_float(ZombieRig.gait_rate(walker, 8.0)).is_equal_approx(8.0 / ZombieRig.SPRINT_AT, 0.001)
	assert_float(ZombieRig.gait_rate(walker, 20.0)).is_equal(ZombieRig.MAX_RATE)
	# Slower than the walk: played slower, down to the limit; standing, not scaled at all.
	assert_float(ZombieRig.gait_rate(walker, 0.6)).is_equal_approx(0.6 / ZombieRig.WALK_AT, 0.001)
	assert_float(ZombieRig.gait_rate(walker, 0.2)).is_between(ZombieRig.MIN_RATE, 1.0)
	assert_float(ZombieRig.gait_rate(walker, 0.0)).is_equal(1.0)
	assert_float(ZombieRig.gait_rate(walker, 0.45)).is_equal(ZombieRig.MIN_RATE)


func test_crawlers_and_the_boss_are_played_to_their_speed() -> void:
	assert_float(ZombieRig.gait_rate(&"crawler", 2.2)).is_equal(ZombieRig.MAX_RATE)
	assert_float(ZombieRig.gait_rate(&"crawler", 0.7)).is_equal_approx(
		0.7 / ZombieRig.CRAWL_SPEED, 0.001
	)
	assert_float(ZombieRig.gait_rate(&"headliner", 1.5)).is_equal_approx(
		1.5 / ZombieRig.BOSS_WALK_AT, 0.001
	)
	assert_float(ZombieRig.gait_rate(&"headliner", 0.6)).is_equal_approx(
		0.6 / ZombieRig.BOSS_WALK_AT, 0.001
	)


func test_the_gait_follows_the_round_curve() -> void:
	var walker := ZombieModels.DEFAULT
	# Round 1 shambles, round 10 jogs (walk and run blended), round 20 in the dark sprints.
	assert_float(ZombieRig.run_weight(walker, _pace(1, 1.0, false))).is_equal(0.0)
	assert_float(ZombieRig.run_weight(walker, _pace(10, 1.0, false))).is_between(0.3, 0.9)
	assert_float(ZombieRig.run_weight(walker, _pace(20, 1.0, true))).is_equal(1.0)
	var previous := -1.0
	for round_number in range(1, 21):
		var run := ZombieRig.run_weight(walker, _pace(round_number, 1.0, false))
		assert_float(run).is_greater_equal(previous)
		previous = run
	# A runner late in the dark sprints, at close to the sprint's own rate (#278: before the
	# sprint it was the run played 1.42 times).
	var dark_runner := _pace(20, 1.4, true)
	assert_float(ZombieRig.sprint_weight(&"runner", dark_runner)).is_greater(0.5)
	assert_float(ZombieRig.gait_rate(&"runner", dark_runner)).is_between(0.8, 1.2)


func test_the_view_sets_the_blend_and_the_rate_on_the_tree() -> void:
	var view := _view(&"walker")
	view.apply(_entry(6.25), STEP)
	assert_float(view.tree.get(ZombieRig.BLEND_PARAMETER)).is_equal_approx(6.25, 0.001)
	assert_float(view.tree.get(ZombieRig.MOVE_RATE_PARAMETER)).is_equal_approx(1.0, 0.001)
	view.apply(_entry(8.0), STEP)
	assert_float(view.tree.get(ZombieRig.BLEND_PARAMETER)).is_equal(ZombieRig.SPRINT_AT)
	assert_float(view.tree.get(ZombieRig.MOVE_RATE_PARAMETER)).is_equal_approx(
		8.0 / ZombieRig.SPRINT_AT, 0.001
	)
	var crawler := _view(&"crawler")
	crawler.apply(_entry(2.0), STEP)
	assert_float(crawler.tree.get(ZombieRig.CRAWL_RATE_PARAMETER)).is_equal(ZombieRig.MAX_RATE)


func test_the_throttle_keeps_the_rate_when_it_advances_late() -> void:
	# A far zombie is advanced every Nth frame with the time it missed: the same distance of
	# animation as stepping each frame.
	var every := _view(&"runner")
	var late := _view(&"runner")
	every.apply(_entry(6.25), STEP)
	late.apply(_entry(6.25), STEP)
	every.tree.advance(0.0)  # the first advance after a state starts only enters it
	late.tree.advance(0.0)
	for i in 12:
		every.accumulated += STEP
		every.advance_animation()
		late.accumulated += STEP
	late.advance_animation()
	var a := every.model().find_child("Skeleton3D", true, false) as Skeleton3D
	var b := late.model().find_child("Skeleton3D", true, false) as Skeleton3D
	var leg := a.find_bone("UpperLeg.L")
	var apart := rad_to_deg(a.get_bone_pose_rotation(leg).angle_to(b.get_bone_pose_rotation(leg)))
	assert_float(apart).is_less(0.5)


func test_the_feet_keep_up_with_the_ground_across_the_rounds() -> void:
	var ratios: Array[float] = []
	var worst := 1.0
	for entry: Array in [[&"walker", 1.0], [&"runner", 1.4], [&"brute", 0.4]]:
		for round_number in [1, 10, 20]:
			for dark in [false, true]:
				var speed := _pace(round_number, entry[1], dark)
				var ratio := speed / maxf(_foot_speed(entry[0], speed), 0.01)
				ratios.append(ratio)
				if absf(log(ratio)) > absf(log(worst)):
					worst = ratio
				(
					assert_float(ratio)
					. override_failure_message(
						(
							"%s round %d%s at %.2f m/s"
							% [entry[0], round_number, " dark" if dark else "", speed]
						)
					)
					. is_between(SLIDE_LOW, SLIDE_HIGH)
				)
	ratios.sort()
	assert_float(ratios[ratios.size() / 2]).is_between(0.9, 1.15)
	print("foot slide: median %.2f, worst %.2f" % [ratios[ratios.size() / 2], worst])


func test_crawlers_keep_up_on_their_hands() -> void:
	for speed in [0.5, 1.0, 1.7]:
		var ratio: float = speed / maxf(_foot_speed(&"crawler", speed), 0.01)
		assert_float(ratio).override_failure_message("crawler at %s m/s" % speed).is_between(
			SLIDE_LOW, SLIDE_HIGH
		)


func test_each_clip_covers_the_speed_its_blend_point_says() -> void:
	# The blend points are the clips' measured ground speeds (docs/research/zombie-gait.md): each
	# clip held at its point and played at its authored rate, read off the planted foot.
	var walker := ZombieModels.DEFAULT
	var measured := {}
	for point in [ZombieRig.WALK_AT, ZombieRig.RUN_AT, ZombieRig.SPRINT_AT]:
		var speed := _foot_speed(walker, point, point)
		measured[point] = speed
		(
			assert_float(speed / point)
			. override_failure_message("clip at %s m/s covers %.2f" % [point, speed])
			. is_between(0.85, 1.15)
		)
	print("clip ground speeds: %s" % measured)
	# The sprint covers more ground than the run at the same cadence.
	assert_float(measured[ZombieRig.SPRINT_AT]).is_greater(measured[ZombieRig.RUN_AT] * 1.3)


func test_the_sprint_is_in_the_shared_library() -> void:
	var view := _view(&"runner")
	var player := view.model().find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sprint := player.get_animation(
		StringName("%s/%s" % [ZombieRig.LIBRARY, ZombieRig.SPRINT_CLIP])
	)
	assert_object(sprint).is_not_null()
	assert_float(sprint.length).is_equal_approx(ZombieRig.SPRINT_CYCLE, 0.01)
	assert_int(sprint.loop_mode).is_equal(Animation.LOOP_LINEAR)
