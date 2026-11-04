# Every repairable entry on both maps shows the same faint outline of the boards it is missing,
# drawn by the `Barricade` itself (not by a window's moon shaft, which only six of the second map's
# windows have): a drawn ghost of each torn board in its slot, none when the board is back, one
# shared material and one draw call a barricade.
extends GdUnitTestSuite

const LOT := "res://world/drive_in_greybox.tscn"
const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
const BOARDS := 5
## The second map's windows and its breach, and the drive-in's fence breaches.
const SMALL_ENTRIES := 12
const LOT_ENTRIES := 6
## The drawn face sits this near the board's own front face (m).
const NEAR := 0.02


func _barricades(path: String) -> Array[Barricade]:
	var map := auto_free((load(path) as PackedScene).instantiate()) as Node3D
	add_child(map)
	var found: Array[Barricade] = []
	for node in map.find_children("*", "Barricade", true, false):
		found.append(node as Barricade)
	return found


func test_the_second_map_has_an_outline_at_each_of_its_entries() -> void:
	var entries := _barricades(SMALL)
	assert_int(entries.size()).is_equal(SMALL_ENTRIES)
	for entry in entries:
		_walk(entry)


func test_the_drive_in_has_an_outline_at_each_of_its_breaches() -> void:
	var entries := _barricades(LOT)
	assert_int(entries.size()).is_equal(LOT_ENTRIES)
	for entry in entries:
		_walk(entry)


## The outline at every count: none at full, one quad per missing board below.
func _walk(entry: Barricade) -> void:
	var label := String(entry.barricade_id)
	var outline := entry.outline()
	assert_object(outline).override_failure_message(label).is_not_null()
	assert_int(entry.capacity()).override_failure_message(label).is_equal(BOARDS)
	assert_bool(outline.visible).override_failure_message("%s full" % label).is_false()
	assert_int(outline.quads()).override_failure_message("%s full" % label).is_equal(0)
	assert_object(outline.material_override).is_same(BoardOutline.material())
	for up in range(BOARDS - 1, -1, -1):
		entry.set_boards(up, false)
		var message := "%s at %d boards" % [label, up]
		assert_bool(outline.visible).override_failure_message(message).is_true()
		assert_int(outline.quads()).override_failure_message(message).is_equal(BOARDS - up)
		assert_int(outline.mesh.get_surface_count()).is_equal(1)
	entry.set_boards(BOARDS, false)
	assert_bool(outline.visible).override_failure_message("%s mended" % label).is_false()
	assert_int(outline.quads()).is_equal(0)


func test_the_ghost_of_a_board_is_drawn_on_the_boards_own_face() -> void:
	for entry in _barricades(SMALL) + _barricades(LOT):
		var outline := entry.outline()
		for index in BOARDS:
			var face := outline.face(index)
			assert_int(face.size()).is_equal(4)
			var mesh := entry.board_mesh(index)
			var box := mesh.mesh.get_aabb()
			var to_barricade := (
				(mesh.get_parent() as Node3D).transform * entry.board_mesh_rest(index)
			)
			# The corners are the front face of the mesh's box, a hair out, in the barricade's space.
			for corner in face:
				var local := to_barricade.affine_inverse() * corner
				assert_float(local.z).is_equal_approx(
					box.position.z + box.size.z + BoardOutline.LIFT, NEAR
				)
				assert_float(absf(local.x)).is_less_equal(box.size.x * 0.5 + NEAR)
				assert_float(absf(local.y)).is_less_equal(box.size.y * 0.5 + NEAR)


func test_only_the_boards_below_the_count_are_left_out() -> void:
	var entry := _barricades(SMALL)[0]
	entry.set_boards(2, false)
	var outline := entry.outline()
	assert_int(outline.quads()).is_equal(3)
	# The three quads are the top three boards': their vertices lie over those boards' slots.
	var vertices := outline.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for quad in 3:
		var drawn := vertices[quad * 4]
		var slot := outline.face(2 + quad)[0]
		assert_vector(drawn).is_equal_approx(slot, Vector3.ONE * 0.001)


func test_a_barricade_of_boards_without_meshes_draws_nothing_and_does_not_fail() -> void:
	var bare := Barricade.new()
	for i in BOARDS:
		var body := StaticBody3D.new()
		bare.add_child(body)
	add_child(bare)
	auto_free(bare)
	bare.set_boards(0, false)
	assert_int(bare.outline().quads()).is_equal(0)


## The maintainer's rule (#902): the outline is one shape a plank slot, and a slot's shape goes when
## its plank is on. Planks go on from the bottom, so with `up` planks on the outline is the top
## slots above them, on every entry.
func test_each_plank_nailed_on_removes_the_lowest_slot_left_bottom_to_top() -> void:
	for entry in _barricades(SMALL) + _barricades(LOT):
		var outline := entry.outline()
		entry.set_boards(0, false)
		for up in range(1, BOARDS + 1):
			entry.set_boards(up)  # a mend, as the rules' repair events send it: one more plank
			entry.finish_motion()
			var message := "%s with %d planks on" % [entry.barricade_id, up]
			assert_int(outline.quads()).override_failure_message(message).is_equal(BOARDS - up)
			if up == BOARDS:
				continue
			var vertices := (
				outline.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
			)
			for quad in BOARDS - up:
				assert_vector(vertices[quad * 4]).override_failure_message(message).is_equal_approx(
					outline.face(up + quad)[0], Vector3.ONE * 0.001
				)
			# The slot of a plank that is on never has a shape, and the planks on are the lowest.
			for slot in BOARDS:
				var plank := entry.get_child(slot) as StaticBody3D
				assert_bool(plank.visible).override_failure_message(message).is_equal(slot < up)
