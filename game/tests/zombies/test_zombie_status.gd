extends GdUnitTestSuite
## A zombie under a status effect (#788): a frozen one stands still and does not attack, a chilled
## one is slow, a shattered one is gone at once; the snapshot carries the status and a client draws
## it (the shell, the held pose).


func _frozen() -> int:
	return StatusCatalog.get_def(&"frozen").wire


func _chilled() -> int:
	return StatusCatalog.get_def(&"chilled").wire


func test_a_frozen_zombie_stands_still_and_does_not_walk() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	ZombieFixture.run(sim, 1.0, {1: Vector3(20, 0, 0)})
	assert_float(zombie.position.x).is_greater(1.0)
	sim.set_status(1, _frozen(), true, 0.0)
	var held := zombie.position
	ZombieFixture.run(sim, 3.0, {1: Vector3(20, 0, 0)})
	assert_vector(zombie.position).is_equal(held)
	assert_float(zombie.move_speed).is_equal(0.0)
	assert_int(zombie.status).is_equal(_frozen())


func test_a_frozen_zombie_beside_a_player_does_not_swing() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	var targets := {1: Vector3(0.6, 0, 0)}
	sim.set_status(1, _frozen(), true, 0.0)
	var events := ZombieFixture.run(sim, 3.0, targets)
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)
	assert_int(zombie.mode).is_not_equal(ZombieBody.Mode.ATTACK)
	# The same zombie, not frozen, hits.
	var control := ZombieFixture.sim()
	ZombieFixture.standing(control, 1, Vector3.ZERO, 2.0)
	var control_events := ZombieFixture.run(control, 3.0, targets)
	assert_int(ZombieFixture.count(control_events, &"zombie_struck")).is_greater(0)


func test_a_swing_in_the_air_ends_when_the_zombie_is_frozen() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	var targets := {1: Vector3(0.6, 0, 0)}
	ZombieFixture.run(sim, 0.1, targets)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.ATTACK)
	sim.set_status(1, _frozen(), true, 0.0)
	assert_int(zombie.mode).is_equal(ZombieBody.Mode.CHASE)
	var events := ZombieFixture.run(sim, 2.0, targets)
	assert_int(ZombieFixture.count(events, &"zombie_struck")).is_equal(0)


func test_a_zombie_walks_again_when_it_thaws() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO, 2.0)
	sim.set_status(1, _frozen(), true, 0.0)
	ZombieFixture.run(sim, 1.0, {1: Vector3(20, 0, 0)})
	var held := zombie.position
	sim.set_status(1, StatusDef.NONE, false, 1.0)
	ZombieFixture.run(sim, 2.0, {1: Vector3(20, 0, 0)})
	assert_float(zombie.position.x).is_greater(held.x + 2.0)
	assert_int(zombie.status).is_equal(StatusDef.NONE)


func test_a_chilled_zombie_walks_at_half_speed() -> void:
	var fast := ZombieFixture.sim()
	var slow := ZombieFixture.sim()
	var a := ZombieFixture.standing(fast, 1, Vector3.ZERO, 2.0)
	var b := ZombieFixture.standing(slow, 1, Vector3.ZERO, 2.0)
	slow.set_status(1, _chilled(), false, 0.5)
	ZombieFixture.run(fast, 3.0, {1: Vector3(40, 0, 0)})
	ZombieFixture.run(slow, 3.0, {1: Vector3(40, 0, 0)})
	assert_float(b.position.x).is_equal_approx(a.position.x * 0.5, 0.35)
	assert_float(b.position.x).is_greater(0.5)


func test_a_shattered_zombie_is_gone_at_once_with_no_corpse() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3(3, 0, 4), 2.0)
	zombie.yaw = 1.0
	sim.set_status(1, _frozen(), true, 0.0)
	var event := sim.shatter(1)
	assert_str(String(event["type"])).is_equal("zombie_shattered")
	assert_int(event["zombie_id"]).is_equal(1)
	assert_vector(event["position"]).is_equal(Vector3(3, 0, 4))
	assert_float(event["yaw"]).is_equal(1.0)
	assert_str(String(event["look"])).is_equal(String(ZombieModels.DEFAULT))
	assert_float(event["scale"]).is_greater(0.0)
	assert_bool(sim.zombies.has(1)).is_false()
	assert_dict(sim.shatter(1)).is_empty()


