# The look of a shot in the toon style (docs/design/shot-feedback.md): a flash of a few frames on
# the weapon's muzzle point, and the shake of the shooter's own view. Frames are counted by hand:
# no wall time. The impacts are in test_impact_fx.gd.
extends GdUnitTestSuite

const TEST_ROOM := "res://world/test_room.tscn"
const SHOOTER := WeaponsFixture.SHOOTER
const BODY := Vector3(0, 1.1, 0)
const TICK := 1.0 / 60.0

var _player: Player
var _animation: PlayerAnimation
var _effects: ShotEffects
var _camera: Camera3D


func before_test() -> void:
	var runner := scene_runner(TEST_ROOM)
	_player = runner.find_child("Player") as Player
	_player.capture_mouse = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_camera = auto_free(Camera3D.new())
	add_child(_camera)
	_camera.position = Vector3(0.0, 1.5, 6.0)
	_camera.make_current()
	_effects = auto_free(ShotEffects.new())
	add_child(_effects)


func _def(id: StringName) -> WeaponDef:
	return WeaponCatalog.get_def(id)


## The events of one shot of `id` at a zombie standing at the origin.
func _shot_event(id: StringName) -> Dictionary:
	var server := WeaponsFixture.make_server()
	server.apply(CombatAction.give_weapon(1, id))
	WeaponsFixture.step(server, {1: Vector3.ZERO}, 2)
	var events := server.apply(WeaponsFixture.fire_at(1, 1, SHOOTER, BODY, server.now))
	return WeaponsFixture.of(events, &"shot_fired")[0]


func _view(state: ClientState) -> NightView:
	var view: NightView = auto_free(NightView.new())
	add_child(view)
	view.setup(state, _camera)
	view.bodies = func(_id: int) -> Player: return _player
	return view


func _frames(flash: MuzzleFlash, count: int) -> void:
	for i in count:
		flash._process(TICK)


# --- the muzzle point ---


func test_the_weapon_in_hand_has_a_muzzle_point_at_the_end_of_its_barrel() -> void:
	_animation.equip(&"Rifle")
	var marker := _animation.muzzle_point()
	assert_object(marker).is_not_null()
	var hold := _animation.weapon_hold()
	var weapon := _animation.weapon()
	assert_vector(marker.global_position).is_equal_approx(
		weapon.to_global(hold.muzzle), Vector3.ONE * 0.0001
	)
	# -Z of the marker runs out of the barrel, which is the model's -X.
	var barrel := (-marker.global_basis.z).normalized()
	var model_forward := -weapon.global_basis.x.normalized()
	assert_vector(barrel).is_equal_approx(model_forward, Vector3.ONE * 0.001)


func test_a_class_with_no_model_has_no_muzzle_point() -> void:
	_animation.equip(&"Pistol")
	assert_object(_animation.muzzle_point()).is_null()


# --- the flash ---


func test_the_flash_appears_on_the_muzzle_point_and_is_gone_within_its_frames() -> void:
	_animation.equip(&"Rifle")
	var marker := _animation.muzzle_point()
	_effects.shot(_def(&"rifle"), marker.global_position, [Vector3(0, 1, -5)], [], marker)
	var flash := marker.get_node(NodePath(MuzzleFlash.NODE_NAME)) as MuzzleFlash
	assert_bool(flash.is_up()).is_true()
	assert_vector(flash.global_position).is_equal_approx(
		marker.global_position, Vector3.ONE * 0.001
	)
	assert_int(flash.frames).is_between(1, 3)
	# Up for exactly its frames, then gone.
	for i in flash.frames:
		_frames(flash, 1)
		assert_bool(flash.is_up()).override_failure_message("frame %d" % (i + 1)).is_true()
	_frames(flash, 1)
	assert_bool(flash.is_up()).is_false()
	assert_bool(flash.light.visible).is_false()


func test_the_flash_is_made_of_a_few_quads_and_nothing_else() -> void:
	var flash: MuzzleFlash = auto_free(MuzzleFlash.new())
	add_child(flash)
	assert_int(flash.quads.size()).is_equal(3)
	for quad in flash.quads:
		assert_object(quad.material_override).is_instanceof(ShaderMaterial)
		assert_object(quad.mesh).is_instanceof(QuadMesh)
	assert_bool(flash.is_up()).is_false()


