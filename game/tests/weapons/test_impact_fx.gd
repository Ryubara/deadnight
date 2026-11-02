# The small pooled impacts of a shot (docs/design/shot-feedback.md): dust, a spark and a mark on a
# wall, one dark-red puff on a zombie; short-lived, capped, and far smaller than the old sphere.
extends GdUnitTestSuite

const TICK := 1.0 / 60.0
## The old impact was a 0.2 m spark and a puff that swelled to 0.52 m: nothing now passes these.
const OLD_SPARK := 0.2
const OLD_PUFF := 0.52

var _effects: ShotEffects


func before_test() -> void:
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.position = Vector3(0.0, 1.5, 6.0)
	camera.make_current()
	_effects = auto_free(ShotEffects.new())
	add_child(_effects)


func _def(id: StringName) -> WeaponDef:
	return WeaponCatalog.get_def(id)


func test_a_wall_hit_is_a_spark_a_puff_and_a_mark_and_all_of_it_is_small() -> void:
	_effects.impacts.spawn(Vector3(0, 1, 0), ImpactFx.Kind.WORLD)
	assert_int(_effects.impacts.active_count()).is_equal(1)
	assert_int(_effects.impacts.visible_parts()).is_equal(3)
	assert_float(_effects.impacts.largest_part()).is_less_equal(ImpactFx.MAX_SIZE)
	# Through the whole life of the impact.
	for i in 90:
		_effects.impacts._process(TICK)
		assert_float(_effects.impacts.largest_part()).is_less_equal(ImpactFx.MAX_SIZE)


func test_the_impact_is_far_smaller_than_the_old_sphere_and_puff() -> void:
	assert_float(_effects.impacts.fx.spark_size).is_less(OLD_SPARK * 0.5)
	assert_float(_effects.impacts.fx.dust_to).is_less(OLD_PUFF * 0.5)
	assert_float(_effects.impacts.fx.blood_to).is_less(_effects.impacts.fx.dust_to)
	assert_float(ImpactFx.MAX_SIZE).is_less(OLD_PUFF * 0.5)


func test_a_zombie_hit_is_one_small_dark_red_puff() -> void:
	_effects.impacts.spawn(Vector3(0, 1, 0), ImpactFx.Kind.FLESH)
	assert_int(_effects.impacts.visible_parts()).is_equal(1)
	var colour: Color = _effects.impacts.fx.blood_colour
	assert_float(colour.r).is_greater(colour.g * 3.0)
	assert_float(colour.get_luminance()).is_less(0.2)


func test_impacts_are_short_lived() -> void:
	_effects.impacts.spawn(Vector3(0, 1, 0), ImpactFx.Kind.WORLD)
	# The spark is two rendered frames (the frame it is drawn in is the first); the dust is gone
	# before half a second; the mark before a second.
	_effects.impacts._process(TICK)
	_effects.impacts._process(TICK)
	assert_int(_effects.impacts.visible_parts()).is_equal(3)
	_effects.impacts._process(TICK)
	assert_int(_effects.impacts.visible_parts()).is_equal(2)
	for i in 30:
		_effects.impacts._process(TICK)
	assert_int(_effects.impacts.visible_parts()).is_equal(1)
	for i in 30:
		_effects.impacts._process(TICK)
	assert_int(_effects.impacts.active_count()).is_equal(0)
	assert_bool(_effects.impacts.is_processing()).is_false()
	for i in 3:
		_effects.impacts.spawn(Vector3(i, 1, 0), ImpactFx.Kind.FLESH)
	for i in 14:
		_effects.impacts._process(TICK)
	assert_int(_effects.impacts.active_count()).is_equal(0)


func test_impacts_are_pooled_and_capped() -> void:
	for i in 200:
		_effects.impacts.spawn(Vector3(i * 0.1, 1, 0), ImpactFx.Kind.WORLD)
		if i % 7 == 0:
			_effects.impacts._process(TICK)
	assert_int(_effects.impacts.active_count()).is_less_equal(ImpactFx.MAX_ACTIVE)
	# 200 impacts never made more than the cap's worth of nodes.
	assert_int(_effects.impacts.get_child_count()).is_equal(ImpactFx.MAX_ACTIVE)
	assert_int(_effects.impacts.visible_parts()).is_less_equal(ImpactFx.MAX_ACTIVE * 3)


func test_a_slot_is_reused_after_its_impact_is_over() -> void:
	_effects.impacts.spawn(Vector3.ZERO, ImpactFx.Kind.FLESH)
	for i in 30:
		_effects.impacts._process(TICK)
	_effects.impacts.spawn(Vector3.ZERO, ImpactFx.Kind.FLESH)
	assert_int(_effects.impacts.get_child_count()).is_equal(1)


func test_a_shot_at_a_zombie_puffs_dark_red_and_at_a_wall_puffs_dust() -> void:
	var def := _def(&"pistol")
	var muzzle := Vector3(0, 1.5, 4)
	var zombie_point := Vector3(0, 1.1, 0)
	var wall_point := Vector3(3, 1.1, -3)
	_effects.shot(def, muzzle, [zombie_point], [zombie_point], null)
	assert_int(_effects.impacts.active_count()).is_equal(1)
	assert_int(_effects.impacts.visible_parts()).is_equal(1)
	_effects.shot(def, muzzle, [wall_point], [], null)
	assert_int(_effects.impacts.active_count()).is_equal(2)
	assert_int(_effects.impacts.visible_parts()).is_equal(1 + 3)
