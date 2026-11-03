# A bot with no way out (bots plan, phase 5): boxed in for two seconds on end it counts itself
# trapped, a free heading for half a second makes it free again, and the nearest place to jump from
# within eight metres is the one it goes to.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60


func test_two_seconds_boxed_in_make_a_bot_trapped_once() -> void:
	var trapped := BotTrapped.new()
	var told := 0
	var now := 0.0
	while now < 6.0:
		if trapped.update(true, now):
			told += 1
		now += 0.125
	assert_bool(trapped.trapped).is_true()
	assert_int(told).is_equal(1)


func test_a_short_squeeze_is_not_being_trapped() -> void:
	var trapped := BotTrapped.new()
	var now := 0.0
	while now < BotTrapped.SECONDS - 0.2:
		trapped.update(true, now)
		now += 0.125
	assert_bool(trapped.trapped).is_false()
	# A way out that lasts frees it and starts the count again.
	for _i in 8:
		trapped.update(false, now)
		now += 0.125
	for _i in 8:
		trapped.update(true, now)
		now += 0.125
	assert_bool(trapped.trapped).is_false()


func test_a_flicker_of_a_free_heading_does_not_end_it() -> void:
	var trapped := BotTrapped.new()
	var now := 0.0
	while now < 3.0:
		trapped.update(true, now)
		now += 0.125
	assert_bool(trapped.trapped).is_true()
	trapped.update(false, now)
	now += 0.125
	trapped.update(true, now)
	assert_bool(trapped.trapped).is_true()
	for _i in 8:
		now += 0.125
		trapped.update(false, now)
	assert_bool(trapped.trapped).is_false()


func test_the_nearest_place_to_jump_from_within_reach_is_chosen() -> void:
	var near := BotLink.new(Vector3(3, 0, 0), Vector3(3, 1, -1))
	var far := BotLink.new(Vector3(6, 0, 0), Vector3(6, 1, -1))
	var out := BotLink.new(Vector3(20, 0, 0), Vector3(20, 1, -1))
	var links: Array[BotLink] = [far, out, near]
	assert_object(BotTrapped.nearest_link(Vector3.ZERO, links)).is_same(near)
	var none: Array[BotLink] = [out]
	assert_object(BotTrapped.nearest_link(Vector3.ZERO, none)).is_null()


# --- Scenario 15: the bot in a pocket ---


## A bot standing in a pocket: every low ray (the knee's, which is what a wall is to a walker) is
## stopped 0.4 m out, the eyes see over it. The dead stand close and do not come nearer (the rig
## moves nothing by itself).
func _pocket(links: Array[BotLink] = []) -> BotRig:
	var rig := BotRig.new(BotProfile.regular(), 3, Callable(self, &"_low_wall"))
	for link in links:
		rig.level.links.append(link)
	rig.position = Vector3.ZERO
	rig.put_zombie(1, Vector3(0.0, 0.0, -1.1))
	rig.put_zombie(2, Vector3(0.9, 0.0, -1.0))
	rig.put_zombie(3, Vector3(-0.9, 0.0, -1.0))
	return rig


func _low_wall(from: Vector3, _to: Vector3) -> float:
	return 0.4 if from.y < 0.9 else -1.0


func _said(rig: BotRig, line: StringName) -> int:
	return rig.sent.filter(func(a: Dictionary) -> bool: return a.get("line") == line).size()


func test_scenario_15_a_bot_boxed_in_fights_reports_once_and_does_not_move() -> void:
	var rig := _pocket()
	rig.run(5 * TICKS_PER_SECOND)
	var brain := rig.bot.brain as BotFightBrain
	assert_bool(brain.trapped.trapped).is_true()
	assert_int(rig.bot.telemetry.counters.get(&"bot_trapped", 0)).is_equal(1)
	# It told the others once, and went on shooting.
	assert_int(_said(rig, BotSay.TRAPPED)).is_equal(1)
	assert_int(rig.shot_ticks.size()).is_greater(3)
	# No teleport: the bot is where it was (the rig moves a body only when told).
	assert_vector(rig.position).is_equal(Vector3.ZERO)
	assert_str(rig.bot.intent.note).is_equal("trapped")


func test_a_trapped_bot_with_a_place_to_jump_from_goes_to_it_and_jumps() -> void:
	var link := BotLink.new(Vector3(0.3, 0.0, 0.5), Vector3(0.3, 1.0, 1.5))
	var rig := _pocket([link])
	rig.run(4 * TICKS_PER_SECOND)
	assert_bool((rig.bot.brain as BotFightBrain).trapped.trapped).is_true()
	assert_vector(rig.bot.intent.goal).is_equal(link.from)
	# At the place, the legs jump the way it says.
	rig.position = link.from
	var jumped := false
	for _i in 30:
		rig.step()
		jumped = jumped or rig.bot.intent.jump
	assert_bool(jumped).is_true()
