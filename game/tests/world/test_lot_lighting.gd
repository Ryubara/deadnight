# The lot's lighting pass (docs/research/night-environment.md, Lamps and glow): what glows
# follows the circuit of the lamp it hangs on, the lot's lights stay under the Compatibility
# renderer's cap per mesh, and what is only decoration lights no ground for the dead.
extends GdUnitTestSuite

## `rendering/limits/opengl/max_lights_per_object`: a mesh lit by more lights drops the rest.
const LIGHT_CAP := 8
## The 320 m near-black ground under the lot: every lamp reaches it, and what it drops is unseen.
const EXEMPT := ["Outskirts"]

var _lot: Node3D
var _lamps: LotLamps
var _fuel: FuelTuning


func before_test() -> void:
	_lot = await LotFixture.make_lot(self)
	auto_free(_lot.get_parent())
	var rules: GameRules = _lot.get_meta(&"rules")
	_fuel = rules.tuning.fuel
	_lamps = LotLamps.new(_lot)
	_lamps.configure(_fuel)
	_lamps.refresh(0)


func _switch(circuit_id: StringName, on: bool) -> void:
	_lamps.apply_event({"type": &"circuit_changed", "circuit_id": circuit_id, "on": on})
	for follower: LightFollower in _lot.find_children("*", "LightFollower", true, false):
		follower.advance(0.0)


func test_the_screen_burns_with_its_circuit_and_keeps_its_afterglow() -> void:
	var screen := _lot.get_node("Field/ScreenFx") as LotScreen
	screen.advance(0.0)
	assert_float(screen.level).is_equal_approx(1.0, 0.001)
	_switch(&"screen_lot", false)
	assert_float(screen.level).is_equal_approx(0.3, 0.001)
	_switch(&"screen_lot", true)
	assert_float(screen.level).is_equal_approx(1.0, 0.001)


func test_the_projector_beam_follows_the_screen_lamp() -> void:
	var beam := _lot.get_node("ProjectionBooth/BeamFx") as ProjectorBeam
	beam.advance(0.0)
	assert_float(beam.level).is_equal_approx(1.0, 0.001)
	_switch(&"screen_lot", false)
	assert_float(beam.level).is_less(0.5)


func test_the_neon_over_the_concession_door_is_dark_until_the_stand_is_powered() -> void:
	var sign := _lot.get_node("Concession/Lamps/NeonSnacks") as LotNeonSign
	sign.advance(0.0)
	assert_float(sign.level).is_equal(0.0)
	assert_bool((sign.get_node("Halo") as MeshInstance3D).visible).is_false()
	_switch(&"concession", true)
	assert_float(sign.level).is_equal_approx(1.0, 0.001)
	assert_bool((sign.get_node("Halo") as MeshInstance3D).visible).is_true()
	_switch(&"concession", false)
	assert_float(sign.level).is_equal(0.0)


func test_a_lamp_post_pool_and_halo_follow_its_circuit() -> void:
	var post := _lot.get_node("Field/Lamps/Lamp1") as LampPost
	assert_bool((post.get_node("Pool") as MeshInstance3D).visible).is_true()
	assert_bool((post.get_node("Halo") as MeshInstance3D).visible).is_true()
	_switch(&"screen_lot", false)
	assert_bool((post.get_node("Pool") as MeshInstance3D).visible).is_false()
	assert_bool((post.get_node("Halo") as MeshInstance3D).visible).is_false()
	var yard := _lot.get_node("GeneratorYard/Lamps/WorkLamp1") as LampPost
	assert_bool((yard.get_node("Pool") as MeshInstance3D).visible).is_true()


func test_the_concession_windows_glow_only_while_the_stand_is_powered() -> void:
	var window := _lot.get_node("Concession/Lamps/WindowW") as GlowPane
	window.advance(0.0)
	assert_bool((window.get_node("Pane") as MeshInstance3D).visible).is_false()
	_switch(&"concession", true)
	assert_bool((window.get_node("Pane") as MeshInstance3D).visible).is_true()
	_switch(&"concession", false)
	assert_bool((window.get_node("Pane") as MeshInstance3D).visible).is_false()


