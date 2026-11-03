extends SceneTree
## Measures the drive-in greybox for the map doc (docs/design/map.md): how much ground each
## circuit lights, how much of each area is lit, where the dead can appear and how far from a
## lamp, how far a door is from light and from the breaches, and where lit ground is far from
## every open spawn.
##
##   godot --headless --path game -s res://tools/lot/lot_report.gd
##
## "Lit" is the rules' word (`LotLamps.lit_at`): ground within `LightTuning.lamp_reach` of a lamp
## whose circuit is on, counted on a grid over each area's floor. A capture's glow reaches further.

const GREYBOX := preload("res://world/drive_in_greybox.tscn")
## Grid step in metres.
const STEP := 0.5
## A pocket is lit ground at least this far from every open spawn, in metres.
const POCKET_DISTANCE := 30.0
const POCKET_STEP := 1.0
## Each area's floor as rectangles [x0, x1, z0, z1] (tools/world/build_greybox.py).
const AREAS := {
	&"Field": [[-62.0, 62.0, -52.0, -4.0]],
	&"Concession": [[-10.0, 10.0, -4.0, 8.0]],
	&"Midway": [[-16.0, 16.0, 8.0, 38.0], [-16.0, -10.0, -4.0, 8.0], [10.0, 16.0, -4.0, 8.0]],
	&"ProjectionBooth": [[-6.0, 6.0, 22.0, 32.0]],
	&"GeneratorYard": [[16.0, 62.0, -4.0, 38.0]],
	&"BackLot": [[-62.0, -16.0, -4.0, 38.0]],
	&"Road": [[-16.0, 16.0, 38.0, 58.0]],
}
const CIRCUITS: Array[StringName] = [
	&"screen_lot", &"concession", &"booth", &"back_lot", &"mains", &"battery"
]
## The areas whose spawns are in the pool once each door is bought, in opening order.
const OPEN_BY_DOOR := [
	[&"start", [&"Field"]],
	[&"concession", [&"Field", &"Midway"]],
	[&"yard", [&"Field", &"Midway", &"GeneratorYard"]],
	[&"booth", [&"Field", &"Midway", &"GeneratorYard", &"ProjectionBooth"]],
	[&"back lot", [&"Field", &"Midway", &"GeneratorYard", &"ProjectionBooth", &"BackLot"]],
	[
		&"road",
		[&"Field", &"Midway", &"GeneratorYard", &"ProjectionBooth", &"BackLot", &"Road"],
	],
]

var _lamps: LotLamps
var _spawns: Array[Dictionary] = []


func _init() -> void:
	var lot := GREYBOX.instantiate()
	root.add_child(lot)
	await process_frame
	await process_frame
	_lamps = LotLamps.new(lot)
	_collect_spawns(lot)
	_report_lit_shares()
	_report_circuits()
	_report_spawns()
	_report_pool_shares()
	_report_doors(lot)
	_report_pockets()
	print("cars in the rows: ", _count_cars(lot))
	quit()


func _report_lit_shares() -> void:
	print("\nLit ground per area (all circuits on / screen_lot and battery only / tank dry)")
	for area: StringName in AREAS:
		var total := _cells(area, CIRCUITS, false)
		var all_on := _cells(area, CIRCUITS, true)
		var screen := _cells(area, [&"screen_lot", &"battery"], true)
		var dry := _cells(area, [&"battery"], true)
		print(
			(
				"%s: floor %.0f m2, lit %.0f m2 (%.1f%%), screen_lot and battery only %.0f m2, dry %.0f m2"
				% [
					area,
					total,
					all_on,
					100.0 * all_on / total,
					screen,
					dry,
				]
			)
		)


func _report_circuits() -> void:
	print("\nGround each circuit lights on its own, by area (m2)")
	for circuit in CIRCUITS:
		var by_area := {}
		for area: StringName in AREAS:
			var lit := _cells(area, [circuit], true)
			if lit > 0.0:
				by_area[area] = lit
		print(circuit, " ", by_area)


func _report_spawns() -> void:
	print("\nSpawns (area, name, position, metres to the nearest lamp of any circuit)")
	for spawn in _spawns:
		print(
			(
				"%s %s %s %.1f"
				% [
					spawn["area"],
					spawn["name"],
					spawn["position"],
					_nearest_lamp(spawn["position"], CIRCUITS)
				]
			)
		)


