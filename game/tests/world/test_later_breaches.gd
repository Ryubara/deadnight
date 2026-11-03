# The dead of the midway, the yard, the back lot and the plaza come in by boarded breaches like the
# field's six (#849): a gap in a wall, boards across it, the dead rising behind it. The number of
# spawn points an area has, and so the share of the pool each open area holds, did not change; only
# where they stand did. The opening order, the walking mesh and the escape probe are the other
# proofs (`test_drive_in_opening_order.gd`, `tools/world/map_escape_probe.gd`).
extends GdUnitTestSuite

const SCENE := "res://world/drive_in_greybox.tscn"
## Spawn points of each area: the counts the lot had before the breaches, and still has.
const SPAWNS := {"Field": 6, "Midway": 2, "GeneratorYard": 3, "BackLot": 3, "Road": 3}
## The breaches of the later areas, by area: the ids the rules list.
const BREACHES := {
	"Midway": [&"mid_w", &"mid_e"],
	"GeneratorYard": [&"yard_e1", &"yard_e2", &"yard_s"],
	"BackLot": [&"back_w1", &"back_w2", &"back_s"],
	"Road": [&"plaza_w", &"plaza_e"],
}
## A spawn point stands at least this far behind its boards (the dead need room to stand and
## tear) and at most this far (they are seen to come out of the gap, not from across the apron).
const BEHIND_MIN := 2.5
const BEHIND_MAX := 5.0

var _lot: Node3D


func before_test() -> void:
	_lot = auto_free(load(SCENE).instantiate()) as Node3D
	add_child(_lot)


func _markers(area: String) -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	for marker in _lot.get_node(area + "/ZombieSpawns").get_children():
		found.append(marker as Marker3D)
	return found


func _barricade(id: StringName) -> Barricade:
	for node in _lot.find_children("*", "Barricade", true, false):
		if StringName(node.get_meta(&"barricade_id")) == id:
			return node as Barricade
	return null


func test_each_area_keeps_its_number_of_spawn_points() -> void:
	for area: String in SPAWNS:
		assert_int(_markers(area).size()).override_failure_message(area).is_equal(SPAWNS[area])


func test_every_later_spawn_names_a_breach_of_its_own_area_and_stands_behind_the_boards() -> void:
	for area: String in BREACHES:
		var own: Array = BREACHES[area]
		for marker in _markers(area):
			var id := StringName(marker.get_meta(&"barricade_id", ""))
			var message := "%s %s names %s" % [area, marker.name, id]
			assert_bool(own.has(id)).override_failure_message(message).is_true()
			var barricade := _barricade(id)
			assert_object(barricade).override_failure_message(message).is_not_null()
			(
				assert_bool(_lot.get_node(area).is_ancestor_of(barricade))
				. override_failure_message(message)
				. is_true()
			)
			var depth := -barricade.depth_of(marker.global_position)
			assert_float(depth).override_failure_message(message).is_between(BEHIND_MIN, BEHIND_MAX)


func test_every_breach_of_an_area_has_a_spawn_point() -> void:
	for area: String in BREACHES:
		var used: Array[StringName] = []
		for marker in _markers(area):
			used.append(StringName(marker.get_meta(&"barricade_id")))
		for id: StringName in BREACHES[area]:
			assert_bool(used.has(id)).override_failure_message("%s has no spawn" % id).is_true()


func test_the_rules_list_every_breach_and_the_lot_has_each_with_its_boards() -> void:
	var tuning := BarricadeTuning.new()
	var in_lot: Array[StringName] = []
	for node in _lot.find_children("*", "Barricade", true, false):
		in_lot.append(StringName(node.get_meta(&"barricade_id")))
		assert_int((node as Barricade).get_child_count()).is_greater_equal(tuning.boards)
	in_lot.sort()
	var listed := tuning.ids.duplicate()
	listed.sort()
	assert_array(in_lot).is_equal(listed)
	assert_int(in_lot.size()).is_equal(6 + 10)


func test_the_gap_of_each_breach_has_no_wall_in_it_and_wall_on_both_sides() -> void:
	# The boards close the gap and are not part of the walking mesh, so a wall box in it would shut
	# the way for the dead, and a gap with no wall at its edges would be a hole in the fence.
	for area: String in BREACHES:
		for id: StringName in BREACHES[area]:
			var barricade := _barricade(id)
			var across := barricade.inward().cross(Vector3.UP)
			var middle := barricade.centre()
			(
				assert_bool(_wall_at(area, middle))
				. override_failure_message("a wall in %s" % id)
				. is_false()
			)
			for side: float in [-1.0, 1.0]:
				var beside: Vector3 = middle + across * side * 2.5
				(
					assert_bool(_wall_at(area, beside))
					. override_failure_message("no wall by %s" % id)
					. is_true()
				)


## Whether a wall of `area` (a tall, thin box, the lot's own) stands over the ground point `at`.
func _wall_at(area: String, at: Vector3) -> bool:
	for node in _lot.get_node(area).get_children():
		var box := node as CSGBox3D
		if box == null or box.size.y < 2.0 or minf(box.size.x, box.size.z) > 0.5:
			continue
		var offset := at - box.global_position
		if absf(offset.x) <= box.size.x / 2.0 + 0.05 and absf(offset.z) <= box.size.z / 2.0 + 0.05:
			return true
	return false


func test_every_spawn_point_of_the_lot_is_at_a_breach() -> void:
	# The share of the pool at a breach was 100, 75, 55, 43 and 35 per cent as the doors opened (the
	# field's six over all of the open areas' points); the counts above stay, and now every point is
	# at one.
	var total := 0
	for area: String in SPAWNS:
		for marker in _markers(area):
			total += 1
			(
				assert_bool(marker.has_meta(&"barricade_id"))
				. override_failure_message("%s %s" % [area, marker.name])
				. is_true()
			)
	assert_int(total).is_equal(17)
