# The small-map kit's lamps and light cards (issue #636; docs/research/maps/small-map-art.md):
# the models on the kit atlas, a lamp that follows its circuit, the moon shaft's geometry, cards
# that take no light slot and build no GL program the lot does not, and a lit room within the cap.
extends GdUnitTestSuite

const PENDANT := "res://world/smallmap/lights/pendant_light.tscn"
const LANTERN := "res://world/smallmap/lights/lantern_light.tscn"
const CARD_SCENES: Array[String] = [
	PENDANT,
	LANTERN,
	"res://world/smallmap/lights/moon_shaft.tscn",
	"res://world/smallmap/lights/door_glow.tscn",
	"res://world/smallmap/lights/chalk_message.tscn",
]
const CAPTURE := "res://tests/captures/smallmap_lights.tscn"
## Lights a fight adds to a mesh near it (test_lot_light_cap.gd's DYNAMIC_HEADROOM).
const DYNAMIC_HEADROOM := 2


func before() -> void:
	# GdUnit minimizes the window after every suite and a minimized window draws no frame,
	# which the warm-up waits for (#1207).
	await WindowFixture.make_drawable(get_tree())


func _add(path: String) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	add_child(node)
	auto_free(node)
	return node


func _mesh_of(fixture: Node) -> MeshInstance3D:
	return fixture.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D


func _triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		count += indices.size() / 3
	return count


func test_the_lamps_are_one_mesh_on_the_kit_atlas_within_budget_and_at_their_size() -> void:
	# name: [triangle budget, size in metres, the lowest point]
	var pieces := {
		"res://world/smallmap/fixtures/pendant_lamp.tscn": [600, Vector3(0.6, 0.662, 0.6), 2.138],
		"res://world/smallmap/fixtures/wall_lantern.tscn": [600, Vector3(0.25, 0.4, 0.2), 1.8],
	}
	for path: String in pieces:
		var spec: Array = pieces[path]
		var mesh := _mesh_of(_add(path))
		assert_int(mesh.mesh.get_surface_count()).override_failure_message(path).is_equal(1)
		var material := mesh.get_active_material(0) as StandardMaterial3D
		assert_str(material.albedo_texture.resource_path).ends_with(
			"assets/smallmap/smallmap_palette.png"
		)
		assert_int(_triangles(mesh.mesh)).override_failure_message(path).is_less_equal(spec[0])
		var box := mesh.get_aabb()
		assert_vector(box.size).override_failure_message(path).is_equal_approx(
			spec[1], Vector3.ONE * 0.01
		)
		assert_float(box.position.y).is_equal_approx(spec[2], 0.01)


func test_the_fixtures_carry_hidden_collision() -> void:
	for path in [
		"res://world/smallmap/fixtures/pendant_lamp.tscn",
		"res://world/smallmap/fixtures/wall_lantern.tscn"
	]:
		var blocker := _add(path).get_node("Blocker") as CSGShape3D
		assert_bool(blocker.use_collision).is_true()
		assert_bool(blocker.visible).is_false()


func test_a_lamp_lights_its_bulb_swatch_and_nothing_else_of_the_atlas() -> void:
	var image := KitLamp.emission_texture(0.0).get_image()
	var at := func(index: int) -> Color:
		return image.get_pixel(
			(index % KitLamp.GRID) * KitLamp.SWATCH_PX + 8,
			(index / KitLamp.GRID) * KitLamp.SWATCH_PX + 8
		)
	assert_float((at.call(KitLamp.BULB_INDEX) as Color).v).is_greater(0.8)
	for index in 25:
		if index != KitLamp.BULB_INDEX:
			assert_float((at.call(index) as Color).v).override_failure_message(str(index)).is_equal(
				0.0
			)


func test_a_lamp_with_its_own_light_goes_dark_with_it() -> void:
	var lamp := _add(PENDANT) as KitLamp
	var light := lamp.get_node("Light") as OmniLight3D
	assert_float(lamp.level).is_equal(1.0)
	assert_bool(lamp.get_node("Pool").visible).is_true()
	light.visible = false
	lamp.advance(0.1)
	assert_float(lamp.level).is_equal(0.0)
	assert_bool(lamp.get_node("Pool").visible).is_false()
	assert_bool(lamp.get_node("Haze").visible).is_false()
	var bulb := _mesh_of(lamp.get_node("Lamp")).get_surface_override_material(0)
	assert_float((bulb as StandardMaterial3D).emission_energy_multiplier).is_equal(0.0)


func test_a_lamp_without_a_light_takes_no_slot_and_follows_its_circuit_or_burns_steady() -> void:
	var steady := (load(PENDANT) as PackedScene).instantiate() as KitLamp
	steady.own_light = false
	add_child(steady)
	auto_free(steady)
	assert_object(steady.get_node_or_null("Light")).is_null()
	assert_float(steady.level).is_equal(1.0)
	var circuit := auto_free(OmniLight3D.new()) as OmniLight3D
	circuit.light_energy = 2.0
	add_child(circuit)
	var follower := (load(PENDANT) as PackedScene).instantiate() as KitLamp
	follower.own_light = false
	follower.light_path = circuit.get_path()
	add_child(follower)
	auto_free(follower)
	circuit.light_energy = 1.0
	follower.advance(0.1)
	assert_float(follower.level).is_equal_approx(0.5, 0.001)