func test_the_marquee_and_its_bulbs_burn_with_the_back_lots_circuit() -> void:
	var glow := _lot.get_node("Road/Lamps/MarqueeGlow") as ModelGlow
	glow.advance(0.0)
	assert_float(glow.level).is_equal(0.0)
	var marquee_mesh := ModelGlow._first_mesh(_lot.get_node("Road/Marquee"))
	var material := marquee_mesh.get_surface_override_material(0) as StandardMaterial3D
	assert_float(material.emission_energy_multiplier).is_equal(0.0)
	_switch(&"back_lot", true)
	assert_float(glow.level).is_equal_approx(1.0, 0.001)
	assert_float(material.emission_energy_multiplier).is_greater(1.0)
	# The shared props of the lot keep their own material: only the marquee glows.
	var booth_mesh := ModelGlow._first_mesh(_lot.get_node("Road/TicketBoothW"))
	assert_object(booth_mesh.get_surface_override_material(0)).is_not_same(material)


func test_the_beam_starts_at_the_projector_lens_and_ends_on_the_screen() -> void:
	var beam := _lot.get_node("ProjectionBooth/BeamFx") as ProjectorBeam
	var lens := beam.global_position
	assert_vector(lens).is_equal_approx(Vector3(0.0, 5.11, 24.37), Vector3.ONE * 0.01)
	var target := lens + beam.target_centre
	assert_float(target.z).is_equal_approx(-47.4, 0.01)
	assert_float(target.y).is_equal_approx(10.0, 0.01)


func test_the_screen_flicker_is_slow_bounded_and_a_function_of_the_phase() -> void:
	var lowest := 10.0
	var highest := 0.0
	var biggest_step := 0.0
	var last := LotScreen.flicker(0.0)
	for i in range(1, 6000):
		var at := float(i) * 0.1
		var f := LotScreen.flicker(at)
		lowest = minf(lowest, f)
		highest = maxf(highest, f)
		biggest_step = maxf(biggest_step, absf(f - last))
		last = f
	assert_float(lowest).is_greater(0.5)
	assert_float(highest).is_less(1.3)
	# A tenth of a second never jumps: a swell, not a strobe.
	assert_float(biggest_step).is_less(0.12)
	assert_float(LotScreen.flicker(12.3)).is_equal(LotScreen.flicker(12.3))


func test_decor_lights_light_no_ground_for_the_dead() -> void:
	var sign_lamp: LotLamps.Lamp = null
	for lamp in _lamps.lamps:
		if lamp.light.get_path().get_concatenated_names().contains("NeonSnacks"):
			sign_lamp = lamp
	assert_object(sign_lamp).is_not_null()
	assert_bool(sign_lamp.decor).is_true()
	assert_bool(sign_lamp.light.visible).is_false()
	for lamp in _lamps.lamps:
		if lamp != sign_lamp:
			assert_bool(lamp.decor).is_false()


func test_no_mesh_of_the_lot_is_lit_by_more_lights_than_the_renderer_allows() -> void:
	# Everything on: the worst case for the cap.
	for circuit_id in _fuel.circuit_drain:
		_switch(circuit_id, true)
	var lights: Array[Light3D] = []
	for node in _lot.get_tree().get_nodes_in_group(&"powered_light"):
		if node is Light3D and _lot.is_ancestor_of(node) and (node as Light3D).visible:
			lights.append(node)
	assert_int(lights.size()).is_greater(20)
	var worst := 0
	var worst_name := ""
	for box: CSGBox3D in _lot.find_children("*", "CSGBox3D", true, false):
		if EXEMPT.has(box.name):
			continue
		var bounds := box.global_transform * AABB(-box.size * 0.5, box.size)
		var names: Array[String] = []
		for light in lights:
			if _reaches(light, bounds):
				names.append(str(_lot.get_path_to(light)))
		var count := names.size()
		if count > worst:
			worst = count
			worst_name = "%s (%s)" % [_lot.get_path_to(box), ", ".join(names)]
	(
		assert_int(worst)
		. override_failure_message("%s is lit by %d lights" % [worst_name, worst])
		. is_less_equal(LIGHT_CAP)
	)


## Whether `light` can touch `bounds`: an omni's sphere, a spot's cone (by its box).
func _reaches(light: Light3D, bounds: AABB) -> bool:
	if light is OmniLight3D:
		var at := light.global_position
		var nearest := at.clamp(bounds.position, bounds.end)
		return at.distance_to(nearest) <= (light as OmniLight3D).omni_range
	var spot := light as SpotLight3D
	var forward := -spot.global_basis.z
	var centre := light.global_position + forward * spot.spot_range
	var radius := spot.spot_range * tan(deg_to_rad(spot.spot_angle))
	var extent := Vector3(
		radius * sqrt(1.0 - forward.x * forward.x),
		radius * sqrt(1.0 - forward.y * forward.y),
		radius * sqrt(1.0 - forward.z * forward.z)
	)
	var cone := AABB(light.global_position, Vector3.ZERO).merge(AABB(centre - extent, extent * 2.0))
	return cone.intersects(bounds)
