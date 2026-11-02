# The lot's lights stay under the Compatibility renderer's cap per mesh
# (docs/research/night-environment.md, Lamps and glow): every mesh a light shades is counted,
# props and cars included, and the cap leaves room for the lights that only exist while a fight
# goes on (a muzzle flash, a blast, a grenade's lamp).
extends GdUnitTestSuite

## Lights a fight adds on top of the lot's own to any mesh near it: one muzzle flash, and one blast
## or one grenade lamp (a grenade bursts where its lamp was, so the two are not both new).
const DYNAMIC_HEADROOM := 2
## The 320 m near-black ground under the lot: every lamp reaches it, and what it drops is unseen.
const EXEMPT := ["Outskirts"]
## Where each script and scene that makes a light says what it is. A new light source is not in
## here, and the test that reads the project fails until its place in the cap is decided.
const LIGHT_SCRIPTS := {
	"res://gameplay/weapons/fx/muzzle_flash.gd": "muzzle flash: one flash on the map lit at a time",
	"res://world/grenade_range/blast_effect.gd": "blast",
	"res://world/grenade_range/grenade_view.gd": "grenade lamp",
	"res://world/crane/prize_crane.gd": "the crane's lamp: counted at every crane spot",
	"res://gameplay/night/warmup/night_warmup.gd":
	"the warm-up's stage, 150 m above the lot, out of reach",
	"res://ui/components/look_preview.gd": "own world: a viewport of its own",
	"res://ui/hud/hud_portrait.gd": "own world: a viewport of its own",
	"res://ui/stage/menu_stage.gd": "own world: the main menu's viewport of its own",
}
const LIGHT_SCENES := {
	"res://world/drive_in_greybox.tscn": "the lot's lamps",
	"res://world/drive_in/lamp_post.tscn": "the lot's lamps",
	"res://world/drive_in/lot_neon_sign.tscn": "the lot's lamps",
}
const SEARCH_ROOT := "res://"
## Folders that hold no game code or scenes of ours.
const SEARCH_SKIP := ["res://addons", "res://tests", "res://.godot"]

var _lot: Node3D
var _lights: Array[Light3D] = []


func before_test() -> void:
	_lot = await LotFixture.make_lot(self)
	auto_free(_lot.get_parent())
	var rules: GameRules = _lot.get_meta(&"rules")
	var fuel := rules.tuning.fuel
	var lamps := LotLamps.new(_lot)
	lamps.configure(fuel)
	lamps.refresh(0)
	# Everything on: the worst case for the cap.
	for circuit_id in fuel.circuit_drain:
		lamps.apply_event({"type": &"circuit_changed", "circuit_id": circuit_id, "on": true})
	for follower: LightFollower in _lot.find_children("*", "LightFollower", true, false):
		follower.advance(0.0)
	_lights.clear()
	for node in _lot.get_tree().get_nodes_in_group(&"powered_light"):
		if node is Light3D and _lot.is_ancestor_of(node) and (node as Light3D).visible:
			_lights.append(node)


## Every lit mesh of the lot but the exempt ones (by lot path) -> the lights that reach it.
func _reach_by_mesh() -> Dictionary:
	var reach := {}
	for mesh in LightCap.lit_meshes(_lot):
		if EXEMPT.has(mesh.name):
			continue
		reach[str(_lot.get_path_to(mesh))] = LightCap.reaching(_lot, _lights, LightCap.bounds(mesh))
	return reach


## The meshes reached by more than `most` lights, as lines that name the lights.
func _over(reach: Dictionary, most: int) -> Array[String]:
	var over: Array[String] = []
	for path: String in reach:
		var names: Array[String] = reach[path]
		if names.size() > most:
			over.append("%s is lit by %d lights (%s)" % [path, names.size(), ", ".join(names)])
	over.sort()
	return over


func test_the_count_walks_props_and_cars_and_leaves_out_what_ignores_lights() -> void:
	var lit := LightCap.lit_meshes(_lot)
	var instances := lit.filter(func(node: Node) -> bool: return node is MeshInstance3D)
	var boxes := lit.filter(func(node: Node) -> bool: return node is CSGShape3D)
	# The kit's props are MeshInstance3D: hundreds of them, as well as the lot's own boxes.
	assert_int(instances.size()).is_greater(200)
	assert_int(boxes.size()).is_greater(100)
	assert_bool(lit.has(_lot.get_node("Field/Rows/Row4/Car43/Model/car_yellow"))).is_true()
	# A lamp's pool and halo are additive quads that ignore lights: they take no slot.
	assert_bool(lit.has(_lot.get_node("Field/Lamps/Lamp3/Pool"))).is_false()
	assert_bool(lit.has(_lot.get_node("Field/Lamps/Lamp3/Halo"))).is_false()