func test_a_zombie_the_director_removed_as_shattered_breaks_apart() -> void:
	var rules := RulesFixture.make_rules(1)
	var sim := ZombieFixture.sim()
	var director := ZombieDirector.new(rules, sim, [Vector3.ZERO] as Array[Vector3])
	var broken: Array[Dictionary] = []
	director.zombie_shattered.connect(func(event: Dictionary) -> void: broken.append(event))
	ZombieFixture.standing(sim, 9, Vector3(1, 0, 1))
	director._on_rules_event(
		{"type": &"zombie_removed", "zombie_id": 9, "cause": &"killed", "shattered": true}
	)
	assert_array(broken).has_size(1)
	assert_int(broken[0]["zombie_id"]).is_equal(9)
	assert_bool(sim.zombies.has(9)).is_false()
	# A zombie killed any other way falls and lies a moment.
	ZombieFixture.standing(sim, 10, Vector3(2, 0, 2))
	director._on_rules_event({"type": &"zombie_removed", "zombie_id": 10, "cause": &"killed"})
	assert_array(broken).has_size(1)
	assert_int(sim.zombies[10].mode).is_equal(ZombieBody.Mode.DYING)
	director.close()


# --- The snapshot ---


func test_the_snapshot_carries_each_zombies_status_beside_its_mode() -> void:
	var sim := ZombieFixture.sim()
	var a := ZombieFixture.standing(sim, 1, Vector3(1, 0, 1))
	var b := ZombieFixture.standing(sim, 2, Vector3(2, 0, 2))
	var c := ZombieFixture.standing(sim, 3, Vector3(3, 0, 3))
	a.status = _frozen()
	b.status = _chilled()
	b.mode = ZombieBody.Mode.ATTACK
	b.tearing = true
	var entries := ZombieCodec.decode(ZombieCodec.encode(sim.zombies))
	assert_int(entries.size()).is_equal(3)
	assert_int(entries[0]["status"]).is_equal(_frozen())
	assert_int(entries[0]["mode"]).is_equal(ZombieBody.Mode.CHASE)
	assert_bool(entries[0]["tearing"]).is_false()
	assert_int(entries[1]["status"]).is_equal(_chilled())
	assert_int(entries[1]["mode"]).is_equal(ZombieBody.Mode.ATTACK)
	assert_bool(entries[1]["tearing"]).is_true()
	assert_int(entries[2]["status"]).is_equal(StatusDef.NONE)
	assert_int(c.status).is_equal(StatusDef.NONE)


func test_every_mode_and_every_status_fit_their_bits() -> void:
	assert_int(ZombieBody.Mode.DYING).is_less_equal(ZombieCodec.MODE_MASK)
	assert_int(StatusDef.WIRE_MAX).is_equal(ZombieCodec.STATUS_MASK)
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3.ZERO)
	for mode in ZombieBody.Mode.values():
		for status in range(0, StatusDef.WIRE_MAX + 1):
			zombie.mode = mode
			zombie.status = status
			var entry := ZombieCodec.decode(ZombieCodec.encode(sim.zombies))[0]
			assert_int(entry["mode"]).is_equal(mode)
			assert_int(entry["status"]).is_equal(status)


func test_a_delta_carries_a_zombie_freezing_and_thawing() -> void:
	var sim := ZombieFixture.sim()
	var zombie := ZombieFixture.standing(sim, 1, Vector3(1, 0, 1))
	var base := ZombieDelta.entries_of(ZombieCodec.encode(sim.zombies))
	zombie.status = _frozen()
	var frozen := ZombieDelta.entries_of(ZombieCodec.encode(sim.zombies))
	var delta := ZombieDelta.diff(base, frozen, 1)
	# One zombie, one changed byte: the mode and the episode (two bytes) are all it sends.
	assert_int(delta.size()).is_equal(ZombieDelta.HEADER + 3 + 2)
	var applied := ZombieDelta.apply(base, delta)
	assert_bool(applied["ok"]).is_true()
	var seen := ZombieCodec.decode(ZombieDelta.whole(applied["entries"]))
	assert_int(seen[0]["status"]).is_equal(_frozen())
	zombie.status = StatusDef.NONE
	var thawed := ZombieDelta.entries_of(ZombieCodec.encode(sim.zombies))
	var back := ZombieDelta.apply(frozen, ZombieDelta.diff(frozen, thawed, 2))
	assert_int(ZombieCodec.decode(ZombieDelta.whole(back["entries"]))[0]["status"]).is_equal(0)


