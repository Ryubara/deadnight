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

## The ticket plaza behind the road door ends at its south wall: the lot has no road past it (#686).
const PLAZA := Rect2(-16.0, 38.0, 32.0, 20.0)
## The wall's outer face, the farthest south anything of the lot reaches (metres).
const LOT_END_Z := 58.2

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


func test_nothing_of_the_lot_lies_past_the_plazas_wall() -> void:
	add_child(_lot)
	var past: Array[String] = []
	for node in _lot.find_children("*", "VisualInstance3D", true, false):
		if (
			node is Light3D
			or node.name == &"Outskirts"
			or not (node as Node3D).is_visible_in_tree()
		):
			continue
		var far := _south_end(node as Node3D)
		if far > LOT_END_Z + 0.01:
			past.append("%s reaches z %.2f" % [_lot.get_path_to(node), far])
	assert_array(past).is_empty()


func test_the_plaza_is_shut_by_walls_higher_than_the_perimeter() -> void:
	# A closed room: the end wall and both sides at 4.2 m, over the perimeter's 3.0 m, because the
	# lot's junk stacked against them reaches 1.71 m and the body climbs 1.25 m (#845;
	# test_plaza_escape.gd runs the hops).
	add_child(_lot)
	for wall_name: String in ["FenceEnd0", "SideW0", "SideE0"]:
		var wall := _lot.get_node("Road/%s" % wall_name) as CSGBox3D
		assert_float(wall.size.y).override_failure_message(wall_name).is_between(4.19, 4.21)
	var end := _lot.get_node("Road/FenceEnd0") as CSGBox3D
	assert_float(end.size.x).is_equal(PLAZA.size.x)
	assert_float(end.global_position.z).is_equal(PLAZA.end.y)


func test_the_plazas_dead_come_from_behind_its_two_side_breaches() -> void:
	# Three points on two aprons just outside the side walls (#849), none past the end wall.
	add_child(_lot)
	var spawns := _lot.get_node("Road/ZombieSpawns").get_children()
	assert_int(spawns.size()).is_equal(3)
	for spawn: Node3D in spawns:
		var at := Vector2(spawn.global_position.x, spawn.global_position.z)
		assert_bool(PLAZA.grow(-1.0).has_point(at)).override_failure_message(str(at)).is_false()
		assert_bool(PLAZA.grow(10.0).has_point(at)).override_failure_message(str(at)).is_true()
		assert_float(at.y).is_less(PLAZA.end.y)
		assert_str(String(spawn.get_meta(&"barricade_id"))).starts_with("plaza_")


## The farthest south (largest z) a drawn thing reaches. A CSG box by its size, a model by its box.
static func _south_end(node: Node3D) -> float:
	var box: AABB
	if node is CSGBox3D:
		box = AABB(-(node as CSGBox3D).size * 0.5, (node as CSGBox3D).size)
	elif node is VisualInstance3D:
		box = (node as VisualInstance3D).get_aabb()
	var far := -INF
	for corner in 8:
		far = maxf(far, (node.global_transform * box.get_endpoint(corner)).z)
	return far
