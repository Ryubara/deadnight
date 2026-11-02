# When a player seen only in frames puts a foot down: a step per stride of ground, none while
# standing, airborne or down, and the surface a floor's material says.
extends GdUnitTestSuite

const STRIDE := 1.9
const TICKS_PER_FRAME := 2
const SECONDS_PER_TICK := 1.0 / 60.0


## Feeds a straight walk at `speed` for `seconds` and returns the steps counted.
func _walk(stride: FootStride, speed: float, seconds: float, start_tick := 0) -> int:
	var steps := 0
	var tick := start_tick
	var x := 0.0
	var frames := int(seconds * 60.0 / TICKS_PER_FRAME)
	stride.advance(tick, Vector3(x, 0.0, 0.0), false, SECONDS_PER_TICK)
	for _i in frames:
		tick += TICKS_PER_FRAME
		x += speed * TICKS_PER_FRAME * SECONDS_PER_TICK
		steps += stride.advance(tick, Vector3(x, 0.0, 0.0), false, SECONDS_PER_TICK)
	return steps


func test_a_walk_steps_once_per_stride_of_ground() -> void:
	var steps := _walk(FootStride.new(STRIDE), 4.8, 10.0)
	assert_int(steps).is_equal(int(4.8 * 10.0 / STRIDE))


func test_a_sprint_steps_faster_by_its_speed() -> void:
	var walk := _walk(FootStride.new(STRIDE), 4.8, 10.0)
	var sprint := _walk(FootStride.new(STRIDE), 7.0, 10.0)
	assert_int(sprint).is_equal(int(7.0 * 10.0 / STRIDE))
	assert_float(float(sprint) / walk).is_equal_approx(7.0 / 4.8, 0.1)


func test_a_crouched_creep_steps_slower() -> void:
	var creep := _walk(FootStride.new(STRIDE), 2.4, 10.0)
	assert_int(creep).is_equal(int(2.4 * 10.0 / STRIDE))


func test_standing_and_drifting_make_no_steps() -> void:
	assert_int(_walk(FootStride.new(STRIDE), 0.0, 5.0)).is_equal(0)
	assert_int(_walk(FootStride.new(STRIDE), 0.3, 5.0)).is_equal(0)


func test_a_downed_player_makes_no_steps() -> void:
	var stride := FootStride.new(STRIDE)
	stride.advance(0, Vector3.ZERO, true, SECONDS_PER_TICK)
	var steps := 0
	for i in range(1, 60):
		steps += stride.advance(i * 2, Vector3(i * 0.16, 0.0, 0.0), true, SECONDS_PER_TICK)
	assert_int(steps).is_equal(0)


func test_a_jump_makes_no_steps_while_it_lasts_and_the_stride_resumes_after() -> void:
	var stride := FootStride.new(STRIDE)
	stride.advance(0, Vector3.ZERO, false, SECONDS_PER_TICK)
	# A run at 4.8 m/s with a jump of 0.9 s: v0 = 4.4 m/s up, 9.8 down, samples every 2 ticks.
	var airborne_steps := 0
	var saw_air := false
	var x := 0.0
	var tick := 0
	for i in 60:
		tick += 2
		x += 4.8 * 2.0 * SECONDS_PER_TICK
		var t := i * 2.0 * SECONDS_PER_TICK
		var y := maxf(0.0, 4.4 * t - 0.5 * 9.8 * t * t)
		var flying := y > 0.0
		var steps := stride.advance(tick, Vector3(x, y, 0.0), false, SECONDS_PER_TICK)
		if flying and stride.is_airborne():
			saw_air = true
			airborne_steps += steps
	assert_bool(saw_air).is_true()
	assert_int(airborne_steps).is_equal(0)
	assert_bool(stride.is_airborne()).is_false()
	assert_int(_walk(stride, 4.8, 4.0, tick + 2)).is_greater(5)


func test_a_one_sample_step_up_is_not_a_jump() -> void:
	var stride := FootStride.new(STRIDE)
	stride.advance(0, Vector3.ZERO, false, SECONDS_PER_TICK)
	stride.advance(2, Vector3(0.16, 0.3, 0.0), false, SECONDS_PER_TICK)
	stride.advance(4, Vector3(0.32, 0.3, 0.0), false, SECONDS_PER_TICK)
	assert_bool(stride.is_airborne()).is_false()


func test_a_teleport_starts_the_stride_again_without_a_step() -> void:
	var stride := FootStride.new(STRIDE)
	stride.advance(0, Vector3.ZERO, false, SECONDS_PER_TICK)
	assert_int(stride.advance(2, Vector3(200.0, 0.0, 0.0), false, SECONDS_PER_TICK)).is_equal(0)


func test_gravel_is_told_from_asphalt_by_the_materials_pattern() -> void:
	assert_str(FootSurface.of_material(_material("res://assets/lot/textures/gravel.png"))).is_equal(
		"gravel"
	)
	(
		assert_str(FootSurface.of_material(_material("res://assets/lot/textures/asphalt.png")))
		. is_equal("asphalt")
	)
	(
		assert_str(FootSurface.of_material(_material("res://assets/lot/textures/concrete.png")))
		. is_equal("asphalt")
	)
	assert_str(FootSurface.of_material(null)).is_equal("asphalt")
	assert_str(FootSurface.of_material(StandardMaterial3D.new())).is_equal("asphalt")


func test_a_floor_can_name_its_surface() -> void:
	var floor_node: Node3D = auto_free(Node3D.new())
	floor_node.set_meta(&"surface", &"gravel")
	assert_str(FootSurface.surface_of(floor_node)).is_equal("gravel")


func _material(texture_path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.set_shader_parameter(&"pattern", load(texture_path))
	return material
