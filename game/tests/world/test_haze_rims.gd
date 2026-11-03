# The haze columns of the second map have a soft rim from the shoulder camera (issue #854): the
# pendant lamps' cones and the prize crane's beam. The crane's beam was an additive wall with a
# hard edge (a pale column from 1 to 4 m); it now fades at its edge and out of a camera that is in
# it, on the shader it already had (no new program, node or light; #728). The pixels are measured
# by `tests/captures/smallmap_haze_cones.tscn` (docs/research/haze-rims.md); this checks the
# settings that capture measured and the measure itself.
extends GdUnitTestSuite

const PENDANT := "res://world/smallmap/lights/pendant_light.tscn"
const CONES := preload("res://tests/captures/smallmap_haze_cones.gd")
const SIZE := Vector2i(640, 360)
## A column's rim fades over this share of its width at least; a hard edge is about 0.01.
const SOFT := 0.2


func _lamp() -> KitLamp:
	var lamp := (load(PENDANT) as PackedScene).instantiate() as KitLamp
	add_child(lamp)
	auto_free(lamp)
	return lamp


func _beam_of(crane: PrizeCrane) -> ShaderMaterial:
	for mesh in crane.find_children("*", "MeshInstance3D", false, false):
		var instance := mesh as MeshInstance3D
		if instance.mesh is CylinderMesh and instance.material_override is ShaderMaterial:
			return instance.material_override as ShaderMaterial
	return null


## A column `half` pixels across either side of the middle of a picture, bright `level` over the
## dark; its brightness falls over `fade` pixels at each edge (0 a hard edge).
func _column(half: int, fade: int, level: float) -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	var middle := SIZE.x / 2
	for y in SIZE.y:
		for x in SIZE.x:
			var inside := float(half - absi(x - middle))
			var share := clampf(inside / float(maxi(fade, 1)), 0.0, 1.0)
			image.set_pixel(x, y, Color(level, level, level) * share)
	return image


func test_the_measure_tells_a_hard_rim_from_a_soft_one() -> void:
	var dark := _column(0, 0, 0.0)
	var hard: Dictionary = CONES.measure(_column(120, 0, 0.4), dark)
	var soft: Dictionary = CONES.measure(_column(120, 90, 0.4), dark)
	assert_float(hard["rim_softness"]).is_less(0.03)
	assert_float(soft["rim_softness"]).is_greater(SOFT)
	assert_float(soft["plateau"]).is_between(0.1, 0.4)


func test_a_lamps_haze_cone_stays_one_cone_on_the_lots_shader_with_its_near_fade() -> void:
	# The cones were measured soft from 1 to 8 m (docs/research/haze-rims.md) and are not changed;
	# this keeps what made them so: the surface-facing fade of `beam.gdshader` and the near fade.
	var lamp := _lamp()
	var cone := lamp.get_node("Haze/Cone") as MeshInstance3D
	var material := cone.material_override as ShaderMaterial
	assert_object(material.shader).is_same(LightCards.BEAM)
	assert_float(material.get_shader_parameter(&"near_fade")).is_greater_equal(2.0)
	assert_str(LightCards.BEAM.code).contains("dot(normalize(NORMAL), normalize(VIEW))")
	assert_int(lamp.get_node("Haze").get_child_count()).is_equal(1)
	assert_int(cone.mesh.get_surface_count()).is_equal(1)


func test_the_prize_cranes_beam_fades_at_its_edge_and_out_of_a_camera_in_it() -> void:
	var crane := PrizeCrane.new()
	add_child(crane)
	auto_free(crane)
	crane.configure(load(GameRules.DEFAULT_TUNING_PATH).crane, [])
	var beam := _beam_of(crane)
	assert_object(beam).is_not_null()
	assert_float(beam.get_shader_parameter(&"rim_power")).is_greater_equal(1.5)
	assert_float(beam.get_shader_parameter(&"near_fade")).is_greater_equal(2.0)
	# Still one beam on one shader, as the crane had.
	var beams := 0
	for mesh in crane.find_children("*", "MeshInstance3D", false, false):
		if (mesh as MeshInstance3D).material_override is ShaderMaterial:
			beams += 1
	assert_int(beams).is_equal(1)
