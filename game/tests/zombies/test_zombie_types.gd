# The zombie simulation and its client carrying a type: the numbers of the spawn request, the look
# on the wire, hit zones of the type's size, a crippled walker's change of body.
extends GdUnitTestSuite

const STEP := ZombieSim.STEP


func _request(type_id: StringName, rules: GameRules) -> Dictionary:
	var type := rules.tuning.roster.type_of(type_id)
	return {
		"type": &"zombie_spawn_requested",
		"zombie_id": 1,
		"zombie_type": type_id,
		"look": type.looks[0],
		"speed": 1.0,
		"point_roll": 0,
		"damage": type.damage,
		"knockback": type.knockback,
		"telegraph_seconds": type.telegraph_seconds,
		"barrier_speed": type.barrier_speed,
		"hit_chance": type.hit_chance,
	}


func _rules() -> GameRules:
	return RulesFixture.make_rules(1, 3, RulesFixture.tuning())


func test_a_profile_takes_the_numbers_of_the_spawn_request() -> void:
	var rules := _rules()
	var profile := ZombieProfile.from_event(_request(&"brute", rules), ZombieTuning.shipped())
	assert_str(String(profile.type)).is_equal("brute")
	assert_str(String(profile.look)).is_equal("brute")
	assert_float(profile.damage).is_equal(35.0)
	assert_float(profile.knockback).is_equal(2.5)
	assert_float(profile.barrier_speed).is_equal(2.5)
	# No telegraph: the walker's ordinary windup.
	assert_float(profile.windup).is_equal(ZombieTuning.shipped().windup_seconds)


func test_a_telegraph_replaces_the_windup() -> void:
	var rules := _rules()
	var profile := ZombieProfile.from_event(_request(&"headliner", rules), ZombieTuning.shipped())
	assert_float(profile.windup).is_equal(1.2)
	assert_float(profile.damage).is_equal(40.0)


func test_a_request_with_nothing_but_an_id_is_a_plain_zombie() -> void:
	var tuning := ZombieTuning.shipped()
	var profile := ZombieProfile.from_event({"zombie_id": 4}, tuning)
	assert_float(profile.damage).is_equal(tuning.strike_damage)
	assert_float(profile.windup).is_equal(tuning.windup_seconds)
	assert_float(profile.hit_scale()).is_equal(1.0)


func test_the_brain_strikes_with_the_zombies_own_damage_after_its_own_windup() -> void:
	var rules := _rules()
	var sim := ZombieFixture.sim()
	var profile := ZombieProfile.from_event(_request(&"brute", rules), sim.tuning)
	var zombie := sim.spawn(1, 1.0, Vector3.ZERO, 0.0, profile)
	zombie.enter(ZombieBody.Mode.CHASE)
	var targets := {1: Vector3(0.0, 0.0, 1.0)}
	var events := ZombieFixture.run(sim, 1.0, targets)
	var blows := events.filter(func(e: Dictionary) -> bool: return e["type"] == &"zombie_struck")
	assert_int(blows.size()).is_equal(1)
	assert_float(blows[0]["damage"]).is_equal(35.0)
	assert_float(blows[0]["knockback"]).is_equal(2.5)


func test_a_longer_windup_keeps_the_same_recovery() -> void:
	var tuning := ZombieTuning.shipped()
	var profile := ZombieProfile.from_event(_request(&"headliner", _rules()), tuning)
	var sim := ZombieSim.new(tuning, 1)
	var zombie := sim.spawn(1, 1.0, Vector3.ZERO, 0.0, profile)
	zombie.enter(ZombieBody.Mode.CHASE)
	var targets := {1: Vector3(0.0, 0.0, 1.0)}
	var blows: Array[float] = []
	for step in 200:
		var events := sim.tick(STEP, targets)
		if ZombieFixture.count(events, &"zombie_struck") > 0:
			blows.append(float(step + 1) * STEP)
	# The first blow comes when the telegraph is over, not at the walker's 0.45 s ...
	assert_float(blows[0]).is_between(1.2, 1.2 + STEP * 2.0)
	# ... and the next a whole swing later: the telegraph and the recovery the walker has too.
	assert_float(blows[1] - blows[0]).is_between(
		1.2 + tuning.recovery_seconds(), 1.2 + tuning.recovery_seconds() + STEP * 3.0
	)