func test_what_ignores_lights_and_what_does_not_is_told_apart() -> void:
	var plain := StandardMaterial3D.new()
	var unshaded := StandardMaterial3D.new()
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow := ShaderMaterial.new()
	glow.shader = Shader.new()
	glow.shader.code = "shader_type spatial;\nrender_mode unshaded, blend_add;\nvoid fragment() {}"
	var lit_shader := ShaderMaterial.new()
	lit_shader.shader = Shader.new()
	lit_shader.shader.code = "shader_type spatial;\nvoid fragment() {}"
	var holder := auto_free(Node3D.new()) as Node3D
	add_child(holder)
	var cases := {
		"no material is the default, lit": [_mesh(holder, null, null), true],
		"standard": [_mesh(holder, plain, null), true],
		"unshaded standard": [_mesh(holder, unshaded, null), false],
		"unshaded shader": [_mesh(holder, glow, null), false],
		"shader that shades": [_mesh(holder, lit_shader, null), true],
		"an override beats the mesh": [_mesh(holder, plain, unshaded), false],
		"a lit override beats an unshaded mesh": [_mesh(holder, unshaded, plain), true],
	}
	for what: String in cases:
		var pair: Array = cases[what]
		assert_bool(LightCap.is_lit(pair[0])).override_failure_message(what).is_equal(pair[1])
	var csg := CSGBox3D.new()
	holder.add_child(csg)
	assert_bool(LightCap.is_lit(csg)).is_true()
	csg.material = unshaded
	assert_bool(LightCap.is_lit(csg)).is_false()
	var label := Label3D.new()
	holder.add_child(label)
	assert_bool(LightCap.is_lit(label)).is_false()
	label.shaded = true
	assert_bool(LightCap.is_lit(label)).is_true()


func test_a_light_reaches_a_box_by_its_sphere_or_its_cone() -> void:
	var holder := auto_free(Node3D.new()) as Node3D
	add_child(holder)
	var omni := OmniLight3D.new()
	omni.omni_range = 5.0
	holder.add_child(omni)
	assert_bool(LightCap.reaches(omni, AABB(Vector3(4, -1, -1), Vector3(2, 2, 2)))).is_true()
	assert_bool(LightCap.reaches(omni, AABB(Vector3(6, -1, -1), Vector3(2, 2, 2)))).is_false()
	var spot := SpotLight3D.new()
	spot.spot_range = 10.0
	spot.spot_angle = 20.0
	holder.add_child(spot)
	# A spot looks down -Z: a box ahead is in the cone's box, one behind is not.
	assert_bool(LightCap.reaches(spot, AABB(Vector3(-1, -1, -9), Vector3(2, 2, 2)))).is_true()
	assert_bool(LightCap.reaches(spot, AABB(Vector3(-1, -1, 3), Vector3(2, 2, 2)))).is_false()


func test_a_prop_moved_under_the_lamps_is_caught() -> void:
	var car := _lot.get_node("Field/Rows/Row4/Car43/Model/car_yellow") as MeshInstance3D
	var copy := car.duplicate() as MeshInstance3D
	_lot.add_child(copy)
	copy.global_position = Vector3(0.0, 0.0, -12.0)
	var names := LightCap.reaching(_lot, _lights, LightCap.bounds(copy))
	assert_int(names.size()).is_greater(LightCap.limit() - DYNAMIC_HEADROOM)
	assert_bool(LightCap.lit_meshes(_lot).has(copy)).is_true()


func test_no_lit_mesh_of_the_lot_is_lit_by_more_lights_than_the_renderer_allows() -> void:
	var over := _over(_reach_by_mesh(), LightCap.limit())
	assert_array(over).override_failure_message("\n".join(over)).is_empty()


func test_the_lot_leaves_room_for_the_lights_of_a_fight() -> void:
	var over := _over(_reach_by_mesh(), LightCap.limit() - DYNAMIC_HEADROOM)
	assert_array(over).override_failure_message("\n".join(over)).is_empty()


