extends GdUnitTestSuite
## A crawler attacks from the floor (#971): it used to play the walker's standing `Punch`, so its
## body rose to the height of a walker to strike and dropped again. It has an attack of its own now:
## a clip that coils on the arms, throws the body along the floor and grabs at the ankles; a reach
## shorter than the walker's, a longer telegraph; and a body that never leaves the crawl's height.

## The most a crawler's highest point may stand over what its own crawl reaches, metres.
const CRAWL_TOP_SLACK := 0.05
## The same over the highest bone of the skeleton in the night (a raised hand's fingertips count).
const BONE_SLACK := 0.1
## Moments sampled in a clip.
const SAMPLES := 40


func _crawler_type() -> ZombieType:
	return RulesFixture.tuning().roster.type_of(&"crawler")


func _crawler_sim(at: Vector3 = Vector3.ZERO) -> ZombieSim:
	var sim := ZombieFixture.sim()
	var profile := ZombieProfile.from_type(_crawler_type(), &"crawler", sim.tuning)
	var zombie := sim.spawn(1, 0.0, at, 0.0, profile)
	zombie.enter(ZombieBody.Mode.CHASE)
	return sim


func _view(look: StringName) -> ZombieView:
	var view := ZombieView.new()
	add_child(auto_free(view))
	var telegraph := _crawler_type().telegraph_seconds
	view.setup(ZombieModels.scene(look), 1, 0.0, 0.7, look, telegraph)
	return view


func _entry(look: StringName, mode: int) -> Dictionary:
	return {
		"id": 1,
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"mode": mode,
		"episode": 1,
		"speed": 0.0,
		"look": look,
	}


func _playback(view: ZombieView) -> AnimationNodeStateMachinePlayback:
	return view.tree.get(ZombieRig.PLAYBACK_PARAMETER)


# --- The type: its own reach and telegraph ---


func test_the_crawler_has_its_own_reach_and_a_longer_telegraph_than_the_walker() -> void:
	var tuning := ZombieTuning.shipped()
	var type := _crawler_type()
	assert_float(type.reach).is_greater(0.0)
	assert_float(type.reach).is_less(tuning.reach)
	assert_float(type.telegraph_seconds).is_greater(tuning.windup_seconds)
	var crawler := ZombieProfile.from_type(type, &"crawler", tuning)
	assert_float(crawler.reach_in(tuning)).is_equal(type.reach)
	assert_float(crawler.windup).is_equal(type.telegraph_seconds)
	var walker_type := RulesFixture.tuning().roster.type_of(&"walker")
	var walker := ZombieProfile.from_type(walker_type, &"walker", tuning)
	assert_float(walker.reach_in(tuning)).is_equal(tuning.reach)
	assert_float(walker.windup).is_equal(tuning.windup_seconds)


func test_a_crawler_starts_its_swing_inside_its_own_reach_and_not_at_the_walkers() -> void:
	var type := _crawler_type()
	var tuning := ZombieTuning.shipped()
	# Out past its own reach, inside the walker's: no swing.
	var sim := _crawler_sim()
	var out := Vector3(0.0, 0.0, (type.reach + tuning.reach) * 0.5)
	assert_float(out.z).is_less(tuning.reach)
	ZombieFixture.run(sim, 0.3, {7: out})
	assert_int(sim.zombies[1].mode).is_equal(ZombieBody.Mode.CHASE)
	# Inside it: it swings.
	sim = _crawler_sim()
	ZombieFixture.run(sim, 0.2, {7: Vector3(0.0, 0.0, type.reach - 0.1)})
	assert_int(sim.zombies[1].mode).is_equal(ZombieBody.Mode.ATTACK)


func test_the_crawlers_blow_lands_on_its_telegraph_with_its_own_damage() -> void:
	var type := _crawler_type()
	var sim := _crawler_sim()
	var targets := {7: Vector3(0.0, 0.0, type.reach - 0.1)}
	var before := ZombieFixture.run(sim, type.telegraph_seconds - 0.1, targets)
	assert_int(ZombieFixture.count(before, &"zombie_struck")).is_equal(0)
	var landing := ZombieFixture.run(sim, 0.2, targets)
	assert_int(ZombieFixture.count(landing, &"zombie_struck")).is_equal(1)
	var strikes := landing.filter(func(e: Dictionary) -> bool: return e["type"] == &"zombie_struck")
	assert_float(strikes[0]["damage"]).is_equal(type.damage)
	assert_float(strikes[0]["knockback"]).is_equal(0.0)


func test_the_blow_reaches_as_far_as_the_grab_does_and_no_further() -> void:
	var type := _crawler_type()
	var slack := ZombieTuning.shipped().strike_slack
	var landed := _lands_at(type.reach + slack - 0.05)
	var missed := _lands_at(type.reach + slack + 0.3)
	assert_bool(landed).is_true()
	assert_bool(missed).is_false()


## Whether a blow lands on a target `apart` metres away when the swing starts inside the reach and
## the target steps back to `apart` before it lands.
func _lands_at(apart: float) -> bool:
	var type := _crawler_type()
	var sim := _crawler_sim()
	ZombieFixture.run(sim, 0.1, {7: Vector3(0.0, 0.0, type.reach - 0.1)})
	var events := ZombieFixture.run(
		sim, type.telegraph_seconds + 0.2, {7: Vector3(0.0, 0.0, apart)}
	)
	return ZombieFixture.count(events, &"zombie_struck") == 1