func test_each_shot_spins_and_scales_the_flash_a_little() -> void:
	var flash: MuzzleFlash = auto_free(MuzzleFlash.new())
	add_child(flash)
	var sizes := {}
	for i in 6:
		flash.fire(0.3, Vector3.FORWARD)
		sizes[snappedf(flash.quads[0].global_transform.basis.x.length(), 0.0001)] = true
	assert_int(sizes.size()).is_greater(1)
	for size: float in sizes:
		assert_float(size).is_between(
			0.3 * flash.scale_range.x - 0.001, 0.3 * flash.scale_range.y + 0.001
		)


func test_a_weapon_with_no_model_flashes_ahead_of_the_body_not_inside_it() -> void:
	var muzzle := Vector3(0.0, 1.45, 0.0)
	_effects.shot(_def(&"pistol"), muzzle, [Vector3(0, 1.5, -8)], [], null)
	var flash: MuzzleFlash = _effects.get("_flash")
	assert_bool(flash.is_up()).is_true()
	assert_float(flash.global_position.distance_to(muzzle)).is_equal_approx(
		ShotEffects.BARE_REACH, 0.001
	)
	assert_float(flash.global_position.z).is_less(muzzle.z)


func test_only_one_flash_on_the_map_holds_the_light() -> void:
	var first: MuzzleFlash = auto_free(MuzzleFlash.new())
	var second: MuzzleFlash = auto_free(MuzzleFlash.new())
	add_child(first)
	add_child(second)
	first.fire(0.3, Vector3.FORWARD)
	assert_bool(first.light.visible).is_true()
	second.fire(0.3, Vector3.FORWARD)
	assert_bool(second.light.visible).is_true()
	assert_bool(first.light.visible).is_false()
	assert_int(get_tree().get_nodes_in_group(MuzzleFlash.LIT_GROUP).size()).is_equal(1)


func test_the_flash_light_can_be_turned_off_in_the_editor_value() -> void:
	var flash: MuzzleFlash = auto_free(MuzzleFlash.new())
	flash.light_enabled = false
	add_child(flash)
	flash.fire(0.3, Vector3.FORWARD)
	assert_bool(flash.is_up()).is_true()
	assert_bool(flash.light.visible).is_false()


func test_every_gun_has_a_flash_and_heavier_guns_flash_bigger() -> void:
	for id: StringName in [&"pistol", &"smg", &"rifle", &"shotgun", &"flare_gun"]:
		assert_float(_def(id).flash_size).is_between(0.1, 0.5)
	assert_float(_def(&"shotgun").flash_size).is_greater(_def(&"rifle").flash_size)
	assert_float(_def(&"rifle").flash_size).is_greater(_def(&"pistol").flash_size)
	# A swing has no muzzle flash.
	assert_float(_def(&"crowbar").flash_size).is_equal(0.0)
	_effects.shot(_def(&"crowbar"), Vector3.ZERO, [Vector3.FORWARD], [], null)
	assert_object(_effects.get("_flash")).is_null()


# --- the shot in the night's view ---


func test_the_server_names_the_zombies_a_shot_hit() -> void:
	var event := _shot_event(&"pistol")
	assert_array(event["flesh"]).is_not_empty()
	assert_vector(event["flesh"][0]).is_equal_approx(event["ends"][0], Vector3.ONE * 0.001)


func test_the_view_hangs_the_flash_on_the_shooters_muzzle_point() -> void:
	_animation.equip(&"Rifle")
	var state := ClientState.new()
	state.player_id = 1
	var view := _view(state)
	view._on_event(_shot_event(&"rifle"))
	var marker := _animation.muzzle_point()
	var flash := marker.get_node(NodePath(MuzzleFlash.NODE_NAME)) as MuzzleFlash
	assert_bool(flash.is_up()).is_true()


func test_a_shot_shakes_the_shooters_own_view_and_no_one_elses() -> void:
	var state := ClientState.new()
	state.player_id = 1
	var view := _view(state)
	var event := _shot_event(&"shotgun")
	view._on_event(event)
	assert_float(_player.camera_rig.shake.trauma).is_equal_approx(
		_def(&"shotgun").shake_trauma, 0.0001
	)
	_player.camera_rig.shake.trauma = 0.0
	state.player_id = 2
	view._on_event(event)
	assert_float(_player.camera_rig.shake.trauma).is_equal(0.0)


