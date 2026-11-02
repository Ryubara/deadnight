# The headliner on the client and in the simulation: the Projectionist model and its clips, the
# roar for an entrance, the attack timed to its telegraph, the stagger, the lamp going dark, and the
# weak spot as a hit zone that staggers it.
extends GdUnitTestSuite

const HEADLINER := &"headliner"
## Where the lamp sits on the boss in a walker's units (`Hitbox.WEAK_ZONE`) at its size.
const SCALE := 1.45


func _view(telegraph: float = ZombieRig.BOSS_HIT_SECONDS) -> ZombieView:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(HEADLINER), 1, 0.0, 0.7, HEADLINER, telegraph)
	return view


func _entry(mode: int, speed: float = 0.0, episode: int = 1) -> Dictionary:
	return {
		"id": 1,
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"mode": mode,
		"episode": episode,
		"speed": speed,
		"look": HEADLINER,
	}


func _state(view: ZombieView) -> StringName:
	view.advance_animation()
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	return playback.get_current_node()


func _boss_request() -> Dictionary:
	var rules := RulesFixture.make_rules(1, 3, RulesFixture.tuning())
	var type := rules.tuning.roster.type_of(HEADLINER)
	return {
		"zombie_id": 1,
		"zombie_type": HEADLINER,
		"look": HEADLINER,
		"boss": true,
		"damage": type.damage,
		"knockback": type.knockback,
		"telegraph_seconds": type.telegraph_seconds,
		"barrier_speed": type.barrier_speed,
		"hit_chance": type.hit_chance,
	}


func _boss_sim(tuning: ZombieTuning) -> ZombieSim:
	var profile := ZombieProfile.from_event(_boss_request(), tuning)
	profile.weak = true
	var sim := ZombieSim.new(tuning, 1)
	sim.spawn(1, 1.0, Vector3.ZERO, 0.0, profile).enter(ZombieBody.Mode.CHASE)
	return sim


func _lamp_at(position: Vector3, yaw: float) -> Vector3:
	return position + Basis(Vector3.UP, yaw) * (Hitbox.WEAK_ZONE["a"] as Vector3) * SCALE


func test_the_headliner_wears_the_projectionist_and_carries_its_five_clips() -> void:
	var view := _view()
	assert_str(view.model().scene_file_path).ends_with("zombie_boss.glb")
	var player := view.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in ["Boss_Walk", "Boss_Attack", "Boss_Roar", "Boss_Stagger", "Boss_Death"]:
		assert_bool(player.has_animation("%s/%s" % [ZombieRig.BOSS_LIBRARY, clip])).is_true()
	# The boss's clips are not the commons': it has a library of its own.
	assert_bool(player.has_animation_library(ZombieRig.LIBRARY)).is_false()


func test_the_models_are_drawn_at_game_scale() -> void:
	for look in [&"walker", &"headliner"]:
		var view := ZombieView.new()
		add_child(auto_free(view))
		view.setup(ZombieModels.scene(look), 1, 0.0, 0.7, look)
		assert_float(view.model().scale.y).is_equal_approx(ZombieModels.GAME_SCALE, 0.0001)


func test_the_boss_roars_on_entrance_walks_attacks_staggers_and_dies() -> void:
	var view := _view()
	view.apply(_entry(ZombieBody.Mode.EMERGING), 0.0)
	assert_str(String(_state(view))).is_equal(String(ZombieRig.STATE_ROAR))
	view.apply(_entry(ZombieBody.Mode.CHASE, 1.0, 2), 0.03)
	assert_str(String(_state(view))).is_equal(String(ZombieRig.STATE_MOVE))
	view.apply(_entry(ZombieBody.Mode.ATTACK, 0.0, 3), 0.03)
	assert_str(String(_state(view))).is_equal(String(ZombieRig.STATE_ATTACK))
	view.apply(_entry(ZombieBody.Mode.STAGGER, 0.0, 4), 0.03)
	assert_str(String(_state(view))).is_equal(String(ZombieRig.STATE_STAGGER))
	view.apply(_entry(ZombieBody.Mode.DYING, 0.0, 5), 0.03)
	assert_str(String(_state(view))).is_equal(String(ZombieRig.STATE_DIE))


func test_the_boss_does_not_sink_into_the_ground_while_it_roars() -> void:
	var view := _view()
	view.apply(_entry(ZombieBody.Mode.EMERGING), 0.0)
	assert_float(view.model().position.y).is_equal(0.0)


func test_the_attack_clip_is_played_so_its_blow_lands_on_the_telegraph() -> void:
	var view := _view(1.2)
	view.apply(_entry(ZombieBody.Mode.ATTACK, 0.0, 2), 0.03)
	var rate: float = view.tree.get(ZombieRig.BOSS_ATTACK_SCALE_PARAMETER)
	assert_float(rate).is_equal_approx(ZombieRig.BOSS_HIT_SECONDS / 1.2, 0.0001)
	# Played at that speed the clip's hit event (frame 32) is 1.2 s in.
	assert_float(ZombieRig.BOSS_HIT_SECONDS / rate).is_equal_approx(1.2, 0.0001)