func test_the_moon_shaft_lands_where_the_opening_projects_along_the_moon() -> void:
	var shaft := MoonShaft.new()
	shaft.opening = Vector2(1.2, 1.3)
	shaft.sill = 0.9
	shaft.pitch = 38.0
	add_child(shaft)
	auto_free(shaft)
	var run := 1.0 / tan(deg_to_rad(38.0))
	var top := shaft.land(shaft.opening_point(0.0, 0.0))
	assert_float(top.y).is_equal_approx(0.015, 0.001)
	assert_float(top.z).is_equal_approx(0.15 + 2.2 * run, 0.01)
	var sill := shaft.land(shaft.opening_point(1.0, 1.0))
	assert_float(sill.z).is_equal_approx(0.15 + 0.9 * run, 0.01)
	assert_float(sill.x).is_equal_approx(0.6, 0.001)
	# With a wall 2 m ahead the top of the opening lands on it, the sill still on the floor.
	shaft.land_wall = 2.0
	var on_wall := shaft.land(shaft.opening_point(0.0, 0.0))
	assert_float(on_wall.z).is_equal_approx(2.14, 0.001)
	assert_float(on_wall.y).is_equal_approx(2.2 - 2.0 * tan(deg_to_rad(38.0)), 0.01)
	assert_float(shaft.land(shaft.opening_point(0.0, 1.0)).y).is_equal_approx(0.015, 0.001)


func test_a_purchase_doors_light_follows_the_far_rooms_lamp_and_leaves_the_floor_when_bought(
) -> void:
	var lamp := auto_free(OmniLight3D.new()) as OmniLight3D
	add_child(lamp)
	var glow := DoorGlow.new()
	glow.light_path = lamp.get_path()
	add_child(glow)
	auto_free(glow)
	assert_bool(glow.get_node("Spill").visible).is_true()
	glow.opened = true
	assert_bool(glow.get_node("Spill").visible).is_false()
	assert_bool(glow.get_node("Beyond").visible).is_true()
	lamp.visible = false
	glow.advance(0.1)
	assert_bool(glow.get_node("Beyond").visible).is_false()


func test_every_chalk_message_has_its_row_in_the_lettering() -> void:
	var data: Dictionary = ChalkMessage.LAYOUT.data
	var names := (auto_free(ChalkMessage.new()) as ChalkMessage).get_property_list().filter(
		func(p: Dictionary) -> bool: return p["name"] == "message"
	)
	var hint := String(names[0]["hint_string"]).split(",")
	assert_int(hint.size()).is_equal((data["messages"] as Array).size())
	for i in hint.size():
		var rect := ChalkMessage.rect_of(i)
		assert_bool(Rect2(0, 0, 1, 1).encloses(rect)).override_failure_message(hint[i]).is_true()
		assert_float(rect.size.x).is_greater(0.2)


func test_the_cards_take_no_light_slot() -> void:
	for path in CARD_SCENES:
		var scene := _add(path)
		for mesh in scene.find_children("*", "GeometryInstance3D", true, false):
			if (
				scene.get_node_or_null("Lamp") != null
				and scene.get_node("Lamp").is_ancestor_of(mesh)
			):
				continue  # the lamp's model is lit, as every prop is
			(
				assert_bool(LightCap.is_lit(mesh))
				. override_failure_message(
					"%s: %s takes a light slot" % [path, scene.get_path_to(mesh)]
				)
				. is_false()
			)


func test_the_lit_room_and_corridor_leave_room_for_a_fight() -> void:
	var capture := (load(CAPTURE) as PackedScene).instantiate() as Node3D
	add_child(capture)
	auto_free(capture)
	var lights: Array[Light3D] = []
	for node in capture.find_children("*", "Light3D", true, false):
		if not node is DirectionalLight3D:
			lights.append(node)
	assert_int(lights.size()).is_equal(3)  # the crane's lamp, the buy's pendant, the lantern
	var over: Array[String] = []
	for mesh in LightCap.lit_meshes(capture):
		if mesh.name == "Outskirts":
			continue
		var names := LightCap.reaching(capture, lights, LightCap.bounds(mesh))
		if names.size() > LightCap.limit() - DYNAMIC_HEADROOM:
			over.append("%s: %s" % [capture.get_path_to(mesh), ", ".join(names)])
	assert_array(over).override_failure_message("\n".join(over)).is_empty()


func test_the_lamps_and_cards_draw_nothing_the_nights_warm_up_does_not() -> void:
	# They are drawn with the lot's own shaders and materials (glow, beam, the kit atlas with an
	# emission texture), so a night that has them links no GL program the warm-up did not.
	var night := Night.new()
	night.warm_up = true
	add_child(night)
	await night.start(Night.Mode.AUTOPILOT, 7, null)
	var drawn: Dictionary[String, int] = {}
	for path in CARD_SCENES:
		drawn.merge(DrawLedger.strings_of(_add(path)))
	assert_int(drawn.size()).is_greater(4)
	assert_array(night.warmup.ledger.missing(drawn)).is_empty()
	night.queue_free()
