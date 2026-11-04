extends GdUnitTestSuite
## Every barricade on both maps is a window, never a door (#915): an opening that does not reach
## the floor, over a sill the dead climb in over, that a player cannot go through whatever the
## boards do. A door-shaped gap tells the player they could walk through it. The generators build
## the opening (`tools/world/build_greybox.py`, `build_smallmap_greybox.py`); this walks every
## barricade the scenes have, so a breach added later is held to the same.

const LOT := "res://world/drive_in_greybox.tscn"
const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
## The physics layers a player's body meets: the world and the boards' layer.
const PLAYER_MASK := 1 | Barricade.BOARD_LAYER
## A sill is waist high: under the player's jump (so it is a ledge, not a wall) and over a knee.
const SILL_MIN := 0.7
## Heights above the floor at which a body trying to walk through the opening is tested.
const BELOW_SILL := 0.4
const IN_OPENING := 1.5
## How far either side of the barricade the test walks (m).
const SPAN := 1.5


func _map(path: String) -> Node3D:
	var map := auto_free((load(path) as PackedScene).instantiate()) as Node3D
	add_child(map)
	return map


func _barricades(map: Node3D) -> Array[Barricade]:
	var found: Array[Barricade] = []
	for node in map.find_children("*", "Barricade", true, false):
		found.append(node as Barricade)
	return found


## Whether a ray along the barricade's way in, `height` above its floor, meets a solid a player
## collides with.
func _blocks(barricade: Barricade, height: float) -> bool:
	var inward := barricade.inward()
	var from := barricade.global_position + Vector3.UP * height - inward * SPAN
	var to := barricade.global_position + Vector3.UP * height + inward * SPAN
	var query := PhysicsRayQueryParameters3D.create(from, to, PLAYER_MASK)
	var space := barricade.get_world_3d().direct_space_state
	return not space.intersect_ray(query).is_empty()


func _each_barricade(path: String, at_least: int) -> void:
	var map := _map(path)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var barricades := _barricades(map)
	assert_int(barricades.size()).is_greater_equal(at_least)
	var jump := PlayerTuning.new().jump_height
	for barricade in barricades:
		var label := String(barricade.barricade_id)
		barricade.set_boards(0, false)  # the worst case: nothing across it
		(
			assert_float(barricade.sill)
			. override_failure_message("%s has no sill" % label)
			. is_greater_equal(SILL_MIN)
		)
		(
			assert_float(barricade.sill)
			. override_failure_message("%s's sill is a wall" % label)
			. is_less(jump)
		)
		assert_float(barricade.thickness).override_failure_message(label).is_greater(0.0)
		for height: float in [BELOW_SILL, barricade.sill + 0.3, IN_OPENING]:
			(
				assert_bool(_blocks(barricade, height))
				. override_failure_message("%s: a player walks in at %.1f m" % [label, height])
				. is_true()
			)
		_assert_not_in_the_walking_mesh(map, barricade)


## The sill is not part of what the navigation mesh is baked from, or the dead would have no way
## in: no collision CSG box of the map stands in the opening above the ground.
func _assert_not_in_the_walking_mesh(map: Node3D, barricade: Barricade) -> void:
	var inside := barricade.global_position + Vector3.UP * (barricade.sill * 0.5)
	for node in map.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if not shape.use_collision:
			continue
		var box := shape.global_transform * shape.get_aabb()
		(
			assert_bool(box.has_point(inside))
			. override_failure_message(
				(
					"%s: %s is in the opening, so the dead have no way in"
					% [barricade.barricade_id, shape.name]
				)
			)
			. is_false()
		)


func test_every_drive_in_breach_is_a_window() -> void:
	await _each_barricade(LOT, 6)


func test_every_second_map_entry_is_a_window() -> void:
	await _each_barricade(SMALL, 12)
	assert_int(_barricades(_map(SMALL)).size()).is_equal(12)
