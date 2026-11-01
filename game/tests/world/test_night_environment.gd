# The lot's night look (docs/research/night-environment.md): a dark sky with the moon in it, fog,
# a flat cool ambient and one moon light, using only what the Compatibility renderer (the web
# build) draws. What it looks like is in the captures of `night_look_tour.tscn`; these tests keep
# the numbers a capture cannot: the scene's settings agree with each other and stay inside the
# renderer's limits.
extends GdUnitTestSuite

const SCENE := "res://world/drive_in_greybox.tscn"
const SKY_SHADER := "res://world/drive_in/night_sky.gdshader"
## A sky colour is night-dark below this luma (sRGB values, Rec. 709 weights).
const SKY_MAX_LUMA := 0.2
## Ambient and the moon together stay under this so lamps and the screen are what lights the lot.
const MAX_FILL := 0.7

var _lighting: Node3D
var _environment: Environment
var _moon: DirectionalLight3D
var _sky: ShaderMaterial


func before_test() -> void:
	var lot := auto_free(load(SCENE).instantiate()) as Node3D
	_lighting = lot.get_node("Lighting")
	_environment = (_lighting.get_node("WorldEnvironment") as WorldEnvironment).environment
	_moon = _lighting.get_node("Moon") as DirectionalLight3D
	_sky = _environment.sky.sky_material as ShaderMaterial


func test_the_background_is_the_night_sky() -> void:
	assert_int(_environment.background_mode).is_equal(Environment.BG_SKY)
	assert_object(_environment.sky).is_not_null()
	assert_object(_sky).is_not_null()
	assert_object(_sky.shader).is_not_null()
	assert_str(_sky.shader.resource_path).is_equal(SKY_SHADER)


func test_the_sky_is_dark() -> void:
	for key: StringName in [&"zenith_color", &"mid_color", &"horizon_color", &"ground_color"]:
		var colour: Color = _sky.get_shader_parameter(key)
		var luma := 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
		assert_float(luma).override_failure_message("%s is too bright" % key).is_less(SKY_MAX_LUMA)
		assert_float(colour.b).override_failure_message("%s is not cool" % key).is_greater_equal(
			colour.r
		)


func test_the_moon_in_the_sky_is_where_the_moon_light_comes_from() -> void:
	var towards_moon: Vector3 = _sky.get_shader_parameter(&"moon_direction")
	# The lot is not in a tree here, so compose the transforms by hand.
	var light_travels := -(_lighting.transform * _moon.transform).basis.z
	assert_vector(towards_moon.normalized()).is_equal_approx(-light_travels, Vector3.ONE * 0.001)
	(
		assert_float(towards_moon.y)
		. override_failure_message("the moon is below the horizon")
		. is_greater(0.1)
	)


func test_the_sky_shader_is_baked_once() -> void:
	# TIME or a LIGHT0 read makes Godot redraw the sky's radiance every frame, a cost the web build
	# pays for nothing here.
	var code := _sky.shader.code
	assert_bool(code.contains("TIME")).is_false()
	assert_bool(code.contains("LIGHT0")).is_false()
	assert_int(_environment.sky.process_mode).is_not_equal(Sky.PROCESS_MODE_REALTIME)
	assert_int(_environment.sky.radiance_size).is_equal(Sky.RADIANCE_SIZE_32)


func test_fog_pools_the_distance_and_leaves_the_sky_alone() -> void:
	assert_bool(_environment.fog_enabled).is_true()
	# Fog at 25 m (where a zombie must still read) stays thin, at the far wall it is thick.
	var at_25 := 1.0 - exp(-_environment.fog_density * 25.0)
	var at_120 := 1.0 - exp(-_environment.fog_density * 120.0)
	assert_float(at_25).is_between(0.05, 0.3)
	assert_float(at_120).is_greater(0.5)
	assert_float(_environment.fog_sky_affect).is_equal(0.0)


func test_only_compatibility_features_are_on() -> void:
	assert_bool(_environment.volumetric_fog_enabled).is_false()
	assert_bool(_environment.sdfgi_enabled).is_false()
	assert_bool(_environment.ssr_enabled).is_false()
	assert_bool(_environment.ssao_enabled).is_false()
	assert_bool(_environment.ssil_enabled).is_false()
	assert_bool(_environment.glow_enabled).is_false()
	assert_bool(_moon.shadow_enabled).is_false()
	assert_int(_environment.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_COLOR)
	assert_int(_environment.tonemap_mode).is_not_equal(Environment.TONE_MAPPER_LINEAR)


func test_lamps_and_the_screen_are_what_light_the_lot() -> void:
	var fill := _environment.ambient_light_energy + _moon.light_energy
	assert_float(fill).is_less(MAX_FILL)
	assert_float(_moon.light_energy).is_greater(0.0)
	# The sky is cool: the moon's light is bluer than it is red.
	assert_float(_moon.light_color.b).is_greater(_moon.light_color.r)