func test_a_plain_spawn_still_hits_like_the_tuning() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	var events := ZombieFixture.run(sim, 1.0, {1: Vector3(0.0, 0.0, 1.0)})
	var blow := events.filter(func(e: Dictionary) -> bool: return e["type"] == &"zombie_struck")
	assert_float(blow[0]["damage"]).is_equal(sim.tuning.strike_damage)
	assert_float(blow[0]["knockback"]).is_equal(0.0)
	assert_str(String(zombie.look())).is_equal("walker")


func test_the_look_travels_in_the_wire_format() -> void:
	var sim := ZombieFixture.sim()
	for index in ZombieModels.VARIANTS.size():
		var profile := ZombieProfile.plain(sim.tuning)
		profile.look = ZombieModels.VARIANTS[index]
		sim.spawn(index + 1, 1.0, Vector3(index, 0, 0), 0.0, profile)
	var entries := ZombieCodec.decode(ZombieCodec.encode(sim.zombies))
	assert_int(entries.size()).is_equal(ZombieModels.VARIANTS.size())
	for index in entries.size():
		assert_str(String(entries[index]["look"])).is_equal(String(ZombieModels.VARIANTS[index]))


func test_every_look_has_a_model_and_a_height() -> void:
	for look in ZombieModels.VARIANTS:
		assert_object(ZombieModels.scene(look)).is_not_null()
		assert_bool(ZombieModels.HEIGHTS.has(look)).is_true()
	assert_str(ZombieModels.scene(&"headliner").resource_path).ends_with("zombie_boss.glb")
	assert_str(ZombieModels.scene(&"brute").resource_path).ends_with("zombie_brute.glb")


func test_every_look_the_rules_name_is_one_the_artists_made() -> void:
	var roster := RulesFixture.tuning().roster
	for type in roster.types:
		for look in type.looks:
			assert_bool(look in ZombieModels.VARIANTS).is_true()


func test_an_unknown_look_on_the_wire_is_a_walker() -> void:
	assert_str(String(ZombieModels.look_at(250))).is_equal("walker")
	assert_int(ZombieModels.look_index(&"nonsense")).is_equal(0)


func test_hit_zones_follow_the_size_of_the_look_and_its_hit_chance() -> void:
	var rules := _rules()
	var tuning := ZombieTuning.shipped()
	var walker := ZombieProfile.from_event(_request(&"walker", rules), tuning)
	var brute := ZombieProfile.from_event(_request(&"brute", rules), tuning)
	var crawler := ZombieProfile.from_event(_request(&"crawler", rules), tuning)
	assert_float(walker.hit_scale()).is_equal(1.0)
	assert_float(brute.hit_scale()).is_equal(1.18)
	assert_float(crawler.hit_scale()).is_equal_approx(0.6, 0.0001)
	var ray_high := Hitbox.ray(
		Vector3(0, 1.3, 5), Vector3.FORWARD, 10.0, Vector3.ZERO, 0.0, 0.0, 1.0
	)
	var ray_high_crawl := Hitbox.ray(
		Vector3(0, 1.3, 5), Vector3.FORWARD, 10.0, Vector3.ZERO, 0.0, 0.0, crawler.hit_scale()
	)
	assert_bool(ray_high.is_empty()).is_false()
	assert_bool(ray_high_crawl.is_empty()).is_true()
	# A brute's head is higher than a walker's: a ray over the walker's head reaches it.
	var over := Vector3(0, 1.95, 5)
	assert_bool(Hitbox.ray(over, Vector3.FORWARD, 10.0, Vector3.ZERO, 0.0).is_empty()).is_true()
	(
		assert_bool(
			(
				Hitbox
				. ray(over, Vector3.FORWARD, 10.0, Vector3.ZERO, 0.0, 0.0, brute.hit_scale())
				. is_empty()
			)
		)
		. is_false()
	)


