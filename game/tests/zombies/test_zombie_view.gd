extends GdUnitTestSuite
## The client side: a view moves and animates from snapshot entries alone, on the committed
## zombie variants (ZombieModels).


func _view() -> ZombieView:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(), 1, 0.25, 0.7)
	return view


func _entry(mode: int, speed: float = 0.0, episode: int = 1) -> Dictionary:
	return {
		"id": 1,
		"position": Vector3(3, 0, 4),
		"yaw": 1.0,
		"mode": mode,
		"episode": episode,
		"speed": speed,
	}


func _state(view: ZombieView) -> StringName:
	view.advance_animation()
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	return playback.get_current_node()


func test_a_view_stands_where_the_entry_says() -> void:
	var view := _view()
	view.apply(_entry(ZombieBody.Mode.CHASE, 1.0), 0.033)
	assert_vector(view.position).is_equal(Vector3(3, 0, 4))
	assert_float(view.rotation.y).is_equal_approx(1.0, 0.001)


func test_the_mode_picks_the_animation_state() -> void:
	var view := _view()
	view.apply(_entry(ZombieBody.Mode.CHASE, 2.0), 0.033)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_MOVE)
	view.apply(_entry(ZombieBody.Mode.ATTACK, 0.0, 2), 0.033)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_ATTACK)
	view.apply(_entry(ZombieBody.Mode.STAGGER, 0.0, 3), 0.033)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_STAGGER)
	view.apply(_entry(ZombieBody.Mode.DYING, 0.0, 4), 0.033)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_DIE)


func test_a_zombie_rises_from_the_ground_while_emerging() -> void:
	var view := _view()
	view.apply(_entry(ZombieBody.Mode.EMERGING), 0.0)
	var model := view.get_child(0) as Node3D
	assert_float(model.position.y).is_less(-1.0)
	view.apply(_entry(ZombieBody.Mode.EMERGING), 0.35)
	assert_float(model.position.y).is_between(-1.0, 0.0)
	view.apply(_entry(ZombieBody.Mode.CHASE, 1.0, 2), 0.033)
	assert_float(model.position.y).is_equal(0.0)


func test_a_view_draws_one_mesh_at_a_time_and_casts_no_shadow() -> void:
	var view := _view()
	var near := view.find_child(ZombieModels.NEAR_MESH, true, false) as MeshInstance3D
	var far := view.find_child(ZombieModels.FAR_MESH, true, false) as MeshInstance3D
	assert_object(near).is_not_null()
	assert_object(far).is_not_null()
	assert_float(near.visibility_range_begin).is_equal(0.0)
	assert_float(near.visibility_range_end).is_equal(ZombieModels.FAR_FROM)
	assert_float(far.visibility_range_begin).is_equal(ZombieModels.FAR_FROM)
	assert_float(far.visibility_range_end).is_equal(0.0)
	var meshes := view.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_equal(2)
	for mesh: MeshInstance3D in meshes:
		assert_int(mesh.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_every_variant_plays_the_shared_library() -> void:
	for variant in ZombieModels.VARIANTS:
		var view := ZombieView.new()
		add_child(auto_free(view))
		view.setup(ZombieModels.scene(variant), 1, 0.0, 0.7)
		view.apply(_entry(ZombieBody.Mode.CHASE, 2.0), 0.033)
		assert_str(_state(view)).is_equal(ZombieRig.STATE_MOVE)
		var player := view.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for clip in ZombieRig.CLIPS:
			assert_bool(player.has_animation("%s/%s" % [ZombieRig.LIBRARY, clip])).is_true()


func test_a_variant_name_picks_its_file() -> void:
	assert_str(ZombieModels.scene(&"walker").resource_path).ends_with("zombie_walker.glb")
	assert_str(ZombieModels.scene(&"brute").resource_path).ends_with("zombie_brute.glb")