func _report_pool_shares() -> void:
	print("\nShare of the spawn pool at the field's breaches, as each door is bought")
	for step: Array in OPEN_BY_DOOR:
		var open: Array = step[1]
		var pool := 0
		var field := 0
		for spawn in _spawns:
			if open.has(spawn["area"]):
				pool += 1
				if spawn["area"] == &"Field":
					field += 1
		print(
			(
				"%s: %d spawns, %d at the breaches (%.0f%%)"
				% [step[0], pool, field, 100.0 * field / pool]
			)
		)


func _report_doors(lot: Node) -> void:
	print("\nDoors: slab centre, metres to the nearest lamp by circuit, to the nearest field spawn")
	for door in lot.get_node("Doors").get_children():
		var line := "%s (%s):" % [door.name, door.get_meta("cost")]
		for slab in door.get_children():
			if slab is CSGBox3D:
				var at := (slab as Node3D).global_position
				var nearest := ""
				for circuit in CIRCUITS:
					nearest += " %s %.1f" % [circuit, _nearest_lamp(at, [circuit])]
				var spawn_distance := 1e9
				for spawn in _spawns:
					if spawn["area"] == &"Field":
						spawn_distance = minf(spawn_distance, _flat(at, spawn["position"]))
				line += (
					"\n  %s %s |%s | field spawn %.1f" % [slab.name, at, nearest, spawn_distance]
				)
		print(line)
	for marker in lot.get_node("Field/PlayerSpawns").get_children():
		var at := (marker as Marker3D).global_position
		var spawn_distance := 1e9
		for spawn in _spawns:
			if spawn["area"] == &"Field":
				spawn_distance = minf(spawn_distance, _flat(at, spawn["position"]))
		print("%s %s: nearest field spawn %.1f" % [marker.name, at, spawn_distance])


func _report_pockets() -> void:
	print("\nLit ground (all circuits) at least %.0f m from every open spawn" % POCKET_DISTANCE)
	for step: Array in OPEN_BY_DOOR:
		var open: Array = step[1]
		var points: Array[Vector3] = []
		for spawn in _spawns:
			if open.has(spawn["area"]):
				points.append(spawn["position"])
		var areas: Array = open.duplicate()
		if open.has(&"Midway"):
			areas.append(&"Concession")
		for area: StringName in areas:
			var count := 0
			var sum := Vector2.ZERO
			for rect: Array in AREAS[area]:
				var x: float = rect[0] + POCKET_STEP
				while x < rect[1]:
					var z: float = rect[2] + POCKET_STEP
					while z < rect[3]:
						var at := Vector3(x, 0.0, z)
						if _is_lit(at, CIRCUITS) and _far_from_all(at, points):
							count += 1
							sum += Vector2(x, z)
						z += POCKET_STEP
					x += POCKET_STEP
			if count > 0:
				print("after %s: %s %d m2, centre %s" % [step[0], area, count, sum / count])


func _collect_spawns(lot: Node) -> void:
	for area: StringName in AREAS:
		var spawns := lot.get_node_or_null(String(area) + "/ZombieSpawns")
		if spawns == null:
			continue
		for marker in spawns.get_children():
			(
				_spawns
				. append(
					{
						"area": area,
						"name": marker.name,
						"position": (marker as Marker3D).global_position,
					}
				)
			)


## Square metres of `area`'s floor lit by `circuits` (all of the floor when `only_lit` is false).
func _cells(area: StringName, circuits: Array, only_lit: bool) -> float:
	var count := 0
	for rect: Array in AREAS[area]:
		var x: float = rect[0] + STEP / 2.0
		while x < rect[1]:
			var z: float = rect[2] + STEP / 2.0
			while z < rect[3]:
				if not only_lit or _is_lit(Vector3(x, 0.0, z), circuits):
					count += 1
				z += STEP
			x += STEP
	return count * STEP * STEP


func _is_lit(at: Vector3, circuits: Array) -> bool:
	for lamp in _lamps.lamps:
		if not lamp.decor and circuits.has(lamp.circuit):
			if _flat(at, lamp.position) < LightTuning.current().lamp_reach:
				return true
	return false


func _nearest_lamp(at: Vector3, circuits: Array) -> float:
	var best := INF
	for lamp in _lamps.lamps:
		if not lamp.decor and circuits.has(lamp.circuit):
			best = minf(best, _flat(at, lamp.position))
	return best


func _far_from_all(at: Vector3, points: Array[Vector3]) -> bool:
	for point in points:
		if _flat(at, point) < POCKET_DISTANCE:
			return false
	return true


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _count_cars(lot: Node) -> int:
	var count := 0
	for row in lot.get_node("Field/Rows").get_children():
		count += row.get_child_count()
	return count
