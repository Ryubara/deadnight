# Every map has a place for every seat (`NightHost.MAX_PLAYERS`, #690): eight markers, none closer
# to another than a body is wide, so a full room never starts with two players in one spot.
extends GdUnitTestSuite

const MAPS: Array[String] = [
	"res://world/drive_in_greybox.tscn",
	"res://world/smallmap/smallmap_greybox.tscn",
]
## Two bodies (a capsule is 0.4 m in radius) never overlap at this.
const CLEAR := 1.2


func _spawns(path: String) -> Array[Vector3]:
	var lot: Node = auto_free((load(path) as PackedScene).instantiate())
	var group := lot.get_node_or_null("Field/PlayerSpawns")
	if group == null:
		group = lot.get_node("PlayerSpawns")
	var found: Array[Vector3] = []
	for marker: Node3D in group.get_children():
		found.append(marker.position + (marker.get_parent() as Node3D).position)
	return found


func test_every_map_has_a_spawn_for_every_seat() -> void:
	for path in MAPS:
		assert_int(_spawns(path).size()).override_failure_message(path).is_equal(
			NightHost.MAX_PLAYERS
		)


func test_no_two_spawns_of_a_map_are_closer_than_a_body_is_wide() -> void:
	for path in MAPS:
		var spots := _spawns(path)
		for i in spots.size():
			for j in range(i + 1, spots.size()):
				(
					assert_float(spots[i].distance_to(spots[j]))
					. override_failure_message("%s: spawns %d and %d" % [path, i + 1, j + 1])
					. is_greater_equal(CLEAR)
				)
