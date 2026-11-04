# Nobody leaves the lot or gets into a closed area by climbing the props beside the walls (#848).
# The map review (#833) found three ways by running the real player body, and the reach tests of the
# time caught none: a crate and a container over the plaza's corner (#845), barrels and a dumpster
# over the midway's west fence (#846), and the second map's counter (#847). The body climbs 1.25 m
# (`CameraProbe.BODY_REACH`), not the jump's 1.1 m, and a prop that is itself a step brings a wall
# within reach. This runs the real body (`EscapeSweep`, the method of
# `tools/world/map_escape_probe.gd` trimmed to the props within 6 m of a perimeter wall, a closed
# door's slab or a closed area's wall) with the doors in each of the nine sets the shop can sell,
# and fails on any standing place beyond the map, inside a closed area or on top of a wall.
# Its first run found a fourth way out: a car's hood, its roof (1.64 m), the top of the small tree's
# trunk by the screen (a 2.4 m post, "above a jump"), and over the 3.0 m north fence. The trunks are
# 4.0 m now (`TRUNK_HEIGHT` in tools/world/lot_props.py).
extends GdUnitTestSuite

## Hops in a chain at most: the ways out the review found took three.
const DEPTH := 3
## The areas a standing place can be in, in the order they are asked: the booth before the midway,
## whose ground runs under it, and the field last.
const AREAS := [
	"ProjectionBooth", "Concession", "Road", "GeneratorYard", "BackLot", "Midway", "Field"
]
## An area's box runs from under its floor to over any wall top.
const BOX_FLOOR := -0.3
const BOX_TOP := 8.0
## The way out over the north fence by the screen, before the trunks were raised (#848), hop by hop:
## [start, yaw, sprinting, the tick the jump is pressed]; the first starts on Car22's hood, each
## later one where the one before landed.
const OLD_TREE_CHAIN := [
	[Vector3(-26.08, 1.0, -48.25), 2.3562, false, 0],
	[Vector3.INF, -0.7854, true, 20],
	[Vector3.INF, 0.0, true, 9],
]
## A trunk's top stands this far over the reach above the tallest prop near it.
const TRUNK_MARGIN := 0.5
## A prop this near a trunk (between their edges) is a step towards it: a sprint-jump from a car
## roof crossed 4.6 m.
const TRUNK_NEAR := 6.0
## A top this high or lower can be stood on (from a step); anything taller is a wall.
const STANDABLE := 2.0
## The booth's two floors: the ramp up the west wall to the landing (no one floor), the upper floor
## (3.9 m) and the ground floor under it.
const BOOTH_RAMP := AABB(Vector3(-5.8, -0.3, 22.0), Vector3(2.4, 4.5, 10.0))
const BOOTH_UPPER_FROM := 3.5
const BOOTH_UPPER_FLOOR := 3.9


func test_no_prop_beside_a_wall_is_a_way_out_for_any_set_of_doors() -> void:
	var cache := {}
	var all_slabs: Array[AABB] = []
	var all_doors: Array = LotFixture.door_table().keys()
	var slab_count := {}
	var started := Time.get_ticks_msec()
	var total_hops := 0
	var total_starts := 0
	for sold: Array in LotFixture.sold_sets():
		var lot := await LotFixture.make_lot(self, sold)
		if all_slabs.is_empty():
			# The first set is none sold: every slab is still there.
			for door: String in all_doors:
				var slabs := LotFixture.slabs(lot, [door])
				slab_count[door] = slabs.size()
				for slab in slabs:
					all_slabs.append(EscapeSweep.bounds_of(slab))
		var present: Array[bool] = []
		for door: String in all_doors:
			for _i in slab_count[door]:
				present.append(not sold.has(door))
		var sweep := EscapeSweep.new(
			lot, _areas(lot, sold), _barriers(lot, sold), all_slabs, present, cache
		)
		var found := sweep.run(DEPTH)
		print(
			(
				"sold %s: %d starts, %d hops run, %d standing places, %d found, %d ms"
				% [
					sold,
					sweep.starts,
					sweep.hops,
					sweep.places,
					found.size(),
					Time.get_ticks_msec() - started
				]
			)
		)
		total_hops += sweep.hops
		total_starts += sweep.starts
		sweep.free_body()
		lot.get_parent().free()
		(
			assert_array(found)
			. override_failure_message("sold %s: %s" % [sold, "\n".join(found)])
			. is_empty()
		)
	# The sweep must have looked: props stand beside every wall of the lot.
	assert_int(total_starts).is_greater(100)
	assert_int(total_hops).is_greater(1000)