# --- The clip: low, and as long as the reach says ---


func test_the_attack_clip_never_rises_above_the_crawls_own_height() -> void:
	var probe := ZombieMeshProbe.make(self, &"crawler")
	probe.use_extra_clips()
	var crawl_top := _top_of(probe, &"Crawl")
	var attack_top := _top_of(probe, &"extra/Crawl_Attack")
	assert_float(attack_top).is_less_equal(crawl_top + CRAWL_TOP_SLACK)
	# The walker's punch on this body is what it used to play: more than twice as high.
	assert_float(_top_of(probe, &"Punch")).is_greater(crawl_top * 2.0)
	probe.free_model()


func test_the_grab_reaches_to_the_edge_of_the_blow() -> void:
	var probe := ZombieMeshProbe.make(self, &"crawler")
	probe.use_extra_clips()
	probe.pose(&"extra/Crawl_Attack", ZombieRig.CRAWL_HIT_SECONDS)
	var fingertips := probe.bounds().end.z
	var edge := _crawler_type().reach + ZombieTuning.shipped().strike_slack
	assert_float(fingertips).is_between(edge - 0.2, edge + 0.2)
	probe.free_model()


func _top_of(probe: ZombieMeshProbe, clip: StringName) -> float:
	var top := 0.0
	var length := probe.length_of(clip)
	for i in SAMPLES:
		probe.pose(clip, length * float(i) / float(SAMPLES))
		top = maxf(top, probe.bounds().end.y)
	return top


# --- The view: which clip, and when the grab lands ---


func test_a_crawler_that_swings_plays_its_own_clip_and_a_walker_the_punch() -> void:
	var crawler := _view(&"crawler")
	crawler.apply(_entry(&"crawler", ZombieBody.Mode.ATTACK), 0.016)
	crawler.advance_animation()
	assert_str(String(_playback(crawler).get_current_node())).is_equal("crawl_attack")
	var walker := _view(&"walker")
	walker.apply(_entry(&"walker", ZombieBody.Mode.ATTACK), 0.016)
	walker.advance_animation()
	assert_str(String(_playback(walker).get_current_node())).is_equal("attack")


func test_the_grab_lands_on_the_types_telegraph_in_the_clip() -> void:
	var telegraph := _crawler_type().telegraph_seconds
	var view := _view(&"crawler")
	view.apply(_entry(&"crawler", ZombieBody.Mode.ATTACK), 0.016)
	var steps := roundi(telegraph / ZombieSim.STEP)
	for _i in steps:
		view.tree.advance(ZombieSim.STEP)
	var at := _playback(view).get_current_play_position()
	# The clip's own seconds: the grab frame is where it has got to when the telegraph is over.
	assert_float(at).is_equal_approx(ZombieRig.CRAWL_HIT_SECONDS, 0.04)


func test_the_attack_ends_back_in_the_crawl() -> void:
	var view := _view(&"crawler")
	view.apply(_entry(&"crawler", ZombieBody.Mode.ATTACK), 0.016)
	view.apply(_entry(&"crawler", ZombieBody.Mode.CHASE), 0.016)
	view.advance_animation()
	assert_str(String(_playback(view).get_current_node())).is_equal("crawl")


# --- The real night: the body stays down while it attacks ---


func test_a_crawler_in_the_real_night_never_rises_above_its_crawl_while_it_attacks() -> void:
	var night := await NightFixture.start(
		self, Night.Mode.MANUAL, NightFixture.only_tuning(&"crawler"), 7
	)
	night.view.horde.throttle.set_process(false)
	var id := NightFixture.first_of_type(night, &"crawler")
	assert_int(id).is_greater_equal(0)
	var body: ZombieBody = night.server.sim.zombies[id]
	var player_at := night.state.position()
	body.position = Vector3(player_at.x, body.position.y, player_at.z - 3.0)
	var crawl_top := 0.0
	var attack_top := 0.0
	var attacking := 0
	for _i in 900:
		night.tick()
		var view := night.view.horde.view_of(id)
		if view == null or body.mode == ZombieBody.Mode.EMERGING:
			continue
		view.accumulated = Night.STEP
		view.advance_animation()
		var top := _highest_bone(view)
		if body.mode == ZombieBody.Mode.ATTACK:
			attacking += 1
			attack_top = maxf(attack_top, top)
		elif body.mode == ZombieBody.Mode.CHASE:
			crawl_top = maxf(crawl_top, top)
		if night.server.rules.health_of(1) < 70.0:
			break
	assert_int(attacking).override_failure_message("it never swung").is_greater(20)
	(
		assert_float(night.server.rules.health_of(1))
		. override_failure_message("no blow landed")
		. is_less(100.0)
	)
	assert_float(crawl_top).is_greater(0.0)
	(
		assert_float(attack_top)
		. override_failure_message(
			"its body rose to %.2f m in the swing (%.2f m crawling)" % [attack_top, crawl_top]
		)
		. is_less_equal(crawl_top + BONE_SLACK)
	)
	night.queue_free()


## The highest a bone of the view's skeleton stands over the zombie's feet, metres.
func _highest_bone(view: ZombieView) -> float:
	var skeleton := view.model().find_child("Skeleton3D", true, false) as Skeleton3D
	var top := -INF
	for bone in skeleton.get_bone_count():
		var at := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		top = maxf(top, at.y - view.global_position.y)
	return top
