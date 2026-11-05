extends GdUnitTestSuite
## The arrival show itself (#1057, `ArrivalCutscene`): it plays through, hands the view back at
## black
## and frees what it built, can be skipped by a press after a moment, puts the player's own look on
## the
## Soldier on the rope, hides what roofs the spot, picks a camera that is not behind a wall, and
## loads
## nothing until it plays.

const STEP := 1.0 / 60.0

var _tuning: ArrivalTuning
var _show: ArrivalCutscene
var _restore: Camera3D
var _finished: Array[bool] = []


func before_test() -> void:
	_tuning = (
		(load(GameRules.DEFAULT_TUNING_PATH) as RulesTuning).arrival.duplicate() as ArrivalTuning
	)
	_restore = Camera3D.new()
	add_child(_restore)
	_restore.make_current()
	_finished = []


func after_test() -> void:
	if is_instance_valid(_show):
		_show.queue_free()
	_restore.queue_free()
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _begin(
	fresh := true, facing := 0.0, hide: Array[Node3D] = [], look: CharacterLook = null
) -> ArrivalCutscene:
	_show = ArrivalCutscene.new()
	_show.self_stepping = false
	add_child(_show)
	_show.finished.connect(func(skipped: bool) -> void: _finished.append(skipped))
	var worn := look if look != null else CharacterLook.from_preset(2)
	_show.begin(_tuning, fresh, Vector3(10.0, 0.0, -4.0), facing, worn, 1, _restore, hide)
	return _show


func _run(seconds: float) -> void:
	for _i in ceili(seconds / STEP):
		_show.advance(STEP)


func test_it_plays_through_and_hands_the_view_back_at_black() -> void:
	_begin()
	assert_object(get_viewport().get_camera_3d()).is_not_same(_restore)
	_run(_tuning.night_seconds - 0.2)
	assert_bool(_show.is_over()).is_false()
	assert_array(_finished).is_empty()
	_run(0.3)
	assert_bool(_show.is_over()).is_true()
	assert_array(_finished).is_equal([false])
	assert_object(get_viewport().get_camera_3d()).is_same(_restore)


func test_a_late_join_plays_the_shorter_show() -> void:
	_begin(false)
	_run(_tuning.late_seconds + 0.05)
	assert_array(_finished).is_equal([false])


func test_what_it_built_is_freed_and_the_black_comes_away() -> void:
	_begin()
	_run(_tuning.night_seconds + 0.1)
	await get_tree().process_frame
	assert_object(_show.soldier()).is_null()
	assert_object(_show.helicopter()).is_null()
	assert_object(_show.find_child("Rope", true, false)).is_null()
	_show.spawn_in()
	_run(ArrivalCutscene.SPAWN_IN_SECONDS + 0.1)
	await get_tree().process_frame
	assert_bool(is_instance_valid(_show)).is_false()


func test_the_black_bars_are_the_shows_and_go_with_it() -> void:
	# The bands a night shows at the top and bottom of a phone page (#1261) are these: deliberate,
	# a share of the picture's height each, there for the show and the 0.45 s after it, never after.
	_begin()
	var cover := _show.find_child("ShowCover", true, false) as CanvasLayer
	assert_object(cover).is_not_null()
	var bars: Array[ColorRect] = []
	for child in cover.get_children():
		var rect := child as ColorRect
		if rect != null and rect.anchor_right == 1.0 and rect.anchor_left == 0.0:
			if rect.anchor_bottom - rect.anchor_top < 0.5:
				bars.append(rect)
	assert_int(bars.size()).is_equal(2)
	for bar in bars:
		assert_float(bar.anchor_bottom - bar.anchor_top).is_equal_approx(
			ArrivalCutscene.BAR_SHARE, 0.0001
		)
	_run(_tuning.night_seconds + 0.1)
	_show.spawn_in()
	_run(ArrivalCutscene.SPAWN_IN_SECONDS + 0.1)
	await get_tree().process_frame
	assert_bool(is_instance_valid(_show)).is_false()
	assert_bool(is_instance_valid(cover)).is_false()


func test_a_press_skips_it_only_after_the_moment_the_tuning_gives() -> void:
	_begin()
	_run(_tuning.skip_after - 0.3)
	assert_bool(_show.skip()).is_false()
	_run(0.4)
	assert_bool(_show.skip()).is_true()
	assert_bool(_show.is_over()).is_false()
	_run(_tuning.fade_out_seconds)
	assert_array(_finished).is_equal([true])


func test_a_key_a_click_a_pad_button_and_a_tap_skip_and_a_look_does_not() -> void:
	for event: InputEvent in [_key(KEY_SPACE), _click(), _pad(), _tap()]:
		_begin()
		_run(_tuning.skip_after + 0.1)
		_show._input(event)
		_run(_tuning.fade_out_seconds)
		assert_array(_finished).is_equal([true])
		_show.free()
		_finished = []
	_begin()
	_run(_tuning.skip_after + 0.1)
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(40, 10)
	_show._input(look)
	var held := _key(KEY_SPACE)
	held.echo = true
	_show._input(held)
	_show._input(_key(KEY_ESCAPE))
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	_show._input(start)
	_run(0.5)
	assert_bool(_show.is_over()).is_false()


