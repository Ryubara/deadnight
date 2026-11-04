# A bot whose goal lies beyond the field's fence (#677). The walking mesh runs through each breach's
# boards into the pocket the dead break in from, so a goal there is "on the mesh" and the path to it
# is fine, but the boards stop a body: the bot stood against them for ten seconds and more, climbing
# the stuck ladder again and again. The path now says so before the bot walks: the goal is marked
# unreachable at once (the brain takes another), and a goal at the fence's own edge is walked to as
# near as the body gets.
#
# Since #995 the walking mesh has no polygon across a barricade (`NavLayers`), so the path stops at
# the boards' line before the walled-path check has anything to see; both stay.
#
# The probe sends one bot, whose brain wants a goal and nothing else (`GoalBrain`), to each place
# from the field side, in the real lot with the boards up, and reads the longest stuck episode.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SEED := 31
## Seconds each walk is given.
const WALK_SECONDS := 20
## The longest stuck episode the issue allows (seconds).
const LONGEST_STUCK := 3.0

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


func _night() -> SeatedNight:
	var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), SEED)
	night.seat(1, BotProfile.regular(), SEED + 1)
	await night.settle(12)
	_catcher.start()
	return night


func _bot(night: SeatedNight) -> BotClient:
	return night.host.bots[0]


## Walks the bot from `from` to `goal` with the arrival radius `radius` and returns how it went.
func _walk(
	night: SeatedNight, brain: GoalBrain, from: Vector3, goal: Vector3, radius: float
) -> Dictionary:
	var bot := _bot(night)
	var body := night.server.body_of(1)
	body.teleport(from + Vector3(0.0, 0.1, 0.0))
	night.run(5)
	brain.goal = goal
	brain.radius = radius
	bot.legs.stuck.reset()
	bot.legs.stuck.longest_episode = 0.0
	var stuck_before := bot.legs.stuck.stuck_seconds
	var marks_before := bot.legs.path.walled_marks
	var closest := INF
	for _t in WALK_SECONDS * TICKS_PER_SECOND:
		night.tick()
		closest = minf(closest, _flat(body.global_position, goal))
	return {
		"end": body.global_position,
		"closest": closest,
		"longest_stuck": bot.legs.stuck.longest(),
		"stuck_seconds": bot.legs.stuck.stuck_seconds - stuck_before,
		"walled": bot.legs.path.walled_marks - marks_before,
	}


func _brain(night: SeatedNight) -> GoalBrain:
	var bot := _bot(night)
	var brain := GoalBrain.new()
	brain.legs = bot.legs
	bot.brain = brain
	return brain


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Places past the field's fences, each with where to walk from: the pockets outside the west
## breaches (the boards at x = -61.9), the east one, and the north one.
func _walled_goals() -> Array[Dictionary]:
	return [
		{"goal": Vector3(-64.0, 0.0, -22.0), "from": Vector3(-50.0, 0.0, -19.0)},
		{"goal": Vector3(-66.0, 0.0, -22.0), "from": Vector3(-50.0, 0.0, -19.0)},
		{"goal": Vector3(64.0, 0.0, -22.0), "from": Vector3(50.0, 0.0, -19.0)},
		{"goal": Vector3(-64.0, 0.0, -46.0), "from": Vector3(-50.0, 0.0, -43.0)},
		{"goal": Vector3(-36.0, 0.0, -54.5), "from": Vector3(-30.0, 0.0, -48.0)},
	]


func test_a_goal_in_a_breach_pocket_is_marked_unreachable_and_the_bot_does_not_wedge() -> void:
	var night := await _night()
	var brain := _brain(night)
	for place in _walled_goals():
		var result := _walk(night, brain, place["from"], place["goal"], 1.0)
		var label := "goal %s: %s" % [place["goal"], result]
		(
			assert_float(result["longest_stuck"])
			. override_failure_message("stuck for too long, %s" % label)
			. is_less(LONGEST_STUCK)
		)
		# The walking mesh has no way across a barricade (#995), so a goal in a pocket is either
		# marked unreachable at once or walked to as near as the mesh goes, never to the boards.
		(
			assert_float(result["closest"])
			. override_failure_message("walked up to the boards, %s" % label)
			. is_greater(BotPath.REACHED_SHORT)
		)
		# It never got through the boards, nor stood in the pocket.
		assert_float(_flat(result["end"], place["goal"])).is_greater(2.0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_goal_at_the_fence_post_is_walked_to_as_near_as_the_body_gets() -> void:
	var night := await _night()
	var brain := _brain(night)
	for radius in [0.5, 1.0]:
		# Straight in along the line of the posts, and a goal behind them.
		for goal in [Vector3(-61.5, 0.0, -20.4), Vector3(-63.5, 0.0, -30.0)]:
			var result := _walk(night, brain, Vector3(-50.0, 0.0, goal.z), goal, radius)
			var label := "goal %s radius %s: %s" % [goal, radius, result]
			(
				assert_float(result["longest_stuck"])
				. override_failure_message("stuck for too long, %s" % label)
				. is_less(LONGEST_STUCK)
			)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_wall_the_mesh_does_not_know_is_seen_by_the_path_and_a_person_in_the_way_is_not(
) -> void:
	var night := await _night()
	var brain := _brain(night)
	var from := Vector3(-30.0, 0.0, -19.0)
	var goal := Vector3(-30.0, 0.0, -12.0)
	var clear := _walk(night, brain, from, goal, 1.0)
	assert_int(clear["walled"]).is_equal(0)
	assert_float(clear["closest"]).is_less(1.5)
	# A box across the aisle that the mesh was never baked with.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 2.2, 0.6)
	shape.shape = box
	body.add_child(shape)
	night.world.add_child(body)
	body.global_position = Vector3(-30.0, 1.1, -15.5)
	await night.settle(3)
	var walled := _walk(night, brain, from, goal, 1.0)
	assert_int(walled["walled"]).is_greater_equal(1)
	assert_float(walled["longest_stuck"]).is_less(LONGEST_STUCK)
	body.queue_free()
	night.dispose()
