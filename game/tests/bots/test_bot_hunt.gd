# The last zombies of a round (bots plan, phase 7, #770): every screen outlines them through the
# walls and a person goes and finds them; a bot reads the same rule off the frame and goes to look,
# once the round has been down to them for a while, the nearest free bot to each. On the rig (a bot
# with no server behind it) and on plain data.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const FAR := Vector3(0.0, 0.0, -60.0)


func _rig() -> BotRig:
	var rig := BotRig.new()
	rig.profile.follows = true
	return rig


func _seconds(rig: BotRig, seconds: float) -> void:
	rig.run(int(seconds * float(TICKS_PER_SECOND)))


func _zombie(id: int, at: Vector3, mode := ZombieBody.Mode.CHASE) -> Dictionary:
	return {"id": id, "position": at, "mode": mode}


# --- Which zombies are marked ---


func test_the_zombies_are_marked_when_the_round_is_down_to_its_last_three() -> void:
	var zombies: Array[Dictionary] = [_zombie(1, FAR), _zombie(2, Vector3.ZERO)]
	var active := BotErrands.ACTIVE_PHASE
	assert_int(BotHunt.marked(zombies, active, 2, 3).size()).is_equal(2)
	assert_int(BotHunt.marked(zombies, active, 3, 3).size()).is_equal(2)
	# Four left, none left, a break, or a dying one: nobody is marked.
	assert_int(BotHunt.marked(zombies, active, 4, 3).size()).is_equal(0)
	assert_int(BotHunt.marked(zombies, active, 0, 3).size()).is_equal(0)
	assert_int(BotHunt.marked(zombies, BotErrands.BREAK_PHASE, 2, 3).size()).is_equal(0)
	zombies.append(_zombie(3, FAR, ZombieBody.Mode.DYING))
	assert_int(BotHunt.marked(zombies, active, 3, 3).size()).is_equal(2)


func test_under_follow_only_a_zombie_far_from_the_person_is_worth_the_walk() -> void:
	var person := Vector3(0.0, 0.0, -34.0)
	assert_bool(BotHunt.worth_the_walk(Vector3(10.0, 0.0, -34.0), true, person)).is_false()
	assert_bool(BotHunt.worth_the_walk(Vector3(-66.0, 0.0, 15.0), true, person)).is_true()
	assert_bool(BotHunt.worth_the_walk(Vector3(10.0, 0.0, -34.0), false, person)).is_true()


# --- The bot goes ---


func test_a_bot_goes_to_look_for_the_last_zombie_after_a_while_and_not_before() -> void:
	var rig := _rig()
	rig.put_zombie(7, FAR)
	_seconds(rig, BotHunt.AFTER - 3.0)
	assert_str(rig.bot.intent.note).is_not_equal("hunt")
	_seconds(rig, 6.0)
	assert_str(rig.bot.intent.note).is_equal("hunt")
	assert_float(rig.bot.intent.goal.distance_to(FAR)).is_less(1.0)
	assert_float(rig.bot.intent.goal_radius).is_equal(BotHunt.STOP)


func test_a_round_with_more_than_the_last_few_left_is_not_hunted() -> void:
	var rig := _rig()
	rig.put_zombie(7, FAR)
	rig.remaining = 6
	_seconds(rig, BotHunt.AFTER + 5.0)
	assert_str(rig.bot.intent.note).is_not_equal("hunt")


func test_a_bot_ordered_to_hold_stays_where_it_is() -> void:
	var orders := BotOrders.new()
	orders.issue(BotOrders.HOLD, 9, Vector3.ZERO)
	var held := _rig()
	held.orders = orders.to_frame()
	held.put_zombie(7, FAR)
	_seconds(held, BotHunt.AFTER + 5.0)
	assert_str(held.bot.intent.note).is_not_equal("hunt")


func test_a_bot_with_a_zombie_in_sight_fights_it_instead() -> void:
	var rig := _rig()
	rig.put_zombie(7, Vector3(0.0, 0.0, -9.0))
	_seconds(rig, BotHunt.AFTER + 5.0)
	assert_str(rig.bot.intent.note).is_not_equal("hunt")


func test_a_bot_that_cannot_find_the_zombie_gives_it_up_for_a_while() -> void:
	var rig := _rig()
	# The zombie is 3 m away but behind a wall: the sight says so.
	rig.set_sight(func(_from: Vector3, _to: Vector3) -> float: return 0.5)
	rig.put_zombie(7, Vector3(0.0, 0.0, -3.0))
	_seconds(rig, BotHunt.AFTER + 2.0)
	assert_str(rig.bot.intent.note).is_equal("hunt")
	_seconds(rig, BotHunt.PATIENCE + 2.0)
	assert_str(rig.bot.intent.note).is_not_equal("hunt")


func test_a_zombie_the_mesh_has_no_way_to_is_left_alone() -> void:
	var rig := _rig()
	rig.put_zombie(7, FAR)
	_seconds(rig, BotHunt.AFTER + 2.0)
	assert_str(rig.bot.intent.note).is_equal("hunt")
	# The legs found no way to the place (a pocket of the mesh): the bot does not stand at the end of a
	# walk that goes nowhere.
	rig.bot.legs.path.block(FAR, rig.bot.perception.beliefs.now, 100.0)
	_seconds(rig, 1.0)
	assert_str(rig.bot.intent.note).is_not_equal("hunt")
