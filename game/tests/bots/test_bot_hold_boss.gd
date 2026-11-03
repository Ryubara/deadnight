# A bot under the Hold order and a boss (#769): the soak found holders that ran the length of the
# lot from the headliner and walked back into it, and holders that stood idle with it in view
# because a person was aiming at it. The order is the spot: a holder keeps off a boss only a few
# metres from it, does not walk back into it, and shoots a boss whoever else is aiming at it.
extends GdUnitTestSuite

const SPOT := Vector3(0.0, 0.0, 0.0)


func _boss(rig: BotRig, id: int, at: Vector3) -> ZombieBody:
	var boss := rig.put_zombie(id, at)
	boss.profile = ZombieProfile.new()
	boss.profile.look = &"headliner"
	return boss


## A holder standing `apart` metres south of the spot (the lone bot's place is the spot itself).
func _holder(apart: float) -> BotRig:
	var orders := BotOrders.new()
	orders.issue(BotOrders.HOLD, 9, SPOT)
	var rig := BotRig.new(BotProfile.regular(), 4)
	rig.profile.follows = true
	rig.orders = orders.to_frame()
	rig.position = SPOT + Vector3(0.0, 0.0, apart)
	return rig


func test_a_holder_near_its_spot_keeps_off_a_boss() -> void:
	var rig := _holder(1.0)
	_boss(rig, 1, rig.position + Vector3(0.0, 0.0, -4.0))
	rig.run(60)
	assert_str(rig.bot.intent.note).is_equal("retreat")


func test_a_holder_far_from_its_spot_stands_and_fights_a_boss_instead_of_running() -> void:
	var profile := BotProfile.regular()
	var rig := _holder(profile.hold_back + 2.0)
	_boss(rig, 1, rig.position + Vector3(0.0, 0.0, -4.0))
	rig.run(60)
	assert_str(rig.bot.intent.note).is_not_equal("retreat")
	assert_bool(rig.shot_ticks.is_empty()).is_false()


func test_a_holder_does_not_walk_back_to_a_place_the_boss_stands_at() -> void:
	var rig := _holder(5.0)
	# The boss is on the spot, 6.5 m from the bot: out of its keep-off, but at its place.
	_boss(rig, 1, SPOT + Vector3(0.0, 0.0, -1.5))
	rig.run(60)
	assert_str(rig.bot.intent.note).is_equal("hold_back")
	assert_bool(rig.bot.intent.goal.is_finite()).is_false()


func test_a_holder_goes_back_to_its_place_when_the_boss_is_gone() -> void:
	var rig := _holder(5.0)
	_boss(rig, 1, SPOT + Vector3(0.0, 0.0, -1.5))
	rig.run(60)
	rig.zombies.clear()
	rig.run(180)
	assert_str(rig.bot.intent.note).is_equal("hold_order")
	assert_bool(rig.bot.intent.goal.is_finite()).is_true()
