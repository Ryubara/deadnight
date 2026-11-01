extends GdUnitTestSuite
## A zombie that leaves the lot (killed, 2.5 s after it fell) keeps its body for the next one of its
## look: the model, skeleton, animation player and tree, and the tree's resources, used to be freed
## at every kill and built again at every spawn, in a frame of the night.

const CYCLES := 12
const SLACK := 6

var _horde: ZombieHorde
var _sim: ZombieSim
var _added := 0


func before_test() -> void:
	var camera := auto_free(Camera3D.new()) as Camera3D
	add_child(camera)
	_horde = auto_free(ZombieHorde.new())
	add_child(_horde)
	_horde.setup_client(camera, 0.7)
	_sim = ZombieFixture.sim()
	get_tree().node_added.connect(_on_node_added)


func after_test() -> void:
	get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(_node: Node) -> void:
	_added += 1


## One zombie of `look` stands at `at` for a few snapshots, then is gone from the next.
func _life(zombie_id: int, look: StringName, at: Vector3) -> void:
	_sim.zombies.clear()
	var zombie := ZombieFixture.standing(_sim, zombie_id, at)
	if look != ZombieModels.DEFAULT:
		var type := RulesFixture.tuning().roster.type_of(look)
		zombie.profile = ZombieProfile.from_type(type, look, _sim.tuning)
	for _i in 3:
		_horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), 0.03)
		await get_tree().process_frame
	_sim.zombies.clear()
	_horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), 0.03)
	await get_tree().process_frame


func test_the_bodies_of_zombies_that_left_are_used_again_not_made_again() -> void:
	await _life(1, &"walker", Vector3(3, 0, 3))
	var nodes_before := _added
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	for id in range(2, 2 + CYCLES):
		await _life(id, &"walker", Vector3(id, 0, 3))
	assert_int(_added - nodes_before).override_failure_message("nodes made").is_equal(0)
	# The test's own bookkeeping may hold a few objects; a body made again holds dozens.
	var now_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	assert_int(now_objects - objects).override_failure_message("objects").is_less_equal(SLACK)
	var now_resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	assert_int(now_resources - resources).override_failure_message("resources").is_less_equal(SLACK)
	assert_int(_horde.view_count()).is_equal(0)


func test_a_reused_body_starts_over_in_the_new_zombies_place_and_mode() -> void:
	await _life(1, &"walker", Vector3(3, 0, 3))
	ZombieFixture.standing(_sim, 2, Vector3(-4, 0, 6))
	_horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), 0.03)
	var view := _horde.view_of(2)
	assert_bool(view.visible).is_true()
	assert_vector(view.position).is_equal_approx(Vector3(-4, 0, 6), Vector3.ONE * 0.02)
	assert_int(view.zombie_id).is_equal(2)
	assert_str(String(view.look)).is_equal("walker")
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	view.advance_animation()
	assert_str(String(playback.get_current_node())).is_equal(String(ZombieRig.STATE_MOVE))


func test_a_parked_body_draws_nothing_and_a_look_keeps_to_its_own_bodies() -> void:
	await _life(1, &"walker", Vector3(3, 0, 3))
	var parked: Array = _horde._parked[&"walker"]
	assert_int(parked.size()).is_equal(1)
	assert_bool((parked[0] as ZombieView).visible).is_false()
	# A crawler does not take the walker's body.
	var nodes_before := _added
	await _life(2, &"crawler", Vector3(5, 0, 5))
	(
		assert_int(_added - nodes_before)
		. override_failure_message("a new look makes a body")
		. is_greater(4)
	)
	assert_int((_horde._parked[&"walker"] as Array).size()).is_equal(1)
	assert_int((_horde._parked[&"crawler"] as Array).size()).is_equal(1)


func test_no_more_bodies_are_kept_than_the_limit() -> void:
	_sim.zombies.clear()
	var count := ZombieHorde.PARKED_PER_LOOK + 3
	for id in count:
		ZombieFixture.standing(_sim, id + 1, Vector3(id, 0, 3))
	_horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), 0.03)
	assert_int(_horde.view_count()).is_equal(count)
	_sim.zombies.clear()
	_horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), 0.03)
	assert_int((_horde._parked[&"walker"] as Array).size()).is_equal(ZombieHorde.PARKED_PER_LOOK)
