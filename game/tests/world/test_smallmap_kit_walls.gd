# The small-map kit's walls, openings and floors (docs/research/maps/small-map-art.md, issue #633):
# every fixture loads with its model and collision, the openings keep the kit's clear sizes, the
# zombie windows keep a player-only blocker that the navigation never sees, and every piece is
# within its triangle budget. The pieces and fixtures are written by
# tools/blender/build_smallmap_walls.py.
extends GdUnitTestSuite

const FIXTURES := "res://world/smallmap/fixtures"
const REPORT := "res://assets/smallmap/smallmap_walls.json"
const PLAYER_SCENE := "res://gameplay/player/player.tscn"
const BOARD_LAYER := Barricade.BOARD_LAYER
## Clear openings (width, height, sill) the scale table sets.
const DOORWAYS := {
	"wall_door_narrow": Vector3(1.4, 2.4, 0.0),
	"wall_door_narrow_upper": Vector3(1.4, 2.4, 0.0),
	"wall_arch": Vector3(1.4, 2.0, 0.0),  # under the springing; the crown is 2.4
	"wall_opening_wide": Vector3(2.0, 2.4, 0.0),
}
const ZOMBIE_WINDOWS: Array[String] = ["wall_window_zombie", "wall_window_zombie_upper"]
const WINDOW := Vector3(1.2, 1.3, 0.9)
const MM := 0.001


func _fixture(piece: String) -> Node3D:
	var scene := load("%s/%s.tscn" % [FIXTURES, piece]) as PackedScene
	assert_object(scene).override_failure_message(piece).is_not_null()
	var node := scene.instantiate() as Node3D
	add_child(node)
	auto_free(node)
	return node


## The walls build's own pieces: the keys of its report. Every kit group writes its fixtures into
## the same folder and checks its own list (the props: test_smallmap_props.gd).
func _pieces() -> PackedStringArray:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	var out := PackedStringArray()
	for piece: String in report:
		out.append(piece)
	return out


func _box(shape: Node3D, size: Vector3) -> AABB:
	return AABB(shape.position - size / 2.0, size)


## The CSG boxes of a fixture (what the navigation bakes and the camera hits), in its own frame.
func _csg(root: Node3D) -> Array[AABB]:
	var out: Array[AABB] = []
	for node in root.find_children("*", "CSGBox3D", false, false):
		var box := node as CSGBox3D
		if box.use_collision:
			out.append(_box(box, box.size))
	return out


func _opening(size: Vector3) -> AABB:
	# Shrunk by a millimetre so boxes that touch its edges do not count as inside it.
	return AABB(
		Vector3(-size.x / 2.0 + MM, size.z + MM, -1.0),
		Vector3(size.x - 2 * MM, size.y - 2 * MM, 2.0)
	)


func test_the_kit_has_its_thirteen_pieces_and_every_fixture_has_a_model_and_collision() -> void:
	var pieces := _pieces()
	for piece: String in [
		"wall_door_narrow",
		"door_purchase",
		"wall_opening_wide",
		"wall_arch",
		"wall_window_zombie",
		"window_board",
		"wall_window_glazed",
		"wall_barred",
		"wall_broken",
		"pillar",
		"beam_2",
		"trim_corner",
		"floor_edge_broken",
	]:
		assert_bool(pieces.has(piece)).override_failure_message(piece).is_true()
	for piece in pieces:
		var root := _fixture(piece)
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).override_failure_message(piece).is_greater(0)
		var solids := root.find_children("*", "CollisionShape3D", true, false).size()
		solids += _csg(root).size()
		assert_int(solids).override_failure_message(piece).is_greater(0)
		for node in root.find_children("*", "CSGShape3D", true, false):
			assert_bool((node as CSGShape3D).visible).override_failure_message(piece).is_false()


func test_doorways_keep_their_clear_opening() -> void:
	for piece: String in DOORWAYS:
		var size: Vector3 = DOORWAYS[piece]
		var root := _fixture(piece)
		var boxes := _csg(root)
		for box in boxes:
			assert_bool(box.intersects(_opening(size))).override_failure_message(piece).is_false()
		# and no wider: the jambs reach the opening's edges
		var wider := _opening(Vector3(size.x + 0.1, size.y, size.z))
		assert_bool(boxes.any(func(b: AABB) -> bool: return b.intersects(wider))).is_true()


func test_zombie_windows_have_a_player_only_blocker_the_navigation_never_sees() -> void:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as CollisionObject3D
	auto_free(player)
	assert_int(player.collision_mask & BOARD_LAYER).is_equal(BOARD_LAYER)
	# A player clears the sill with a jump: the blocker is what keeps them in.
	assert_float(PlayerTuning.new().jump_height).is_greater(WINDOW.z)
	for piece in ZOMBIE_WINDOWS:
		var root := _fixture(piece)
		for box in _csg(root):
			assert_bool(box.intersects(_opening(WINDOW))).override_failure_message(piece).is_false()
		var blocker := root.get_node("PlayerBlocker") as StaticBody3D
		assert_int(blocker.collision_layer).is_equal(BOARD_LAYER)
		assert_int(blocker.collision_mask).is_equal(0)
		var shape := (blocker.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
		var covered := _box(blocker, shape.size)
		assert_float(covered.size.x).is_equal_approx(WINDOW.x, MM)
		assert_float(covered.size.y).is_equal_approx(WINDOW.y, MM)
		assert_float(covered.position.y).is_equal_approx(WINDOW.z, MM)
		assert_int(root.find_children("BoardSlot*", "Marker3D", false, false).size()).is_equal(5)


func test_window_boards_work_in_a_barricade() -> void:
	var window := _fixture("wall_window_zombie")
	var barricade := Barricade.new()
	var slots := window.find_children("BoardSlot*", "Marker3D", false, false)
	for i in slots.size():
		var board := (load(FIXTURES + "/window_board.tscn") as PackedScene).instantiate() as Node3D
		board.name = "Board%d" % (i + 1)
		board.transform = (slots[i] as Marker3D).transform
		barricade.add_child(board)
	window.add_child(barricade)
	assert_int(barricade.capacity()).is_equal(5)
	var first := barricade.get_child(0) as StaticBody3D
	assert_int(first.collision_layer).is_equal(BOARD_LAYER)
	var shape := (first.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
	assert_vector(shape.size).is_equal_approx(Vector3(1.5, 0.19, 0.05), Vector3.ONE * MM)
	assert_object((first.get_node("Mesh") as MeshInstance3D).mesh).is_not_null()
	barricade.set_boards(2, false)
	assert_int(barricade.boards()).is_equal(2)


func test_every_piece_is_within_its_triangle_budget() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	for piece in _pieces():
		assert_bool(report.has(piece)).override_failure_message(piece).is_true()
		var info: Dictionary = report[piece]
		assert_int(int(info["tris"])).override_failure_message(piece).is_less_equal(
			int(info["budget"])
		)
		# The report counts what Godot draws.
		var tris := 0
		for node in _fixture(piece).find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var indices = arrays[Mesh.ARRAY_INDEX]
				if indices == null:
					tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				else:
					tris += (indices as PackedInt32Array).size() / 3
		assert_int(tris).override_failure_message(piece).is_equal(int(info["tris"]))
