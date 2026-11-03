# The six lamps over the breach aprons burn dim (the maintainer's decision, Deadnight #850): the
# dead are seen coming out of the dark without arriving in a spotlight. This holds their levels,
# that every other post of the field burns in full, and that the rules still call the apron lit
# (docs/design/map.md, Light and dark).
extends GdUnitTestSuite

## The share of a post's light the apron lamps give (`APRON_LAMP_DIM` in the map generator,
## tools/world/build_greybox.py).
const APRON_DIM := 0.4
## Dim, not dark and not a spotlight: the band the level may be moved within.
const DIM_FLOOR := 0.25
const DIM_CEILING := 0.5
## A lamp stands this near the spawn it belongs to (they are 0.5 m apart).
const BELONGS := 1.5

var _lot: Node3D
var _lamps: LotLamps
var _generator: GeneratorState


func before_test() -> void:
	_lot = await LotFixture.make_lot(self)
	auto_free(_lot.get_parent())
	var rules: GameRules = _lot.get_meta(&"rules")
	_generator = rules.generator
	_lamps = LotLamps.new(_lot)
	_lamps.configure(rules.tuning.fuel)
	_lamps.refresh(0)


## The spawn markers of the field's breach aprons.
func _apron_spawns() -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	for marker in _lot.get_node("Field/ZombieSpawns").get_children():
		if marker.has_meta(&"barricade_id"):
			found.append(marker as Marker3D)
	return found


func _field_posts() -> Array[LampPost]:
	var posts: Array[LampPost] = []
	for node in _lot.get_node("Field/Lamps").get_children():
		if node is LampPost:
			posts.append(node as LampPost)
	return posts


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The posts that stand over an apron's spawn.
func _apron_posts() -> Array[LampPost]:
	var posts: Array[LampPost] = []
	for spawn in _apron_spawns():
		for post in _field_posts():
			if _flat(post.global_position, spawn.global_position) < BELONGS:
				posts.append(post)
	return posts


func _post_light(post: LampPost) -> Light3D:
	return post.get_node("Light") as Light3D


func _lamp_of(post: LampPost) -> LotLamps.Lamp:
	for lamp in _lamps.lamps:
		if lamp.post == post:
			return lamp
	return null


func test_every_apron_has_one_lamp_over_its_spawn_and_it_burns_dim() -> void:
	var spawns := _apron_spawns()
	assert_int(spawns.size()).is_equal(6)
	for spawn in spawns:
		var over: Array[LampPost] = []
		for post in _field_posts():
			if _flat(post.global_position, spawn.global_position) < BELONGS:
				over.append(post)
		assert_int(over.size()).override_failure_message(str(spawn.name)).is_equal(1)
		assert_float(over[0].dim).override_failure_message(str(spawn.name)).is_equal(APRON_DIM)
	assert_float(APRON_DIM).is_between(DIM_FLOOR, DIM_CEILING)


func test_every_other_post_of_the_field_burns_in_full() -> void:
	var apron := _apron_posts()
	var others := 0
	for post in _field_posts():
		if apron.has(post):
			continue
		others += 1
		assert_float(post.dim).override_failure_message(str(post.name)).is_equal(1.0)
	assert_int(others).is_greater(15)


func test_the_light_the_lens_the_halo_and_the_pool_all_follow_the_level() -> void:
	var tuning := LightTuning.current()
	var full: LampPost = null
	for post in _field_posts():
		if post.dim == 1.0:
			full = post
			break
	assert_object(full).is_not_null()
	for post in _apron_posts():
		var name := str(post.name)
		# The light: the lamp burns at the level of its post.
		assert_float(_lamp_of(post).energy).override_failure_message(name).is_equal_approx(
			_lamp_of(full).energy * APRON_DIM, 0.001
		)
		assert_float(_post_light(post).light_energy).override_failure_message(name).is_equal_approx(
			_post_light(full).light_energy * APRON_DIM, 0.001
		)
		# The lens, the halo and the pool on the ground, with the circuit on.
		var head := post.get_node("Head") as CSGBox3D
		(
			assert_float((head.material as StandardMaterial3D).emission_energy_multiplier)
			. is_equal_approx(tuning.bulb_energy * APRON_DIM, 0.001)
		)
		var halo := (post.get_node("Halo") as MeshInstance3D).material_override as ShaderMaterial
		assert_float(halo.get_shader_parameter(&"energy")).is_equal_approx(
			tuning.bulb_halo_energy * APRON_DIM, 0.001
		)
		var pool := (post.get_node("Pool") as MeshInstance3D).material_override as ShaderMaterial
		assert_float(pool.get_shader_parameter(&"energy")).is_equal_approx(
			tuning.bulb_pool_energy * APRON_DIM, 0.001
		)


func test_a_dim_lamp_still_goes_out_with_its_circuit() -> void:
	_lamps.apply_event({"type": &"circuit_changed", "circuit_id": &"screen_lot", "on": false})
	for post in _apron_posts():
		var head := post.get_node("Head") as CSGBox3D
		assert_bool(_post_light(post).visible).override_failure_message(str(post.name)).is_false()
		assert_float((head.material as StandardMaterial3D).emission_energy_multiplier).is_equal(0.0)
	_lamps.apply_event({"type": &"circuit_changed", "circuit_id": &"screen_lot", "on": true})
	for post in _apron_posts():
		assert_bool(_post_light(post).visible).override_failure_message(str(post.name)).is_true()


func test_the_rules_still_call_the_apron_lit_while_the_field_circuit_is_on() -> void:
	# The decision is to dim the lamps, not to move them out of the pool: the dead leave the
	# breach at their round's pace and are faster only once they leave the lamp's reach.
	for spawn in _apron_spawns():
		(
			assert_bool(_lamps.lit_at(spawn.global_position, _generator))
			. override_failure_message(str(spawn.name))
			. is_true()
		)
	_generator.set_circuit(&"screen_lot", false)
	for spawn in _apron_spawns():
		assert_bool(_lamps.lit_at(spawn.global_position, _generator)).is_false()


func test_a_post_without_a_level_burns_in_full() -> void:
	var scene := load("res://world/drive_in/lamp_post.tscn") as PackedScene
	var post := scene.instantiate() as LampPost
	add_child(post)
	auto_free(post)
	assert_float(post.dim).is_equal(1.0)
	var full := _post_light(post).light_energy
	var half := scene.instantiate() as LampPost
	half.dim = 0.5
	add_child(half)
	auto_free(half)
	assert_float(_post_light(half).light_energy).is_equal_approx(full * 0.5, 0.001)