func test_the_protocol_is_the_one_that_has_the_status_bits() -> void:
	assert_int(NetWire.VERSION).is_greater_equal(14)
	assert_int(NetWire.MIN_VERSION).is_greater_equal(14)


# --- A client draws it ---


func _view(look: StringName = ZombieModels.DEFAULT) -> ZombieView:
	var view := ZombieView.new()
	add_child(view)
	auto_free(view)
	view.setup(ZombieModels.scene(look), 1, 0.0, 0.7, look)
	return view


func _entry(status: int, mode: int = ZombieBody.Mode.CHASE) -> Dictionary:
	return {
		"id": 1,
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"mode": mode,
		"episode": 0,
		"speed": 1.0,
		"look": ZombieModels.DEFAULT,
		"tearing": false,
		"status": status,
	}


func test_a_frozen_zombie_wears_the_ice_shell_and_a_thawed_one_does_not() -> void:
	var view := _view()
	view.apply(_entry(StatusDef.NONE), 0.0)
	var meshes := view.model().find_children("*", "MeshInstance3D", true, false)
	assert_array(meshes).is_not_empty()
	for mesh: MeshInstance3D in meshes:
		assert_object(mesh.material_overlay).is_null()
	view.apply(_entry(_frozen()), 0.0)
	assert_int(view.status()).is_equal(_frozen())
	for mesh: MeshInstance3D in meshes:
		assert_object(mesh.material_overlay).is_same(StatusLook.shell_for(_frozen()))
	view.apply(_entry(StatusDef.NONE), 0.0)
	for mesh: MeshInstance3D in meshes:
		assert_object(mesh.material_overlay).is_null()


func test_every_zombie_under_a_status_shares_one_shell() -> void:
	assert_object(StatusLook.shell_for(_frozen())).is_same(StatusLook.shell_for(_frozen()))
	assert_object(StatusLook.shell_for(_chilled())).is_not_same(StatusLook.shell_for(_frozen()))
	assert_object(StatusLook.shell_for(StatusDef.NONE)).is_null()


func test_a_frozen_zombie_keeps_its_pose_and_a_thawed_one_moves_again() -> void:
	var view := _view()
	view.apply(_entry(StatusDef.NONE), 0.0)
	view.accumulated = 0.3
	view.advance_animation()
	view.apply(_entry(_frozen()), 0.0)
	assert_bool(view.is_held()).is_true()
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	var position := playback.get_current_play_position()
	view.accumulated = 0.5
	view.advance_animation()
	assert_float(view.accumulated).is_equal(0.0)
	assert_float(playback.get_current_play_position()).is_equal(position)
	view.apply(_entry(StatusDef.NONE), 0.0)
	assert_bool(view.is_held()).is_false()
	view.accumulated = 0.2
	view.advance_animation()
	assert_float(playback.get_current_play_position()).is_not_equal(position)


func test_a_chilled_zombie_is_drawn_in_its_shell_but_is_not_held() -> void:
	var view := _view()
	view.apply(_entry(_chilled()), 0.0)
	assert_bool(view.is_held()).is_false()
	for mesh: MeshInstance3D in view.model().find_children("*", "MeshInstance3D", true, false):
		assert_object(mesh.material_overlay).is_same(StatusLook.shell_for(_chilled()))


func test_a_parked_view_is_not_frozen_when_it_is_used_again() -> void:
	var view := _view()
	view.apply(_entry(_frozen()), 0.0)
	view.park()
	assert_int(view.status()).is_equal(StatusDef.NONE)
	view.setup(ZombieModels.scene(ZombieModels.DEFAULT), 2, 0.0, 0.7, ZombieModels.DEFAULT)
	assert_int(view.status()).is_equal(StatusDef.NONE)
	assert_bool(view.is_held()).is_false()
