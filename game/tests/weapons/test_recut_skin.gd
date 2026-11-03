# The re-cut skin (Deadnight #787): the shader that stands in a weapon's palette material, on the
# surface and
# not as a second pass, for every weapon model and for any model that is added, and gone again
# when taken off.
extends GdUnitTestSuite


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		found.append(node)
	return found


## What each surface of `root` draws with: its override, else its mesh's own.
func _materials(root: Node) -> Array[Material]:
	var found: Array[Material] = []
	for mesh in _meshes(root):
		for index in mesh.mesh.get_surface_count():
			found.append(mesh.get_active_material(index))
	return found


func _model(id: StringName) -> Node3D:
	var hold := WeaponHoldMap.hold_for(id)
	return (load(hold.scene) as PackedScene).instantiate() as Node3D


func _hand() -> HeldWeapon:
	var skeleton := auto_free(Skeleton3D.new()) as Skeleton3D
	skeleton.add_bone(PlayerAnimation.HAND_BONE)
	add_child(skeleton)
	return HeldWeapon.new(skeleton)


func test_every_weapon_model_wears_the_skin_on_its_palette_surface() -> void:
	var worn := 0
	for id in WeaponCatalog.IDS:
		if WeaponHoldMap.hold_for(id) == null:
			continue
		var model := auto_free(_model(id)) as Node3D
		var before := _materials(model)
		var skin := RecutSkin.wear(model)
		assert_int(skin.surface_count()).override_failure_message(String(id)).is_greater(0)
		var after := _materials(model)
		# The same number of surfaces, each one material: no pass is added, so no draw call.
		assert_int(after.size()).is_equal(before.size())
		for i in after.size():
			assert_bool(after[i] is ShaderMaterial).override_failure_message(String(id)).is_true()
			assert_object((after[i] as ShaderMaterial).shader).is_same(RecutSkin.SHADER)
			# It reads the palette the weapon was painted with.
			var palette: Variant = (after[i] as ShaderMaterial).get_shader_parameter(&"palette")
			assert_object(palette).is_same((before[i] as BaseMaterial3D).albedo_texture)
		for mesh in _meshes(model):
			assert_object(mesh.material_overlay).is_null()
			assert_object(mesh.material_override).is_null()
		worn += 1
	assert_int(worn).is_greater(5)


func test_taking_the_skin_off_puts_back_what_each_surface_had() -> void:
	var model := auto_free(_model(&"smg")) as Node3D
	var before := _materials(model)
	RecutSkin.wear(model)
	assert_bool(RecutSkin.worn_by(model) != null).is_true()
	RecutSkin.strip(model)
	assert_object(RecutSkin.worn_by(model)).is_null()
	assert_bool(model.has_meta(RecutSkin.META)).is_false()
	var after := _materials(model)
	assert_int(after.size()).is_equal(before.size())
	for i in after.size():
		assert_object(after[i]).is_same(before[i])
	for mesh in _meshes(model):
		for index in mesh.mesh.get_surface_count():
			assert_object(mesh.get_surface_override_material(index)).is_null()


func test_wearing_it_twice_is_one_skin() -> void:
	var model := auto_free(_model(&"rifle")) as Node3D
	var first := RecutSkin.wear(model, 0.0)
	var second := RecutSkin.wear(model, 1.0)
	assert_object(second).is_same(first)
	assert_float(first.reveal).is_equal(1.0)


func test_a_model_nobody_has_seen_needs_no_work() -> void:
	# A made-up weapon: a near mesh with a palette material, a far one under a `__far` name, a glass
	# part
	# and a part with a material of its own over all of it.
	var palette := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var paint := StandardMaterial3D.new()
	paint.albedo_texture = palette
	paint.metallic = 0.6
	paint.roughness = 0.3
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var glow := StandardMaterial3D.new()
	var root := auto_free(Node3D.new()) as Node3D
	var near := _box(root, "near", paint)
	var far := _box(root, "weapon__far", paint)
	far.visibility_range_begin = 20.0
	var lens := _box(root, "lens", glass)
	var held := _box(root, "held", paint)
	held.material_override = glow
	var skin := RecutSkin.wear(root)
	assert_int(skin.surface_count()).is_equal(2)
	for mesh in [near, far]:
		var material := mesh.get_active_material(0) as ShaderMaterial
		assert_object(material).is_not_null()
		assert_float(material.get_shader_parameter(&"base_metallic")).is_equal_approx(0.6, 0.001)
		assert_float(material.get_shader_parameter(&"base_roughness")).is_equal_approx(0.3, 0.001)
	assert_object(lens.get_active_material(0)).is_same(glass)
	assert_object(held.get_active_material(0)).is_same(glow)
	RecutSkin.strip(root)
	assert_object(near.get_surface_override_material(0)).is_null()


