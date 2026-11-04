extends GdUnitTestSuite
## A zombie that leaves the lot (killed, 2.5 s after it fell) keeps its body for the next one of its
## look: the model, skeleton, animation player and tree, and the tree's resources, used to be freed
## at every kill and built again at every spawn, in a frame of the night.

const CYCLES := 12
const SLACK := 6

var _horde: ZombieHorde
var _sim: ZombieSim
var _added := 0
var _views_made := 0


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


func _on_node_added(node: Node) -> void:
	_added += 1
	if node is ZombieView:
		_views_made += 1


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
	# Sounds an earlier suite left queued on `Audio` are decoded during the frames below (#1093).
	await AudioSettle.until_idle(get_tree())
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


## `count` walkers stand in a grid; every snapshot is one tick.
func _crowd(count: int) -> Array[ZombieBody]:
	_sim.zombies.clear()
	var crowd: Array[ZombieBody] = []
	for index in count:
		var at := Vector3(float(index % 6) * 1.7, 0.0, float(index / 6) * 1.7)
		crowd.append(ZombieFixture.standing(_sim, index + 1, at, 1.0))
	return crowd


func _cripple(zombies: Array[ZombieBody], count: int) -> void:
	var profile := ZombieProfile.from_type(
		RulesFixture.tuning().roster.type_of(&"crawler"), &"crawler", _sim.tuning
	)
	for index in count:
		zombies[index].profile = profile


func _tick() -> void:
	_horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), 0.03)
	for view in _horde.views():
		view.advance_animation()


func test_a_blast_that_cripples_a_crowd_makes_no_view_when_the_crawlers_are_kept() -> void:
	_horde.prewarm({&"crawler": 20})
	var crowd := _crowd(30)
	_tick()
	_tick()
	var made := _views_made
	_cripple(crowd, 20)
	_tick()
	assert_int(_views_made - made).override_failure_message("views made").is_equal(0)
	assert_int(_horde.view_count()).is_equal(30)
	assert_int((_horde._parked[&"crawler"] as Array).size()).is_equal(0)
	# The crippled walkers' bodies wait for the next walkers.
	assert_int((_horde._parked[&"walker"] as Array).size()).is_equal(12)


func test_the_crippled_keep_their_place_their_gait_and_become_crawling() -> void:
	_horde.prewarm({&"crawler": 20})
	var crowd := _crowd(12)
	_tick()
	_cripple(crowd, 8)
	_tick()
	var entries: Dictionary[int, Dictionary] = {}
	for entry in ZombieCodec.decode(ZombieCodec.encode(_sim.zombies)):
		entries[entry["id"]] = entry
	for index in 12:
		var id := index + 1
		var view := _horde.view_of(id)
		assert_int(view.zombie_id).is_equal(id)
		assert_vector(view.position).is_equal_approx(crowd[index].position, Vector3.ONE * 0.02)
		assert_bool(view.visible).is_true()
		var playback: AnimationNodeStateMachinePlayback = view.tree.get(
			ZombieRig.PLAYBACK_PARAMETER
		)
		var crawling := index < 8
		assert_str(String(view.look)).is_equal("crawler" if crawling else "walker")
		var state := ZombieRig.STATE_CRAWL if crawling else ZombieRig.STATE_MOVE
		assert_str(String(playback.get_current_node())).is_equal(String(state))
		if crawling:
			var rate: float = view.tree.get(ZombieRig.CRAWL_RATE_PARAMETER)
			assert_float(rate).is_equal_approx(
				ZombieRig.gait_rate(&"crawler", entries[id]["speed"]), 0.001
			)
	assert_int(_horde.view_count()).is_equal(12)


func test_without_kept_crawlers_a_blast_makes_one_each_once_and_the_next_blast_makes_none() -> void:
	var crowd := _crowd(8)
	_tick()
	var made := _views_made
	_cripple(crowd, 8)
	_tick()
	assert_int(_views_made - made).is_equal(8)
	# They fall and are gone; their bodies are kept, and another blast uses them.
	_sim.zombies.clear()
	_tick()
	assert_int((_horde._parked[&"crawler"] as Array).size()).is_equal(8)
	var again := _crowd(8)
	_tick()
	made = _views_made
	_cripple(again, 8)
	_tick()
	assert_int(_views_made - made).is_equal(0)


func test_a_crippled_zombie_keeps_its_outline_and_its_saved_animation_time() -> void:
	_horde.prewarm({&"crawler": 2})
	var crowd := _crowd(2)
	_tick()
	var style := OutlineStyle.new()
	_horde.view_of(1).set_outlined(true, style)
	_horde.view_of(1).accumulated = 0.25
	_horde.view_of(1).period = 3
	_cripple(crowd, 1)
	_horde.apply_snapshot(ZombieCodec.encode(_sim.zombies), 0.03)
	var view := _horde.view_of(1)
	assert_str(String(view.look)).is_equal("crawler")
	assert_bool(view.is_outlined()).is_true()
	assert_object(view.outline_style()).is_same(style)
	assert_float(view.accumulated).is_equal_approx(0.25, 0.0001)
	assert_int(view.period).is_equal(3)
	assert_bool(_horde.view_of(2).is_outlined()).is_false()
	# The body it left is plain again for the next walker.
	var left: ZombieView = (_horde._parked[&"walker"] as Array)[0]
	assert_bool(left.is_outlined()).is_false()
	assert_bool(left.visible).is_false()


func test_a_parked_body_is_posed_by_hand_after_a_kept_wait() -> void:
	# The parked tree stays active (switching it off and on loses its resolved tracks): a body
	# that waited still plays its first clip when it is wanted.
	_horde.prewarm({&"crawler": 1})
	var parked: ZombieView = (_horde._parked[&"crawler"] as Array)[0]
	assert_bool(parked.tree.active).is_true()
	var crowd := _crowd(1)
	_tick()
	_cripple(crowd, 1)
	_tick()
	_tick()
	var playback: AnimationNodeStateMachinePlayback = _horde.view_of(1).tree.get(
		ZombieRig.PLAYBACK_PARAMETER
	)
	assert_str(String(playback.get_current_node())).is_equal(String(ZombieRig.STATE_CRAWL))
