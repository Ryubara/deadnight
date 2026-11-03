# What a wall weapon shows on its plaque (#829): the weapon's own silhouette, made by a rule from
# its model, on both maps; no weapon text from a distance (the prompt card names and prices it once
# a player is in reach); one draw call and one shared mesh and material, so a spot adds nothing to
# the night's load or a phone's draw calls.
extends GdUnitTestSuite

const LOT := "res://world/drive_in_greybox.tscn"
const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
## A wall spot's plaque sits this close to its marker (the marker is 1.3 to 1.4 m from the wall).
const PLAQUE_REACH := 2.0
## How far from the spot a far look stands, past the prompt's reach (`NightTuning.use_reach`, 3.2).
const FAR := 6.0
## How far a far look must be from every spot, so that nothing else is in reach of it.
const FAR_CLEAR := 3.6
const EPSILON := 0.001
## The ledger's key (`DrawLedger.material_key`) of an unshaded, opaque, textureless material.
const FLAT_OPAQUE_KEY := (
	"standard:0,0,0,0,0,false,0,false,false,false,false,false,false,false,"
	+ "false,0,0,0,false,-,-,-"
)

var _night: Night


func after_test() -> void:
	if _night != null:
		_night.queue_free()
		_night = null


func _scenes() -> Array[String]:
	return [LOT, SMALL]


func _map(path: String) -> Node3D:
	var map := (load(path) as PackedScene).instantiate() as Node3D
	add_child(map)
	return auto_free(map)


func _spots_of(map: Node3D) -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	for marker in map.get_node("ShopSpots").get_children():
		if marker.get_meta("kind") in ["wall", "rack"]:
			found.append(marker as Marker3D)
	return found


## Whether `node` hangs within reach of the plaque of `spot` (on its floor).
func _by(node: Node3D, spot: Marker3D) -> bool:
	var apart := node.global_position - spot.global_position
	return absf(apart.y) < 2.5 and Vector2(apart.x, apart.z).length() < PLAQUE_REACH


## The silhouette nodes of the plaque belonging to `spot`: the ones that sell its id within reach.
func _silhouettes_at(map: Node3D, spot: Marker3D) -> Array[WallSilhouette]:
	var found: Array[WallSilhouette] = []
	for node in map.find_children("*", "WallSilhouette", true, false):
		var silhouette := node as WallSilhouette
		if silhouette.shop_id == StringName(spot.get_meta("shop_id")) and _by(silhouette, spot):
			found.append(silhouette)
	return found


func test_every_wall_weapon_spot_on_both_maps_has_one_silhouette_of_a_real_model() -> void:
	for path in _scenes():
		var map := _map(path)
		var spots := _spots_of(map)
		assert_int(spots.size()).override_failure_message(path).is_greater(1)
		for spot in spots:
			var label := "%s %s" % [path.get_file(), spot.name]
			var shapes := _silhouettes_at(map, spot)
			assert_int(shapes.size()).override_failure_message(label).is_equal(1)
			var shape := shapes[0]
			assert_object(shape.shape).override_failure_message(label).is_not_null()
			var triangles := SilhouetteMesh.triangle_count(shape.shape.mesh as ArrayMesh)
			assert_int(triangles).override_failure_message(label).is_greater(100)
			# A weapon on a wall has its model: the stand-in is for weapons still to come.
			assert_bool(shape.is_stand_in()).override_failure_message(label).is_false()


func test_no_label_stands_near_a_wall_weapons_plaque() -> void:
	for path in _scenes():
		var map := _map(path)
		for spot in _spots_of(map):
			for node in map.find_children("*", "Label3D", true, false):
				var label := node as Label3D
				var message := "%s: '%s' hangs by %s" % [path.get_file(), label.text, spot.name]
				assert_bool(_by(label, spot)).override_failure_message(message).is_false()


func test_a_spot_is_one_draw_call_and_spots_of_one_weapon_share_a_mesh_and_a_material() -> void:
	var map := _map(SMALL)
	var by_weapon := {}
	var shotguns := 0
	for node in map.find_children("*", "WallSilhouette", true, false):
		var silhouette := node as WallSilhouette
		var mesh := silhouette.shape.mesh
		assert_int(mesh.get_surface_count()).is_equal(1)
		assert_object(mesh.surface_get_material(0)).is_same(SilhouetteMesh.MATERIAL)
		var key := String(silhouette.shop_id) + ("|up" if silhouette.upright else "")
		if by_weapon.has(key):
			assert_object(mesh).is_same(by_weapon[key])
		by_weapon[key] = mesh
		if silhouette.shop_id == &"weapon_shotgun":
			shotguns += 1
	# The map sells the shotgun twice (the side room and upstairs): one mesh between them.
	assert_int(shotguns).is_equal(2)


func test_the_silhouette_material_adds_no_shader_program_to_the_night() -> void:
	# Unshaded, opaque, back faces culled, no texture or glow: the settings of the flat materials
	# the night already draws, so the engine links nothing new for it (a browser pays 0.1 to 2 s
	# for each program, docs/research/web-export.md).
	var key := DrawLedger.material_key(SilhouetteMesh.MATERIAL)
	assert_str(key).is_equal(FLAT_OPAQUE_KEY)