func test_the_old_hops_from_a_car_roof_over_the_tree_no_longer_leave_the_lot() -> void:
	var lot := await LotFixture.make_lot(self, [])
	var sweep := EscapeSweep.new(lot, _areas(lot, []), [], [], [], {})
	var at := Vector3.INF
	for hop: Array in OLD_TREE_CHAIN:
		var from: Vector3 = hop[0] if at == Vector3.INF else at
		var landed := sweep.hop(from, hop[1], hop[2], hop[3])
		at = landed if landed != Vector3.INF else from
	var verdict := sweep.judge(at)
	sweep.free_body()
	lot.get_parent().free()
	(
		assert_str(verdict)
		. override_failure_message("the old chain ends at %s: %s" % [at, verdict])
		. is_empty()
	)


func test_every_trunk_stands_out_of_reach_of_the_props_beside_it() -> void:
	var lot := await LotFixture.make_lot(self, [])
	var needed := CameraProbe.BODY_REACH + TRUNK_MARGIN
	var trunks := 0
	for node in lot.find_children("Blocker", "CSGCylinder3D", true, false):
		var trunk := node as CSGCylinder3D
		if not String(trunk.get_parent().name).begins_with("Tree"):
			continue
		trunks += 1
		var top := trunk.global_position.y + trunk.height * 0.5
		var at := trunk.global_position
		var tallest := 0.0
		for other in lot.find_children("*", "CSGShape3D", true, false):
			var shape := other as CSGShape3D
			if not shape.use_collision or shape == trunk:
				continue
			var bounds := _bounds(shape)
			var gap := (
				Vector2(
					maxf(maxf(bounds.position.x - at.x, at.x - bounds.end.x), 0.0),
					maxf(maxf(bounds.position.z - at.z, at.z - bounds.end.z), 0.0)
				)
				. length()
			)
			if gap <= TRUNK_NEAR and bounds.end.y <= STANDABLE and bounds.size.y > 0.3:
				tallest = maxf(tallest, bounds.end.y)
		(
			assert_float(top - tallest)
			. override_failure_message(
				(
					"%s: top %.2f, a prop %.2f high within %.0f m"
					% [trunk.get_path(), top, tallest, TRUNK_NEAR]
				)
			)
			. is_greater_equal(needed)
		)
	lot.get_parent().free()
	assert_int(trunks).is_greater(10)


func _bounds(shape: CSGShape3D) -> AABB:
	if shape is CSGBox3D:
		return EscapeSweep.bounds_of(shape)
	if shape is CSGCylinder3D:
		var cylinder := shape as CSGCylinder3D
		var size := Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
		return shape.global_transform * AABB(-size * 0.5, size)
	return AABB(shape.global_position, Vector3.ZERO)


## Every area as boxes from its footprint, open or not with `sold`.
func _areas(lot: Node3D, sold: Array) -> Array:
	var areas: Array = []
	for name: String in AREAS:
		var boxes: Array[AABB] = []
		for rect in LotFixture.footprint(lot, name):
			boxes.append(
				AABB(
					Vector3(rect.position.x, BOX_FLOOR, rect.position.y),
					Vector3(rect.size.x, BOX_TOP - BOX_FLOOR, rect.size.y)
				)
			)
		var open := LotFixture.is_open(name, sold)
		if name == "ProjectionBooth":
			var ramp: Array[AABB] = [BOOTH_RAMP]
			var upper: Array[AABB] = []
			var lower: Array[AABB] = []
			for box in boxes:
				upper.append(
					AABB(
						Vector3(box.position.x, BOOTH_UPPER_FROM, box.position.z),
						Vector3(box.size.x, BOX_TOP - BOOTH_UPPER_FROM, box.size.z)
					)
				)
				lower.append(
					AABB(
						box.position, Vector3(box.size.x, BOOTH_UPPER_FROM - BOX_FLOOR, box.size.z)
					)
				)
			areas.append({"name": name, "boxes": ramp, "floor": NAN, "open": open})
			areas.append({"name": name, "boxes": upper, "floor": BOOTH_UPPER_FLOOR, "open": open})
			boxes = lower
		areas.append({"name": name, "boxes": boxes, "floor": 0.0, "open": open})
	return areas


## What a player must not get over with `sold`: the perimeter, the fences between the field and the
## yard and back lot, the closed doors' slabs and the closed areas' walls.
func _barriers(lot: Node3D, sold: Array) -> Array[AABB]:
	var boxes: Array[CSGBox3D] = LotFixture.perimeter(lot)
	var closed := LotFixture.closed_doors(sold)
	boxes.append_array(LotFixture.slabs(lot, closed))
	for area: String in LotFixture.AREA_DOOR:
		if not LotFixture.is_open(area, sold):
			boxes.append_array(LotFixture.walls_of(lot.get_node(area)))
	for fence in lot.get_node("Field").get_children():
		if fence is CSGBox3D and String(fence.name).begins_with("FenceS"):
			boxes.append(fence)
	var bounds: Array[AABB] = []
	for box in boxes:
		bounds.append(EscapeSweep.bounds_of(box))
	return bounds