func test_the_lamp_burns_until_the_boss_dies_and_the_models_material_is_left_alone() -> void:
	var view := _view()
	var near := view.find_child(ZombieModels.NEAR_MESH, true, false) as MeshInstance3D
	var shared := near.mesh.surface_get_material(0) as StandardMaterial3D
	var strength := shared.emission_energy_multiplier
	assert_float(strength).is_greater(0.0)
	var lamp := near.material_override as StandardMaterial3D
	assert_object(lamp).is_not_null()
	assert_float(lamp.emission_energy_multiplier).is_equal(strength)
	view.apply(_entry(ZombieBody.Mode.CHASE, 1.0), 0.03)
	assert_float(lamp.emission_energy_multiplier).is_equal(strength)
	view.apply(_entry(ZombieBody.Mode.DYING, 0.0, 2), 0.03)
	assert_float(lamp.emission_energy_multiplier).is_equal(0.0)
	assert_float(shared.emission_energy_multiplier).is_equal(strength)
	# The far mesh shows the same dark lamp.
	var far := view.find_child(ZombieModels.FAR_MESH, true, false) as MeshInstance3D
	assert_object(far.material_override).is_same(lamp)


func test_two_bosses_do_not_share_a_lamp() -> void:
	var a := _view()
	var b := _view()
	a.apply(_entry(ZombieBody.Mode.DYING, 0.0, 2), 0.03)
	var near_b := b.find_child(ZombieModels.NEAR_MESH, true, false) as MeshInstance3D
	var lamp_b := near_b.material_override as StandardMaterial3D
	assert_float(lamp_b.emission_energy_multiplier).is_greater(0.0)


func test_the_boss_roars_for_its_entrance_before_it_chases() -> void:
	var tuning := ZombieTuning.shipped()
	var profile := ZombieProfile.from_event(_boss_request(), tuning)
	assert_float(profile.emerge).is_equal(tuning.boss_entrance_seconds)
	var sim := ZombieSim.new(tuning, 1)
	var zombie := sim.spawn(1, 1.0, Vector3.ZERO, 0.0, profile)
	ZombieFixture.run(sim, 2.0, {1: Vector3(8.0, 0.0, 0.0)})
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.EMERGING)
	ZombieFixture.run(sim, 1.0, {1: Vector3(8.0, 0.0, 0.0)})
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.CHASE)


# --- The weak spot ---


func test_the_weak_spot_is_a_zone_only_a_zombie_with_one_has() -> void:
	var lamp := _lamp_at(Vector3.ZERO, 0.0)
	var from_front := Vector3(0.0, lamp.y, 6.0)
	var dir := Vector3.FORWARD
	var with_it := Hitbox.ray(from_front, dir, 10.0, Vector3.ZERO, 0.0, 0.0, SCALE, true)
	assert_str(String(with_it["zone"])).is_equal("weak")
	var without := Hitbox.ray(from_front, dir, 10.0, Vector3.ZERO, 0.0, 0.0, SCALE)
	assert_str(String(without["zone"])).is_not_equal("weak")


func test_the_weak_spot_is_on_the_front_and_hidden_from_behind() -> void:
	var height := _lamp_at(Vector3.ZERO, 0.0).y
	var eye := Vector3(0.0, height, -6.0)
	var behind := Hitbox.ray(eye, Vector3.BACK, 10.0, Vector3.ZERO, 0.0, 0.0, SCALE, true)
	assert_bool(behind.is_empty()).is_false()
	assert_str(String(behind["zone"])).is_not_equal("weak")
	# Turned round, the same ray from the same side finds the lamp.
	var turned := Hitbox.ray(eye, Vector3.BACK, 10.0, Vector3.ZERO, PI, 0.0, SCALE, true)
	assert_str(String(turned["zone"])).is_equal("weak")


func test_the_weak_spot_moves_with_the_boss() -> void:
	var at := Vector3(10.0, 0.0, -4.0)
	var yaw := PI * 0.5
	var lamp := _lamp_at(at, yaw)
	var eye := lamp + Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 5.0)
	var hit := Hitbox.ray(eye, (lamp - eye).normalized(), 10.0, at, yaw, 0.0, SCALE, true)
	assert_str(String(hit["zone"])).is_equal("weak")


func test_a_weak_spot_hit_staggers_the_boss_with_a_cooldown() -> void:
	var tuning := ZombieTuning.shipped()
	var sim := _boss_sim(tuning)
	var zombie := sim.zombies[1]
	var far := {1: Vector3(20.0, 0.0, 0.0)}
	sim.weak_hit(1)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.STAGGER)
	ZombieFixture.run(sim, tuning.boss_stagger_seconds + 0.1, far)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.CHASE)
	# Inside the cooldown the lamp does not hold it still again ...
	sim.weak_hit(1)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.CHASE)
	# ... after it, it does.
	ZombieFixture.run(sim, tuning.boss_stagger_cooldown, far)
	sim.weak_hit(1)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.STAGGER)


func test_a_weak_spot_hit_on_a_zombie_without_one_does_nothing() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	sim.weak_hit(1)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.CHASE)


func test_a_stagger_loses_the_boss_its_swing() -> void:
	var sim := _boss_sim(ZombieTuning.shipped())
	var zombie := sim.zombies[1]
	var targets := {1: Vector3(0.0, 0.0, 1.0)}
	ZombieFixture.run(sim, 0.8, targets)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.ATTACK)
	sim.weak_hit(1)
	var events := ZombieFixture.run(sim, 1.0, targets)
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)