func test_every_weapon_model_in_the_game_gets_a_silhouette_by_the_rule() -> void:
	# The folders of `assets/weapons/`: the three models of #816 (service pistol, ray gun, freeze
	# gun) are here before any hold file or wall spot, and a weapon that lands tomorrow is too.
	var seen := 0
	for folder in DirAccess.get_directories_at("res://assets/weapons"):
		if not ResourceLoader.exists("res://assets/weapons/%s/%s.glb" % [folder, folder]):
			continue
		seen += 1
		var id := StringName("weapon_" + folder)
		assert_bool(SilhouetteMesh.is_stand_in(id)).override_failure_message(folder).is_false()
		var box := SilhouetteMesh.mesh_for(id).get_aabb()
		assert_float(box.size.x).override_failure_message(folder).is_less_equal(
			SilhouetteMesh.FRAME.x + EPSILON
		)
		assert_float(box.size.y).override_failure_message(folder).is_less_equal(
			SilhouetteMesh.FRAME.y + EPSILON
		)
		assert_float(box.size.x).override_failure_message(folder).is_greater(0.5)
		# Centred on its plaque.
		assert_float(box.get_center().x).is_equal_approx(0.0, 0.02)
		assert_float(box.get_center().y).is_equal_approx(0.0, 0.02)
	assert_int(seen).is_greater_equal(13)


func test_every_catalogue_weapon_and_the_grenades_have_a_model_silhouette() -> void:
	for id in WeaponCatalog.IDS:
		var shop := StringName(WeaponCatalog.SHOP_PREFIX + String(id))
		(
			assert_bool(SilhouetteMesh.is_stand_in(shop))
			. override_failure_message(String(id))
			. is_false()
		)
	assert_bool(SilhouetteMesh.is_stand_in(&"grenades")).is_false()


func test_a_weapon_whose_model_has_not_landed_gets_a_stand_in_not_text() -> void:
	var id := &"weapon_not_modelled_yet"
	var mesh := SilhouetteMesh.mesh_for(id)
	assert_bool(SilhouetteMesh.is_stand_in(id)).is_true()
	assert_int(SilhouetteMesh.triangle_count(mesh)).is_greater(0)
	assert_object(mesh.surface_get_material(0)).is_same(SilhouetteMesh.MATERIAL)
	var spot := WallSilhouette.new()
	spot.shop_id = id
	add_child(spot)
	assert_object(spot.shape.mesh).is_not_null()
	assert_bool(spot.is_stand_in()).is_true()
	assert_array(spot.find_children("*", "Label3D", true, false)).is_empty()
	spot.queue_free()


func test_a_model_without_a_hold_file_is_found_by_its_folder_not_by_another_weapons_class() -> void:
	# `ray_gun` has no hold file yet: held as its class it would be the rifle's model.
	assert_str(SilhouetteMesh.model_path(&"ray_gun")).is_equal(
		"res://assets/weapons/ray_gun/ray_gun.glb"
	)
	var ray := SilhouetteMesh.mesh_for(&"weapon_ray_gun")
	assert_bool(ray == SilhouetteMesh.mesh_for(&"weapon_rifle")).is_false()


func test_an_upright_plaque_lays_the_weapon_along_its_long_side() -> void:
	var flat := SilhouetteMesh.mesh_for(&"weapon_rifle").get_aabb()
	var upright := SilhouetteMesh.mesh_for(&"weapon_rifle", true).get_aabb()
	assert_float(flat.size.x).is_greater(flat.size.y)
	assert_float(upright.size.y).is_equal_approx(flat.size.x, EPSILON)
	assert_float(upright.size.x).is_equal_approx(flat.size.y, EPSILON)
	# The cabinet's recess is 0.9 m across and 1.7 m high.
	assert_float(upright.size.x).is_less(0.9)
	assert_float(upright.size.y).is_less(1.7)


## What the player's prompt names at `at`, an empty string for nothing.
func _offer_at(night: Night, at: Vector3) -> String:
	night.player().teleport(at + Vector3(0.0, 0.1, 0.0))
	NightFixture.run(night, 6)
	return String(night.state.me()["prompt"].get("id", ""))


func _prompt_follows_the_reach(night: Night) -> void:
	night.server.rules.apply(RulesAction.grant_points(1, 50000))
	var others := night.world.shop_spots()
	var looked_far := 0
	for spot in _spots_of(night.world.greybox):
		var id := String(spot.get_meta("shop_id"))
		# The revolver the night starts with is offered as its rounds, any other weapon as itself.
		var sold: Array[String] = [id, "ammo_" + String(WeaponCatalog.catalog_id(StringName(id)))]
		var offered := _offer_at(night, spot.global_position)
		var near_message := "near %s: the card names '%s'" % [id, offered]
		assert_bool(offered in sold).override_failure_message(near_message).is_true()
		# Far: out from the wall (the marker faces away from it) or along it, where no spot of any
		# kind is in reach, so what the card names could only be this spot's.
		var far := _far_from(spot, others)
		if far == Vector3.INF:
			continue
		looked_far += 1
		offered = _offer_at(night, far)
		var far_message := "far from %s: the card names '%s'" % [id, offered]
		assert_bool(offered in sold).override_failure_message(far_message).is_false()
	assert_int(looked_far).is_greater(1)


## A point FAR from `spot` with no spot of any kind within reach of it, or INF.
func _far_from(spot: Marker3D, others: Array[Dictionary]) -> Vector3:
	var out := spot.global_basis.z
	for turn in [0.0, PI / 2.0, -PI / 2.0]:
		var at := spot.global_position + out.rotated(Vector3.UP, turn) * FAR
		var clear := true
		for other in others:
			var apart: Vector3 = other["position"] - at
			if absf(apart.y) < 2.5 and Vector2(apart.x, apart.z).length() < FAR_CLEAR:
				clear = false
		if clear:
			return at
	return Vector3.INF


func test_the_name_and_price_come_with_the_prompt_on_the_second_map() -> void:
	_night = await SmallMapNight.start(self)
	SmallMapNight.run(_night, 30)
	_prompt_follows_the_reach(_night)


func test_the_name_and_price_come_with_the_prompt_on_the_lot() -> void:
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(_night, 5)
	_prompt_follows_the_reach(_night)
