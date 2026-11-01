# The lot's opening order (docs/design/map.md): with every set of doors the shop can have sold, a
# player reaches exactly the areas those doors open. The proof is a baked navigation mesh, not a ray
# per door.
extends GdUnitTestSuite

const SCENE := "res://world/drive_in_greybox.tscn"
## A point on open ground in each area (the test checks they are reachable when everything is open).
const AREA_POINTS := {
	"Field": Vector3(0, 0, -30),
	"Concession": Vector3(0, 0, 5.5),
	"Midway": Vector3(-10, 0, 30),
	"ProjectionBooth": Vector3(0, 0, 25),
	"GeneratorYard": Vector3(30, 0, 18),
	"BackLot": Vector3(-30, 0, 26),
	"Road": Vector3(0, 0, 44),
}
## The shop item whose door opens each area; the concession also opens the midway behind it.
const AREA_DOOR := {
	"Concession": "door_concession",
	"Midway": "door_concession",
	"ProjectionBooth": "door_booth",
	"GeneratorYard": "door_yard",
	"BackLot": "door_back_lot",
	"Road": "door_road",
}
const START := Vector3(0, 0, -43)  # the apron below the screen
const REACHED := 1.0  # metres: a point on the navigation mesh is this close to its sample
const MISSED := 2.0  # metres: an area behind a closed door stays at least this far away


func test_every_area_is_reachable_with_all_doors_open() -> void:
	var lot := await _lot([])
	var nav := LotNavigation.new(lot, CameraProbe.BODY_RADIUS)
	await nav.settle(get_tree())
	for area: String in AREA_POINTS:
		(
			assert_bool(nav.can_reach(START, AREA_POINTS[area], REACHED))
			. override_failure_message(area)
			. is_true()
		)


func test_each_area_is_reached_only_through_its_door() -> void:
	var doors := _door_table()
	var sold_sets := _closed_sets(doors)
	# Nothing, the concession alone, the concession and any mix of the rest that the prerequisites
	# allow (nine).
	assert_int(sold_sets.size()).is_equal(9)
	for sold: Array in sold_sets:
		var closed: Array[String] = []
		for item: String in doors:
			if not sold.has(item):
				closed.append(item)
		var lot := await _lot(closed)
		var nav := LotNavigation.new(lot, CameraProbe.BODY_RADIUS)
		await nav.settle(get_tree())
		for area: String in AREA_POINTS:
			var open: bool = area == "Field" or sold.has(AREA_DOOR[area])
			var message := "sold %s, area %s" % [sold, area]
			if open:
				(
					assert_bool(nav.can_reach(START, AREA_POINTS[area], REACHED))
					. override_failure_message(message)
					. is_true()
				)
			else:
				var gap := nav.nearest_approach(START, AREA_POINTS[area])
				assert_float(gap).override_failure_message(message).is_greater(MISSED)
		lot.get_parent().queue_free()
		await get_tree().process_frame


func test_the_camera_gets_everywhere_the_player_does() -> void:
	# An agent as wide as the shoulder camera's reach on either side of the player (0.75 m + 0.1 m
	# of air, rounded up): if a passage were narrower than 1.8 m, this agent could not cross it and
	# an area would drop out.
	var lot := await _lot([])
	var nav := LotNavigation.new(lot, CameraProbe.SHOULDER + CameraProbe.CAMERA_CLEAR + 0.05)
	await nav.settle(get_tree())
	for area: String in AREA_POINTS:
		(
			assert_bool(nav.can_reach(START, AREA_POINTS[area], REACHED))
			. override_failure_message(area)
			. is_true()
		)


## Instantiates the greybox in a world of its own (so its navigation map is its own) with the named
## doors still closed and every other door removed (sold), built and ready.
func _lot(closed: Array[String]) -> Node3D:
	var world := SubViewport.new()
	world.own_world_3d = true
	auto_free(world)
	add_child(world)
	var lot := load(SCENE).instantiate() as Node3D
	for door: Node in lot.get_node("Doors").get_children():
		if not closed.has(door.get_meta("shop_id")):
			door.free()
	world.add_child(lot)
	await get_tree().process_frame
	await get_tree().process_frame
	for i in 3:
		await get_tree().physics_frame
	return lot


## Shop id -> the shop id it needs, for every door of the scene.
func _door_table() -> Dictionary:
	var scene := load(SCENE).instantiate() as Node3D
	var table := {}
	for door: Node in scene.get_node("Doors").get_children():
		table[door.get_meta("shop_id")] = door.get_meta("requires")
	scene.free()
	return table


## Every set of sold doors in which each sold door's prerequisite is sold too (what the shop
## allows).
func _closed_sets(table: Dictionary) -> Array:
	var ids := table.keys()
	var sets := []
	for mask in 1 << ids.size():
		var sold := []
		for i in ids.size():
			if mask & (1 << i):
				sold.append(ids[i])
		var allowed := true
		for item: String in sold:
			var needs: String = table[item]
			if needs != "" and not sold.has(needs):
				allowed = false
		if allowed:
			sets.append(sold)
	return sets
