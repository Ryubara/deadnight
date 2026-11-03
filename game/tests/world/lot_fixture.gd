class_name LotFixture
extends RefCounted
## Shared helpers for the lot's world suites: a greybox in a world of its own whose doors are sold
## through the rules and opened by the game's own `LotDoors`, the areas' footprints and sample
## points, and the sets of doors the shop can have sold.

const SCENE := "res://world/drive_in_greybox.tscn"
const START := Vector3(0, 0, -43)  # the apron below the screen
const REACHED := 1.0  # metres: a point on a navigation mesh is this close to its sample
## Open ground in each area (at least three each; the all-open test checks every one is reachable).
const AREA_POINTS := {
	"Field": [Vector3(0, 0, -30), Vector3(-40, 0, -30), Vector3(40, 0, -30), Vector3(0, 0, -10)],
	"Concession": [Vector3(0, 0, 5.5), Vector3(-7, 0, -1.5), Vector3(7, 0, 6.0)],
	"Midway": [Vector3(-10, 0, 30), Vector3(0, 0, 34), Vector3(-13, 0, 2), Vector3(13, 0, 2)],
	"ProjectionBooth": [Vector3(0, 0, 25), Vector3(0, 0, 28), Vector3(-3, 0, 30)],
	"GeneratorYard": [Vector3(30, 0, 18), Vector3(56, 0, 0), Vector3(22, 0, 34)],
	"BackLot": [Vector3(-30, 0, 26), Vector3(-56, 0, 0), Vector3(-22, 0, 34)],
	"Road": [Vector3(0, 0, 41), Vector3(-10, 0, 50), Vector3(10, 0, 55), Vector3(0, 0, 56)],
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
## The ground boxes (by name prefix) that make up an area's footprint.
const GROUND_PREFIXES := {
	"Field": ["Ground"],
	"Concession": ["Floor"],
	"Midway": ["Ground", "AlleyW", "AlleyE"],
	"ProjectionBooth": ["Floor"],
	"GeneratorYard": ["Ground"],
	"BackLot": ["Ground"],
	"Road": ["Plaza"],
}
const SETTLE_FRAMES := 3
const POINTS_PER_PLAYER := 10000


## The greybox in a SubViewport of its own under `host` (so its navigation map and physics space are
## its own), with `sold` bought through a `GameRules` the lot's doors follow. Returns the lot; the
## rules are its `rules` meta, the viewport is `lot.get_parent()` (free that to drop the lot).
static func make_lot(host: Node, sold: Array = []) -> Node3D:
	var world := SubViewport.new()
	world.own_world_3d = true
	host.add_child(world)
	var lot := load(SCENE).instantiate() as Node3D
	world.add_child(lot)
	var rules := RulesFixture.make_rules(1)
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.grant_points(1, POINTS_PER_PLAYER))
	(lot.get_node("Doors") as LotDoors).bind(rules)
	lot.set_meta(&"rules", rules)
	for item: StringName in in_buying_order(sold):
		var result := RulesFixture.buy(rules, 1, item)
		assert(result == GameRules.BuyResult.OK, "could not buy %s: %d" % [item, result])
	var tree := host.get_tree()
	await tree.process_frame
	await tree.process_frame
	for i in SETTLE_FRAMES:
		await tree.physics_frame
	return lot


## `sold` sorted so that every door follows the one it needs.
static func in_buying_order(sold: Array) -> Array[StringName]:
	var table := door_table()
	var ordered: Array[StringName] = []
	while ordered.size() < sold.size():
		var progressed := false
		for item: String in sold:
			var needs: String = table[item]
			if (
				not ordered.has(StringName(item))
				and (needs == "" or ordered.has(StringName(needs)))
			):
				ordered.append(StringName(item))
				progressed = true
		assert(progressed, "a sold door's prerequisite is not sold: %s" % [sold])
		if not progressed:
			break
	return ordered


## Shop id -> the shop id it needs, for every door of the scene.
static func door_table() -> Dictionary:
	var scene := load(SCENE).instantiate() as Node3D
	var table := {}
	for door: Node in scene.get_node("Doors").get_children():
		table[door.get_meta("shop_id")] = door.get_meta("requires")
	scene.free()
	return table


## Every set of sold doors in which each sold door's prerequisite is sold too (what the shop
## allows): nothing, the concession alone, the concession and any mix of the rest (nine).
static func sold_sets() -> Array:
	var table := door_table()
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


## Whether `area` can be walked into once `sold` doors are open.
static func is_open(area: String, sold: Array) -> bool:
	return area == "Field" or sold.has(AREA_DOOR[area])


## The doors not in `sold`.
static func closed_doors(sold: Array) -> Array[String]:
	var closed: Array[String] = []
	for item: String in door_table():
		if not sold.has(item):
			closed.append(item)
	return closed


## The area's ground as rectangles on the ground plane (x, z), read from its ground boxes.
static func footprint(lot: Node3D, area: String) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in lot.get_node(area).get_children():
		if not child is CSGBox3D:
			continue
		for prefix: String in GROUND_PREFIXES[area]:
			if String(child.name).begins_with(prefix):
				var box := child as CSGBox3D
				var centre := box.global_position
				rects.append(
					Rect2(
						centre.x - box.size.x * 0.5,
						centre.z - box.size.z * 0.5,
						box.size.x,
						box.size.z
					)
				)
	return rects


## True when `point` is inside one of `rects`, shrunk by `inset` metres on every side.
static func inside(rects: Array[Rect2], point: Vector3, inset: float = 0.05) -> bool:
	for rect in rects:
		if rect.grow(-inset).has_point(Vector2(point.x, point.z)):
			return true
	return false


## A grid of points `step` metres apart over the footprint, on the ground.
static func grid(rects: Array[Rect2], step: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for rect in rects:
		var x := rect.position.x + step * 0.5
		while x < rect.end.x:
			var z := rect.position.y + step * 0.5
			while z < rect.end.y:
				points.append(Vector3(x, 0.0, z))
				z += step
			x += step
	return points


## Points along `path`, at most `step` metres apart, corners included.
static func along(path: PackedVector3Array, step: float = 0.25) -> PackedVector3Array:
	var samples := PackedVector3Array()
	for i in path.size():
		samples.append(path[i])
		if i > 0:
			var length := path[i - 1].distance_to(path[i])
			for n in range(1, int(length / step)):
				samples.append(path[i - 1].lerp(path[i], n * step / length))
	return samples
