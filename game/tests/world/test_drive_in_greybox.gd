# The drive-in greybox (docs/design/map.md): areas are named nodes and purchase doors carry the
# shop's prices. Reachability is in test_drive_in_opening_order.gd, the camera in
# test_drive_in_camera.gd.
extends GdUnitTestSuite

const SCENE := "res://world/drive_in_greybox.tscn"
const AREAS := [
	"Field",
	"Concession",
	"Midway",
	"ProjectionBooth",
	"GeneratorYard",
	"BackLot",
	"Road",
]
## The map's door nodes and the shop items (default_tuning.tres) that sell them, in opening order.
const DOORS := {
	"Door_Concession": "door_concession",
	"Door_GeneratorYard": "door_yard",
	"Door_ProjectionBooth": "door_booth",
	"Door_BackLot": "door_back_lot",
	"Door_Road": "door_road",
}

var _lot: Node3D


func before_test() -> void:
	_lot = auto_free(load(SCENE).instantiate()) as Node3D


func test_every_area_is_a_named_node() -> void:
	for area: String in AREAS:
		assert_object(_lot.get_node_or_null(area)).is_not_null()


func test_every_purchase_door_is_priced_by_the_shop() -> void:
	# The map follows the rules: the scene's metadata is written from the tuning by
	# tools/world/build_greybox.py, so
	# a price changed in the tuning and not regenerated shows up here.
	var economy := (load("res://gameplay/rules/default_tuning.tres") as RulesTuning).economy
	for door_name: String in DOORS:
		var door := _lot.get_node("Doors/%s" % door_name)
		var item := economy.item(StringName(DOORS[door_name]))
		assert_object(item).override_failure_message(door_name).is_not_null()
		assert_str(door.get_meta("shop_id")).is_equal(DOORS[door_name])
		assert_int(door.get_meta("cost")).override_failure_message(door_name).is_equal(item.price)
		assert_str(door.get_meta("requires")).override_failure_message(door_name).is_equal(
			str(item.requires)
		)


func test_every_door_has_a_slab_in_each_way_in() -> void:
	# Two ways in (the field's fence and the midway) means two slabs; the others one.
	var slabs := {"Door_GeneratorYard": 2, "Door_BackLot": 2}
	for door_name: String in DOORS:
		var count := 0
		for child: Node in _lot.get_node("Doors/%s" % door_name).get_children():
			if child is CSGBox3D:
				count += 1
		assert_int(count).override_failure_message(door_name).is_equal(slabs.get(door_name, 1))