## The prize crane stands on one of the lot's crane spots at a time and carries a lamp of its own:
## with that lamp in, and the crane's own meshes among the lit ones, no mesh is over the budget
## that the lot keeps for a fight.
func test_the_crane_at_any_of_its_spots_keeps_the_lot_within_the_budget() -> void:
	var rules: GameRules = _lot.get_meta(&"rules")
	var budget := LightCap.limit() - DYNAMIC_HEADROOM
	var problems: Array[String] = []
	var spots := _lot.get_node("ShopSpots").get_children().filter(
		func(marker: Node) -> bool: return marker.get_meta("kind") == "crane"
	)
	assert_int(spots.size()).is_greater(0)
	for marker: Node3D in spots:
		var crane := PrizeCrane.new()
		_lot.add_child(crane)
		crane.configure(rules.tuning.crane, [])
		var forward := marker.global_basis.z
		crane.global_transform = CraneView.stand_at(
			marker.global_position, atan2(forward.x, forward.z)
		)
		var lights := _lights.duplicate()
		for lamp: Light3D in crane.find_children("*", "Light3D", true, false):
			lights.append(lamp)
		for mesh in LightCap.lit_meshes(_lot):
			var path := str(_lot.get_path_to(mesh))
			if EXEMPT.has(mesh.name):
				continue
			var count := LightCap.reaching(_lot, lights, LightCap.bounds(mesh)).size()
			if count > budget:
				problems.append(
					(
						"crane spot %s: %s is lit by %d lights, over %d"
						% [marker.name, path, count, budget]
					)
				)
		crane.free()
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_every_light_the_game_can_make_at_run_time_has_a_place_in_the_cap() -> void:
	var problems: Array[String] = []
	for path in _files(SEARCH_ROOT, ".gd"):
		if _file_text(path).contains("Light3D.new(") and not LIGHT_SCRIPTS.has(path):
			problems.append("%s makes a light at run time: add it to LIGHT_SCRIPTS" % path)
	for path in _files(SEARCH_ROOT, ".tscn"):
		var text := _file_text(path)
		var has_light := text.contains('type="OmniLight3D"') or text.contains('type="SpotLight3D"')
		if has_light and not LIGHT_SCENES.has(path):
			problems.append("%s has a light: add it to LIGHT_SCENES" % path)
	for path: String in LIGHT_SCRIPTS.keys() + LIGHT_SCENES.keys():
		if not FileAccess.file_exists(path):
			problems.append("%s is listed but gone" % path)
	assert_array(problems).override_failure_message("\n".join(problems)).is_empty()


func test_each_fight_effect_adds_one_light_and_the_headroom_pays_for_it() -> void:
	var effects := auto_free(ShotEffects.new()) as ShotEffects
	add_child(effects)
	# The flashes are pooled and only one holds its light at a time: whichever weapon fires, one
	# lit light is what a shot has on the map.
	for def in WeaponCatalog.all():
		if def.is_melee():
			continue
		effects.shot(def, Vector3(0, 1.5, 0), [Vector3(0, 1.0, -6)])
		var lit := 0
		for light: Light3D in effects.find_children("*", "Light3D", true, false):
			if light.visible:
				lit += 1
		assert_int(lit).override_failure_message("%s lights %d lights" % [def.id, lit]).is_equal(1)
	var blast := auto_free(BlastEffect.new()) as BlastEffect
	add_child(blast)
	blast.play(Vector3.ZERO, load("res://gameplay/grenades/defs/frag.tres") as GrenadeDef)
	assert_int(blast.find_children("*", "Light3D", true, false).size()).is_equal(1)
	var grenade := auto_free(GrenadeView.new()) as GrenadeView
	add_child(grenade)
	assert_int(grenade.find_children("*", "Light3D", true, false).size()).is_equal(1)
	# One flash plus one blast is the most a mesh near a fight gains at once.
	assert_int(DYNAMIC_HEADROOM).is_equal(2)


## A mesh with `material` on its one surface and `override` over it (each may be null).
func _mesh(parent: Node3D, material: Material, override: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = override
	parent.add_child(instance)
	return instance


## Every file under `dir` ending in `extension`, skipping the folders that are not ours.
func _files(dir: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	if SEARCH_SKIP.has(dir.trim_suffix("/")):
		return found
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(extension):
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files(dir.path_join(sub), extension))
	return found


func _file_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)
