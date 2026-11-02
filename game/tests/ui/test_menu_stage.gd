extends GdUnitTestSuite
## The menu's stage built for real: the lot, the soldier in the saved look with the saved weapon,
## the dead on their paths, the camera at every tab, the still level, and the stage screen's keys.

const TEST_PATH := "user://menu_stage_test.cfg"

var _saved_path: String


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()


func after_test() -> void:
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	UIMotion.reduced = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	await RouterFixture.clear(get_tree())


func _view() -> MenuStageView:
	var view := MenuStageView.new()
	view.manual = true
	add_child(view)
	auto_free(view)
	return view


func test_the_stage_has_its_lot_its_hero_and_its_dead() -> void:
	var stage := MenuStage.new()
	add_child(stage)
	auto_free(stage)
	assert_object(stage.hero).is_not_null()
	assert_int(stage.dead.size()).is_equal(MenuStage.DEAD.size())
	assert_object(stage.camera).is_not_null()
	assert_bool(stage.camera.current).is_true()
	# Nothing here needs physics or navigation.
	assert_int(stage.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
	assert_int(stage.find_children("*", "NavigationRegion3D", true, false).size()).is_equal(0)
	assert_int(stage.find_children("*", "CSGShape3D", true, false).size()).is_equal(0)
	assert_int(stage.find_children("*", "Light3D", true, false).size()).is_less_equal(8)


func test_the_hero_wears_the_saved_look_and_holds_the_saved_weapon() -> void:
	var look := CharacterLook.from_preset(3)
	LookStore.save_look(look)
	Settings.set_value(SettingsService.SHOWCASE_WEAPON, "shotgun")
	var view := _view()
	await get_tree().process_frame
	var hero := view.stage.hero
	assert_str(String(hero.weapon_id)).is_equal("shotgun")
	assert_object(hero.weapon).is_not_null()
	assert_object(hero.weapon.get_parent()).is_instanceof(BoneAttachment3D)
	var worn := CharacterLook.from_json(Settings.get_value(SettingsService.CHARACTER_LOOK))
	assert_bool(worn.equals(look)).is_true()


func test_a_weapon_without_a_model_falls_back_to_the_default() -> void:
	Settings.set_value(SettingsService.SHOWCASE_WEAPON, "no_such_gun")
	assert_str(String(MenuHero.saved_weapon())).is_equal(String(MenuHero.DEFAULT_WEAPON))


func test_changing_the_saved_weapon_changes_the_hand() -> void:
	var view := _view()
	await get_tree().process_frame
	Settings.set_value(SettingsService.SHOWCASE_WEAPON, "shotgun")
	assert_str(String(view.stage.hero.weapon_id)).is_equal("shotgun")


func test_the_dead_walk_and_the_same_time_gives_the_same_place() -> void:
	var first := MenuStage.new()
	add_child(first)
	auto_free(first)
	var second := MenuStage.new()
	add_child(second)
	auto_free(second)
	var start := first.dead[0].position
	for _i in 60:
		first.advance(1.0 / 30.0)
		second.advance(1.0 / 30.0)
	assert_float(first.dead[0].position.distance_to(start)).is_greater(0.3)
	assert_vector(first.dead[0].position).is_equal_approx(
		second.dead[0].position, Vector3.ONE * 0.0001
	)
	# Beyond the fence, never in the lot.
	for zombie in first.dead:
		assert_float(zombie.position.z).is_less(MenuStage.FENCE_Z)


func test_the_camera_goes_to_every_tab() -> void:
	var stage := MenuStage.new()
	add_child(stage)
	auto_free(stage)
	var seen := {}
	for tab in MenuTab.ORDER:
		stage.show_tab(tab)
		for _i in 90:
			stage.advance(1.0 / 30.0)
		assert_bool(stage.rig.arrived()).is_true()
		seen[stage.camera.position.snappedf(0.5)] = true
	assert_int(seen.size()).is_equal(MenuTab.ORDER.size())


func test_a_still_draws_once_per_change_and_a_covered_menu_draws_nothing() -> void:
	Settings.set_value(SettingsService.MENU_SCENE, MenuStageView.MODE_STILL)
	var view := _view()
	await get_tree().process_frame
	assert_int(view.level).is_equal(StageGovernor.Level.STILL)
	assert_bool(view.stage.animated).is_false()
	assert_int(view.viewport().render_target_update_mode).is_equal(SubViewport.UPDATE_ONCE)
	var before := view.stage.dead[0].position
	view.show_tab(MenuTab.Id.SHOP)
	# A still cuts to the camera at once and does not move the dead.
	assert_bool(view.stage.rig.arrived()).is_true()
	assert_vector(view.stage.dead[0].position).is_equal(before)
	view.set_active(false)
	assert_int(view.viewport().render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)


func test_a_live_stage_draws_every_frame_and_steps_down_when_told() -> void:
	var view := _view()
	await get_tree().process_frame
	assert_int(view.level).is_equal(StageGovernor.Level.LIVE)
	assert_int(view.viewport().render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)
	view.set_level(StageGovernor.Level.HALF)
	assert_int(view.stretch_shrink).is_equal(2)
	view.set_level(StageGovernor.Level.STILL)
	assert_int(view.viewport().render_target_update_mode).is_equal(SubViewport.UPDATE_ONCE)


func test_reduced_motion_stops_the_dead_and_cuts_the_camera() -> void:
	var view := _view()
	await get_tree().process_frame
	UIMotion.reduced = true
	assert_bool(view.stage.animated).is_false()
	view.show_tab(MenuTab.Id.MORE)
	view.stage.advance(0.016)
	assert_bool(view.stage.rig.arrived()).is_true()


func test_the_stage_screen_walks_the_tabs_with_keys_and_never_takes_the_mouse() -> void:
	UIRouter.reset("res://ui/screens/menu_stage_screen.tscn", UITransition.Kind.CUT)
	await UIRouter.idle
	var screen := UIRouter.top() as MenuStageScreen
	assert_object(screen).is_not_null()
	assert_int(screen.view.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	for press in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_RIGHT
		key.physical_keycode = KEY_RIGHT
		key.pressed = press
		get_viewport().push_input(key)
		await get_tree().process_frame
	assert_int(screen.tab).is_equal(MenuTab.Id.LOADOUT)
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
