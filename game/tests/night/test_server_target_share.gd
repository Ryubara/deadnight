# The grenades read the dead the combat was given, not a second list built in the same tick (#906):
# the same ids, minus the dead that fell between the two.
extends GdUnitTestSuite

var _night: Night


func before_test() -> void:
	_night = await NightFixture.start(self, Night.Mode.MANUAL, RulesFixture.tuning(), 7, null)


func after_test() -> void:
	_night.queue_free()
	await get_tree().physics_frame


func test_the_grenades_get_the_combats_targets_less_the_ones_that_fell() -> void:
	var sim := _night.server.sim
	ZombieFixture.standing(sim, 901, Vector3(4, 0, 4))
	var falling := ZombieFixture.standing(sim, 902, Vector3(6, 0, 4))
	ZombieFixture.standing(sim, 903, Vector3(8, 0, 4))
	var list := _night.server._target_list()
	assert_int(list.size()).is_greater_equal(3)
	var same := _night.server._still_standing(list)
	assert_int(same.size()).is_equal(list.size())
	# One falls after the list was built (a shot of this tick): it is not a blast target.
	falling.enter(ZombieBody.Mode.DYING)
	var after := _night.server._still_standing(list)
	assert_int(after.size()).is_equal(list.size() - 1)
	var ids: Array = after.map(func(target: Dictionary) -> int: return target["id"])
	assert_bool(ids.has(902)).is_false()
	assert_bool(ids.has(901)).is_true()
	# What the old code built, the new one answers: the same targets in the same order.
	var rebuilt := _night.server._target_list()
	(
		assert_array(after.map(func(target: Dictionary) -> int: return target["id"]))
		. is_equal(rebuilt.map(func(target: Dictionary) -> int: return target["id"]))
	)