func test_a_shot_does_not_move_the_aim_ray_of_the_next_command() -> void:
	var state := ClientState.new()
	state.player_id = 1
	var view := _view(state)
	var rig := _player.camera_rig
	rig.step(TICK, 1.0)
	var before := rig.aim_direction()
	view._on_event(_shot_event(&"shotgun"))
	for i in 10:
		rig.step(TICK, 1.0)
	assert_vector(rig.aim_direction()).is_equal_approx(before, Vector3.ONE * 0.0001)


# --- the Muzzle convention: the flash is on the held weapon's own muzzle ---


func test_the_flash_is_on_the_held_weapons_muzzle_for_every_catalogue_firearm() -> void:
	var with_model := 0
	for def in WeaponCatalog.all():
		if def.is_melee():
			continue
		_animation.equip(WeaponHoldMap.class_of(def.id))
		var muzzle := _animation.muzzle_point()
		var effects: ShotEffects = auto_free(ShotEffects.new())
		add_child(effects)
		# The server's own muzzle is somewhere else on purpose: the flash must not follow it.
		var server_muzzle := Vector3(40.0, 1.45, 40.0)
		if muzzle == null:
			# A class with no model yet flashes at the server's muzzle, a little down the barrel.
			effects.shot(def, server_muzzle, [server_muzzle + Vector3.FORWARD * 9.0], [], null)
			var bare: MuzzleFlash = effects.get("_flash")
			(
				assert_float(bare.global_position.distance_to(server_muzzle))
				. override_failure_message(
					"%s has no model and flashes away from the muzzle" % def.id
				)
				. is_less(ShotEffects.BARE_REACH + 0.01)
			)
			continue
		with_model += 1
		effects.shot(def, server_muzzle, [server_muzzle + Vector3.FORWARD * 9.0], [], muzzle)
		var flash := muzzle.get_node(NodePath(MuzzleFlash.NODE_NAME)) as MuzzleFlash
		assert_bool(flash.is_up()).override_failure_message("%s: no flash" % def.id).is_true()
		(
			assert_vector(flash.global_position)
			. override_failure_message("%s: the flash is not on the Muzzle" % def.id)
			. is_equal_approx(muzzle.global_position, Vector3.ONE * 0.0001)
		)
	# The rifle, the shotgun and the SMG (which borrows the rifle's model) have a model.
	assert_int(with_model).is_greater_equal(3)


func test_a_model_that_carries_its_own_muzzle_node_is_preferred() -> void:
	_animation.equip(&"Rifle")
	var weapon := _animation.weapon()
	var ours := _animation.muzzle_point()
	ours.get_parent().remove_child(ours)
	ours.free()
	var theirs := Node3D.new()
	theirs.name = PlayerAnimation.MUZZLE_NODE
	weapon.add_child(theirs)
	theirs.position = Vector3(-1.0, 0.1, 0.0)
	assert_object(_animation.muzzle_point()).is_same(theirs)
	_effects.shot(_def(&"rifle"), Vector3.ZERO, [Vector3.FORWARD * 5.0], [], theirs)
	var flash := theirs.get_node(NodePath(MuzzleFlash.NODE_NAME)) as MuzzleFlash
	assert_vector(flash.global_position).is_equal_approx(
		theirs.global_position, Vector3.ONE * 0.0001
	)


func test_another_players_shot_flashes_on_their_weapon_and_shakes_nobody() -> void:
	var other := (load("res://gameplay/player/player.tscn") as PackedScene).instantiate() as Player
	other.capture_mouse = false
	add_child(other)
	auto_free(other)
	other.position = Vector3(3.0, 0.0, 0.0)
	var other_animation := other.get_node("AnimationTree") as PlayerAnimation
	other_animation.equip(&"Shotgun")
	var state := ClientState.new()
	state.player_id = 1
	var view: NightView = auto_free(NightView.new())
	add_child(view)
	view.setup(state, _camera)
	view.bodies = func(id: int) -> Player: return other if id == 2 else _player
	var event := _shot_event(&"shotgun")
	event["shooter_id"] = 2
	view._on_event(event)
	var flash := (
		other_animation.muzzle_point().get_node(NodePath(MuzzleFlash.NODE_NAME)) as MuzzleFlash
	)
	assert_bool(flash.is_up()).is_true()
	assert_float(_player.camera_rig.shake.trauma).is_equal(0.0)
	assert_float(other.camera_rig.shake.trauma).is_equal(0.0)