func test_a_mesh_with_no_material_at_all_is_covered_too() -> void:
	var root := auto_free(Node3D.new()) as Node3D
	var bare := _box(root, "bare", null)
	var skin := RecutSkin.wear(root)
	assert_int(skin.surface_count()).is_equal(1)
	assert_bool(bare.get_active_material(0) is ShaderMaterial).is_true()


func test_the_lattice_runs_across_the_whole_weapon_not_from_each_part() -> void:
	var paint := StandardMaterial3D.new()
	var root := auto_free(Node3D.new()) as Node3D
	var part := _box(root, "part", paint)
	part.position = Vector3(0.4, 0.0, 0.0)
	var skin := RecutSkin.wear(root)
	var material := skin.materials()[0]
	var to_root := Transform3D(Projection(material.get_shader_parameter(&"to_root")))
	assert_vector(to_root.origin).is_equal_approx(Vector3(0.4, 0.0, 0.0), Vector3.ONE * 0.001)
	# The sweep's span is the weapon's, from its lowest X to its highest.
	var span: Vector2 = material.get_shader_parameter(&"span")
	assert_float(span.x).is_equal_approx(0.4 - 0.05, 0.001)
	assert_float(span.y).is_equal_approx(0.4 + 0.05, 0.001)


func test_every_value_the_skin_sets_is_a_uniform_of_its_shader() -> void:
	var uniforms: Array[String] = []
	for entry in RecutSkin.SHADER.get_shader_uniform_list():
		uniforms.append(entry["name"])
	var names: Array = RecutSkin.parameters(RecutStyle.shipped()).keys()
	names.append_array([&"palette", &"base_colour", &"base_metallic", &"base_roughness"])
	names.append_array([&"to_root", &"span", &"reveal", &"boost"])
	for name: StringName in names:
		assert_bool(uniforms.has(String(name))).override_failure_message(String(name)).is_true()


func test_the_reveal_and_the_flash_reach_every_surface() -> void:
	var model := auto_free(_model(&"shotgun")) as Node3D
	var skin := RecutSkin.wear(model, 0.0)
	skin.reveal = 0.4
	skin.boost = 2.0
	for material in skin.materials():
		assert_float(material.get_shader_parameter(&"reveal")).is_equal_approx(0.4, 0.001)
		assert_float(material.get_shader_parameter(&"boost")).is_equal_approx(2.0, 0.001)
	skin.reveal = 3.0
	assert_float(skin.reveal).is_equal(1.0)


func test_the_skin_asks_for_no_light_and_no_blending() -> void:
	# The Compatibility renderer lights a mesh with at most so many lights, and the lot is built to
	# that
	# cap (test_lot_light_cap): the skin is one lit opaque surface, like the material it stands in for.
	var code := RecutSkin.SHADER.code
	for word in ["blend_add", "blend_mix", "blend_mul", "unshaded", "depth_test_disabled"]:
		assert_bool(code.contains(word)).override_failure_message(word).is_false()
	assert_bool(code.contains("hint_screen_texture")).is_false()
	assert_bool(code.contains("hint_depth_texture")).is_false()
	# One texture read: the palette.
	assert_int(code.count("texture(")).is_equal(1)


func test_a_held_weapon_keeps_the_skin_across_weapons_until_told_otherwise() -> void:
	var held := _hand()
	held.hold_weapon(&"Rifle", WeaponHoldMap.hold_for(&"smg"))
	assert_bool(held.is_skinned()).is_false()
	held.set_recut(true)
	assert_bool(held.is_skinned()).is_true()
	# The next weapon in the hand is dressed the same.
	held.hold_weapon(&"Shotgun", WeaponHoldMap.hold_for(&"shotgun"))
	assert_bool(held.is_skinned()).is_true()
	held.set_recut(false)
	assert_bool(held.is_skinned()).is_false()
	held.hold_weapon(&"Rifle", WeaponHoldMap.hold_for(&"rifle"))
	assert_bool(held.is_skinned()).is_false()
	held.release()


func test_the_ignition_sweeps_the_skin_over_the_weapon_and_ends() -> void:
	var held := _hand()
	held.hold_weapon(&"Pistol", WeaponHoldMap.hold_for(&"pistol"))
	held.set_recut(true, true)
	var skin := RecutSkin.worn_by(held.weapon)
	assert_float(skin.reveal).is_equal(0.0)
	var seconds := RecutStyle.shipped().ignite_seconds
	held.advance(seconds * 0.5)
	assert_float(skin.reveal).is_equal_approx(0.5, 0.001)
	assert_float(skin.boost).is_greater(0.0)
	held.advance(seconds)
	assert_float(skin.reveal).is_equal(1.0)
	assert_float(skin.boost).is_equal(0.0)
	held.release()


func _box(parent: Node3D, part_name: String, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.1
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	parent.add_child(instance)
	return instance
