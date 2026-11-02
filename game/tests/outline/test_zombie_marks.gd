extends GdUnitTestSuite
## The last zombies of a round wear an outline through walls on every client: when it shows (the
## round is active and `remaining` is at most `mark_last`), how many zombies wear it, and that it
## turns off (the round ends, a zombie dies, the switch is flipped, the body is parked), through the
## night view's own frames.

const ACTIVE := GameRules.Phase.ACTIVE
const BREAK := GameRules.Phase.BREAK

var _state: ClientState
var _view: NightView
var _sim: ZombieSim


func before_test() -> void:
	var camera := auto_free(Camera3D.new()) as Camera3D
	add_child(camera)
	_state = ClientState.new()
	_view = auto_free(NightView.new())
	add_child(_view)
	_view.setup(_state, camera)
	_sim = ZombieFixture.sim()


## One frame of the server: `count` zombies standing, with `remaining` still to kill in the round.
func _frame(phase: int, remaining: int, count: int, dying: int = 0) -> void:
	_sim.zombies.clear()
	for id in count:
		var zombie := ZombieFixture.standing(_sim, id + 1, Vector3(id * 2.0, 0.0, 4.0))
		if id < dying:
			zombie.enter(ZombieBody.Mode.DYING)
	(
		_state
		. apply_events(
			[
				{
					"type": &"frame",
					"phase": phase,
					"remaining": remaining,
					"zombies": ZombieCodec.encode(_sim.zombies),
				}
			]
		)
	)


func _marked() -> int:
	return _view.marks.marked_count()


func _overlays(view: ZombieView) -> int:
	var count := 0
	for mesh in view.model().find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).material_overlay != null:
			count += 1
	return count


func test_the_rule_shows_in_an_active_round_with_few_left() -> void:
	assert_bool(ZombieMarks.rule(ACTIVE, 3, 3)).is_true()
	assert_bool(ZombieMarks.rule(ACTIVE, 1, 3)).is_true()
	assert_bool(ZombieMarks.rule(ACTIVE, 4, 3)).is_false()
	assert_bool(ZombieMarks.rule(ACTIVE, 0, 3)).is_false()


func test_the_rule_waits_for_an_active_round_and_a_count_above_zero() -> void:
	assert_bool(ZombieMarks.rule(BREAK, 2, 3)).is_false()
	assert_bool(ZombieMarks.rule(GameRules.Phase.OVER, 2, 3)).is_false()
	assert_bool(ZombieMarks.rule(ACTIVE, 2, 0)).is_false()


func test_n_is_the_tunings_and_defaults_to_three() -> void:
	assert_int(ZombieTuning.shipped().mark_last).is_equal(3)
	assert_int(_view.marks.mark_last).is_equal(ZombieTuning.shipped().mark_last)


func test_no_one_is_marked_while_more_than_n_are_left() -> void:
	_frame(ACTIVE, 12, 5)
	assert_int(_view.horde.view_count()).is_equal(5)
	assert_int(_marked()).is_equal(0)
	for view in _view.horde.views():
		assert_int(_overlays(view)).is_equal(0)


func test_the_last_three_are_marked() -> void:
	_frame(ACTIVE, 3, 3)
	assert_int(_marked()).is_equal(3)
	for view in _view.horde.views():
		assert_int(_overlays(view)).is_greater(0)


func test_one_left_marks_one() -> void:
	_frame(ACTIVE, 1, 1)
	assert_int(_marked()).is_equal(1)


func test_zombies_still_to_spawn_count_toward_the_last() -> void:
	# Two stand, two more are to come: four left, so none are marked yet; one dies and a spawn is left.
	_frame(ACTIVE, 4, 2)
	assert_int(_marked()).is_equal(0)
	_frame(ACTIVE, 3, 2)
	assert_int(_marked()).is_equal(2)


func test_a_dying_zombie_is_not_marked() -> void:
	_frame(ACTIVE, 3, 3, 1)
	assert_int(_marked()).is_equal(2)


func test_it_turns_off_when_the_round_ends() -> void:
	_frame(ACTIVE, 2, 2)
	assert_int(_marked()).is_equal(2)
	_frame(BREAK, 2, 2)
	assert_int(_marked()).is_equal(0)
	for view in _view.horde.views():
		assert_int(_overlays(view)).is_equal(0)


func test_it_turns_off_when_the_count_rises() -> void:
	_frame(ACTIVE, 3, 3)
	_frame(ACTIVE, 9, 3)
	assert_int(_marked()).is_equal(0)


func test_n_is_live_tunable() -> void:
	_frame(ACTIVE, 5, 5)
	assert_int(_marked()).is_equal(0)
	_view.marks.mark_last = 5
	_frame(ACTIVE, 5, 5)
	assert_int(_marked()).is_equal(5)
	_view.marks.mark_last = 0
	_frame(ACTIVE, 5, 5)
	assert_int(_marked()).is_equal(0)


func test_the_switch_turns_it_off_and_on() -> void:
	_frame(ACTIVE, 2, 2)
	_view.marks.enabled = false
	_frame(ACTIVE, 2, 2)
	assert_int(_marked()).is_equal(0)
	_view.marks.enabled = true
	_frame(ACTIVE, 2, 2)
	assert_int(_marked()).is_equal(2)


func test_a_zombie_that_is_gone_takes_no_outline_into_its_next_life() -> void:
	_frame(ACTIVE, 1, 1)
	var view: ZombieView = _view.horde.views()[0]
	assert_bool(view.is_outlined()).is_true()
	_frame(ACTIVE, 1, 0)  # it left: its body is parked
	assert_bool(view.is_outlined()).is_false()
	assert_int(_overlays(view)).is_equal(0)
	_frame(ACTIVE, 9, 1)  # another zombie is given the parked body
	assert_int(_marked()).is_equal(0)
	assert_int(_overlays(_view.horde.views()[0])).is_equal(0)


func test_a_body_that_changes_look_keeps_its_outline() -> void:
	_frame(ACTIVE, 1, 1)
	var view: ZombieView = _view.horde.views()[0]
	view.dress(ZombieModels.scene(&"brute"), &"brute")
	assert_bool(view.is_outlined()).is_true()
	assert_int(_overlays(view)).is_greater(0)


func test_nothing_is_made_for_a_zombie_that_is_never_marked() -> void:
	_frame(ACTIVE, 12, 5)
	for view in _view.horde.views():
		for child in view.get_children():
			assert_bool(child is Outline).is_false()
