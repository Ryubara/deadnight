extends GdUnitTestSuite
## The client side: a view moves and animates from snapshot entries alone. The zombie model is a
## third-party file that is not committed (a maintainer decides), so these tests run only where it
## has been placed under `res://assets/zombie_kit/`.

const MODEL := "res://assets/zombie_kit/zombie.glb"


func _view() -> ZombieView:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(load(MODEL), 1, 0.25, 0.7)
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
	if not ResourceLoader.exists(MODEL):
		return
	var view := _view()
	view.apply(_entry(ZombieState.Mode.CHASE, 1.0), 0.033)
	assert_vector(view.position).is_equal(Vector3(3, 0, 4))
	assert_float(view.rotation.y).is_equal_approx(1.0, 0.001)


func test_the_mode_picks_the_animation_state() -> void:
	if not ResourceLoader.exists(MODEL):
		return
	var view := _view()
	view.apply(_entry(ZombieState.Mode.CHASE, 2.0), 0.033)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_MOVE)
	view.apply(_entry(ZombieState.Mode.ATTACK, 0.0, 2), 0.033)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_ATTACK)
	view.apply(_entry(ZombieState.Mode.STAGGER, 0.0, 3), 0.033)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_STAGGER)
	view.apply(_entry(ZombieState.Mode.DYING, 0.0, 4), 0.033)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_DIE)


func test_a_zombie_rises_from_the_ground_while_emerging() -> void:
	if not ResourceLoader.exists(MODEL):
		return
	var view := _view()
	view.apply(_entry(ZombieState.Mode.EMERGING), 0.0)
	var model := view.get_child(0) as Node3D
	assert_float(model.position.y).is_less(-1.0)
	view.apply(_entry(ZombieState.Mode.EMERGING), 0.35)
	assert_float(model.position.y).is_between(-1.0, 0.0)
	view.apply(_entry(ZombieState.Mode.CHASE, 1.0, 2), 0.033)
	assert_float(model.position.y).is_equal(0.0)


func test_a_view_has_one_mesh_and_casts_no_shadow() -> void:
	if not ResourceLoader.exists(MODEL):
		return
	var view := _view()
	var meshes := view.find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_equal(1)
	for mesh: MeshInstance3D in meshes:
		assert_int(mesh.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