func test_a_show_that_cannot_be_skipped_is_not() -> void:
	_tuning.skippable = false
	_begin()
	_run(_tuning.skip_after + 1.0)
	assert_bool(_show.skip()).is_false()
	_show._input(_key(KEY_SPACE))
	_run(0.5)
	assert_bool(_show.is_over()).is_false()


func test_the_soldier_on_the_rope_wears_the_players_look() -> void:
	var worn := CharacterLook.from_preset(5)
	var other := CharacterLook.from_preset(0)
	_begin(true, 0.0, [], worn)
	var model := _show.soldier()
	assert_array(_shown(model)).is_equal(_shown(auto_free(CharacterAssembler.assemble(worn, 1))))
	assert_array(_shown(model)).is_not_equal(
		_shown(auto_free(CharacterAssembler.assemble(other, 1)))
	)
	assert_object(model.find_child(CharacterAssembler.ARMBAND_NAME, true, false)).is_not_null()


func test_he_hangs_by_his_hands_on_the_rope_and_stands_when_he_lands() -> void:
	_begin()
	_run(_tuning.night_seconds * 0.6)
	var skeleton := _show.soldier().find_child("Skeleton3D", true, false) as Skeleton3D
	var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone("UpperArm.L")).origin
	var hand := skeleton.get_bone_global_pose(skeleton.find_bone("Index1.L")).origin
	# The skeleton's space has up for +Z: the hands are well over the shoulders on the rope.
	assert_float(hand.z - shoulder.z).is_greater(0.4)
	_run(_tuning.night_seconds * 0.4 - 0.9)
	shoulder = skeleton.get_bone_global_pose(skeleton.find_bone("UpperArm.L")).origin
	hand = skeleton.get_bone_global_pose(skeleton.find_bone("Index1.L")).origin
	assert_float(hand.z - shoulder.z).is_less(0.2)


func test_what_roofs_the_spot_is_hidden_while_it_plays() -> void:
	var roof := Node3D.new()
	add_child(roof)
	var hidden: Array[Node3D] = [roof]
	_begin(true, 0.0, hidden)
	assert_bool(roof.visible).is_false()
	_run(_tuning.night_seconds + 0.1)
	assert_bool(roof.visible).is_true()
	roof.queue_free()


func test_the_camera_stands_where_a_wall_is_not_between_it_and_the_spot() -> void:
	_begin()
	var free := _show.heading()
	assert_float(free).is_equal_approx(0.0 + ArrivalCutscene.HEADING_TURN, 0.001)
	_show.queue_free()
	# A wall where the preferred camera would stand: the show turns away from it.
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 60.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	var turn := Basis(Vector3.UP, ArrivalCutscene.HEADING_TURN)
	wall.global_position = (
		Vector3(10.0, 0.0, -4.0) + turn * Vector3(0.0, 20.0, _tuning.camera_back * 0.5)
	)
	wall.global_basis = turn
	await get_tree().physics_frame
	await get_tree().physics_frame
	_begin()
	assert_float(absf(angle_difference(_show.heading(), free))).is_greater(0.4)
	wall.queue_free()


func test_the_show_is_small() -> void:
	_begin()
	var meshes := _show.find_children("*", "MeshInstance3D", true, false).filter(
		func(mesh: Node) -> bool: return (mesh as MeshInstance3D).is_visible_in_tree()
	)
	var lights := _show.find_children("*", "Light3D", true, false)
	var json: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/helicopter/helicopter.json")
	)
	# The helicopter (a body and two rotors), the beam, the rope and the Soldier's parts: one lamp.
	assert_int(lights.size()).is_equal(1)
	assert_int(meshes.size()).is_less(24)
	assert_int(int(json["total_tris"])).is_less_equal(int(json["budget"]))


func test_nothing_is_loaded_for_a_night_until_the_show_plays() -> void:
	for id in SoundCatalog.ids_for_night():
		assert_bool(String(SoundCatalog.get_def(id).path_format).contains("/arrival/")).is_false()
	# The warm-up's own list is not called here: naming `WarmupManifest` loads `PlayerAnimation` and
	# the scripts under it, which a test without a night leaves "still in use" at exit and CI fails
	# the shard for. Its source is read instead: it must build the list from the night's ids.
	var manifest := FileAccess.get_file_as_string("res://gameplay/night/warmup/warmup_manifest.gd")
	assert_bool(manifest.contains("SoundCatalog.ids_for_night()")).is_true()
	assert_bool(manifest.contains("SoundCatalog.ids()")).is_false()
	for id in [ArrivalCutscene.SOUND_LOOP, ArrivalCutscene.SOUND_SLIDE, ArrivalCutscene.SOUND_LAND]:
		assert_bool(SoundCatalog.get_def(id).on_demand).is_true()
		assert_bool(SoundCatalog.ids().has(id)).is_true()


func _shown(model: Node) -> Array[String]:
	var out: Array[String] = []
	var meshes := SoldierLook.part_meshes(model)
	for mesh_name: String in meshes:
		if (meshes[mesh_name] as MeshInstance3D).visible:
			out.append(mesh_name)
	out.sort()
	return out


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _pad() -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	return event


func _tap() -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.pressed = true
	return event
