# The second map's lamps stay under the Compatibility renderer's cap per mesh, with the room the
# lot's suite keeps for a fight (tests/world/test_lot_light_cap.gd): the same count, on the greybox.
# Its moon stays low indoors (kit docs/godot/compat-lighting.md, Light cards indoors).
extends GdUnitTestSuite

const LOT_SUITE := preload("res://tests/world/test_lot_light_cap.gd")
## The moon indoors, against the lot's 0.36: with no shadow it lifts every floor under the roof.
const INDOOR_MOON_MOST := 0.12

var _map: Node3D


func before_test() -> void:
	_map = auto_free((load(SmallMapMeasure.SCENE) as PackedScene).instantiate()) as Node3D
	add_child(_map)


## The map's omni and spot lights (the moon lights every mesh and is not one of the capped ones).
func _lamps() -> Array[Light3D]:
	var lamps: Array[Light3D] = []
	for node in _map.find_children("*", "Light3D", true, false):
		if (node is OmniLight3D or node is SpotLight3D) and (node as Light3D).visible:
			lamps.append(node)
	return lamps


func test_the_map_has_its_lamps() -> void:
	assert_int(_lamps().size()).is_greater(0)


func test_no_lit_mesh_of_the_map_leaves_less_than_the_room_for_a_fight() -> void:
	var lamps := _lamps()
	var budget := LightCap.limit() - LOT_SUITE.DYNAMIC_HEADROOM
	var over: Array[String] = []
	for mesh in LightCap.lit_meshes(_map):
		var names := LightCap.reaching(_map, lamps, LightCap.bounds(mesh))
		if names.size() > budget:
			over.append(
				(
					"%s is lit by %d lights, over %d (%s)"
					% [_map.get_path_to(mesh), names.size(), budget, ", ".join(names)]
				)
			)
	over.sort()
	assert_array(over).override_failure_message("\n".join(over)).is_empty()


func test_the_moon_stays_low_indoors() -> void:
	var moon := _map.get_node("Lighting/Moon") as DirectionalLight3D
	assert_float(moon.light_energy).is_less_equal(INDOOR_MOON_MOST)