func test_the_lag_compensator_keeps_the_zone_size() -> void:
	var lag := LagCompensator.new()
	lag.record(0.0, [{"id": 1, "pos": Vector3.ZERO, "yaw": 0.0, "scale": 0.6}])
	lag.record(0.1, [{"id": 1, "pos": Vector3.ONE, "yaw": 0.0, "scale": 0.6}])
	lag.record(0.2, [{"id": 2, "pos": Vector3.ZERO}])
	assert_float(lag.rewind(0.05, 0.2)["targets"][1]["scale"]).is_equal_approx(0.6, 0.0001)
	assert_float(lag.rewind(0.2, 0.2)["targets"][2]["scale"]).is_equal(1.0)


func test_a_view_changes_body_when_its_look_changes_and_a_crawler_crawls() -> void:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(&"walker"), 1, 0.0, 0.7, &"walker")
	var entry := {
		"id": 1,
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"mode": ZombieBody.Mode.CHASE,
		"episode": 1,
		"speed": 1.0,
		"look": &"walker",
	}
	view.apply(entry, 0.03)
	view.advance_animation()
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	assert_str(String(playback.get_current_node())).is_equal(String(ZombieRig.STATE_MOVE))
	assert_str(view.model().scene_file_path).ends_with("zombie_walker.glb")
	view.dress(ZombieModels.scene(&"crawler"), &"crawler")
	view.apply(entry, 0.03)
	view.advance_animation()
	playback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	assert_str(String(playback.get_current_node())).is_equal(String(ZombieRig.STATE_CRAWL))
	assert_str(view.model().scene_file_path).ends_with("zombie_crawler.glb")
	assert_int(view.get_child_count()).is_equal(1)


func test_the_horde_redresses_a_zombie_whose_look_changes_on_the_wire() -> void:
	var camera := auto_free(Camera3D.new()) as Camera3D
	add_child(camera)
	var horde := ZombieHorde.new()
	add_child(auto_free(horde))
	horde.setup_client(camera, 0.7)
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3(3, 0, 3))
	horde.apply_snapshot(ZombieCodec.encode(sim.zombies), 0.03)
	assert_str(String(horde.view_of(1).look)).is_equal("walker")
	var crawler_type := RulesFixture.tuning().roster.type_of(&"crawler")
	zombie.profile = ZombieProfile.from_type(crawler_type, &"crawler", sim.tuning)
	horde.apply_snapshot(ZombieCodec.encode(sim.zombies), 0.03)
	assert_str(String(horde.view_of(1).look)).is_equal("crawler")
	assert_str(horde.view_of(1).model().scene_file_path).ends_with("zombie_crawler.glb")
	assert_int(horde.view_count()).is_equal(1)


func test_a_blast_that_takes_the_legs_turns_the_walker_into_a_crawler_in_the_simulation() -> void:
	var rules := RulesFixture.make_rules(1, 5, RulesFixture.tuning())
	RulesFixture.into_round_one(rules)
	var sim := ZombieFixture.sim()
	var director := ZombieDirector.new(rules, sim, [Vector3(5, 0, 5)] as Array[Vector3])
	for _i in 600:
		rules.apply(RulesAction.tick(RulesFixture.STEP))
		if sim.zombies.size() > 0:
			break
	assert_int(sim.zombies.size()).is_greater(0)
	var zombie_id: int = sim.zombies.keys()[0]
	var body: ZombieBody = sim.zombies[zombie_id]
	body.enter(ZombieBody.Mode.CHASE)
	var before := body.speed
	var health := rules.zombie_health(zombie_id)
	var victim := {"zombie_id": zombie_id, "damage": health * 0.3, "leg_damage": health * 0.3}
	rules.apply(RulesAction.explosion(1, [victim]))
	assert_str(String(body.profile.type)).is_equal("crawler")
	assert_str(String(body.look())).is_equal("crawler")
	assert_float(body.profile.hit_chance).is_equal(0.6)
	assert_float(body.speed).is_equal_approx(before * 0.35, 0.0001)
	assert_bool(body.crippled).is_true()
	# It does not lose its legs twice.
	sim.cripple(zombie_id, body.profile, 0.35)
	assert_float(body.speed).is_equal_approx(before * 0.35, 0.0001)
	director.close()
