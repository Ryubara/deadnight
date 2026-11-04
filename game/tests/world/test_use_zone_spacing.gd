# No two interactables share ground a press reaches from (#908). Holding use at a window, the
# maintainer bought the wall weapon beside it and lost the gun in hand: the window's reach and the
# weapon's overlapped, and the press went to the weapon. Each thing's use zone is the floor a body
# can stand on from which the server would offer it (its reach on the flat, its floor, its line
# from the hand, its side: `UseZones`), and this walks a grid of that floor round every thing of
# both maps and fails on a point inside two zones. The gap the map review asks for
# (`UseZones.MIN_GAP`) is kept by growing every zone by half of it first.
extends GdUnitTestSuite

const LOT := "res://world/drive_in_greybox.tscn"
const SMALL := "res://world/smallmap/smallmap_greybox.tscn"

## Metres between the grid's points.
const STEP := 0.25
## A body's headroom and the room round it (as the use-sight test stands a body).
const HEADROOM := 1.7
const ROOM := 0.4
const SPOKES := 8
const FLOOR_SLACK := 0.3

## The second map's pairs that its rework (#917: one window a wall, the upper windows on a patio,
## each perk in its own corridor) moves apart; nothing else may overlap, and each pair comes off
## this list as the rework fixes it. The worst is the locker 1.45 m from the upper window
## `upper_a2`, with the bat on the wall beside both.
const SMALL_PENDING_917: Array[String] = [
	"ammo (12.0, 3.4, 3.2) | breach upper_a2",
	"ammo (5.0, 0.0, -1.6) | door door_stairs_start",
	"ammo (6.0, 3.4, -1.6) | tonic_third_holster (8.6, 3.4, -1.7)",
	"ammo (8.0, 0.0, 13.1) | breach start_1",
	"ammo (8.0, 0.0, 13.1) | breach start_2",
	"breach side_1 | breach side_2",
	"breach side_1 | breach side_breach",
	"breach side_2 | breach side_breach",
	"breach start_2 | breach start_5",
	"breach start_3 | breach start_4",
	"breach start_4 | breach start_5",
	"crane_play (10.5, 0.0, -5.9) | tonic_swift_rescue (7.6, 0.0, -6.3)",
	"door door_side | breach start_3",
	"door door_stairs_side | breach side_breach",
	"tonic_double_shot (12.6, 3.4, -6.4) | breach upper_b2",
	"tonic_double_shot (12.6, 3.4, -6.4) | tonic_reload_shock (15.4, 3.4, -6.4)",
	"weapon_baseball_bat (14.7, 3.4, 2.3) | ammo (12.0, 3.4, 3.2)",
	"weapon_baseball_bat (14.7, 3.4, 2.3) | breach upper_a2",
	"weapon_crowbar (1.4, 0.0, 6.0) | tonic_hearty (1.7, 0.0, 8.5)",
	"weapon_fire_axe (14.7, 3.4, -4.0) | tonic_double_shot (12.6, 3.4, -6.4)",
	"weapon_fire_axe (14.7, 3.4, -4.0) | tonic_reload_shock (15.4, 3.4, -6.4)",
	"weapon_flare_gun (1.3, 3.4, 2.3) | breach upper_a1",
	"weapon_pistol (1.4, 0.0, 11.0) | tonic_hearty (1.7, 0.0, 8.5)",
	"weapon_shotgun (5.0, 3.4, -6.5) | breach upper_b2",
	"weapon_smg (5.5, 0.0, -6.4) | tonic_quick_load (2.9, 0.0, -6.3)",
	"weapon_smg (5.5, 0.0, -6.4) | tonic_swift_rescue (7.6, 0.0, -6.3)",
]

var _night: SeatedNight
var _space: PhysicsDirectSpaceState3D


func after_test() -> void:
	if _night != null:
		_night.dispose()
		_night = null


func _start(scene_path: String) -> UseZones:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = 600.0
	_night = await NightFixture.seat(self, 1, tuning, 7, false, load(scene_path) as PackedScene)
	_space = _night.world.get_world_3d().direct_space_state
	var probe := WorldProbe.new(_space)
	return UseZones.new(_night.world, _night.server.tuning, UseSight.new(probe.static_callable()))


func _wall(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	return not _space.intersect_ray(query).is_empty()


## The ground a body stands on at `x, z` near height `y`, or `Vector3.INF`.
func _ground(x: float, z: float, y: float) -> Vector3:
	var top := Vector3(x, y + 1.2, z)
	var query := PhysicsRayQueryParameters3D.create(top, top - Vector3(0.0, 1.2 + FLOOR_SLACK, 0.0))
	query.collision_mask = PhysicsLayers.WORLD
	var hit := _space.intersect_ray(query)
	if hit.is_empty() or hit["normal"].y < 0.7:
		return Vector3.INF
	var ground: Vector3 = hit["position"]
	if _wall(ground + Vector3(0.0, 0.1, 0.0), ground + Vector3(0.0, HEADROOM, 0.0)):
		return Vector3.INF
	var middle := ground + Vector3(0.0, 0.6, 0.0)
	for i in SPOKES:
		var turn := TAU * float(i) / float(SPOKES)
		if _wall(middle, middle + Vector3(sin(turn), 0.0, cos(turn)) * ROOM):
			return Vector3.INF
	return ground


## Every point inside two zones, by pair: `{"a | b": {count, worst, apart}}`.
func _overlaps(zones: UseZones) -> Dictionary:
	var found := {}
	var seen := {}
	for thing in zones.things():
		var at: Vector3 = thing["floor"]
		var radius: float = float(thing["reach"]) + UseZones.MIN_GAP * 0.5
		var cells := ceili(radius / STEP)
		for i in range(-cells, cells + 1):
			for k in range(-cells, cells + 1):
				var x := snappedf(at.x, STEP) + float(i) * STEP
				var z := snappedf(at.z, STEP) + float(k) * STEP
				if Vector2(x - at.x, z - at.z).length() > radius:
					continue
				var key := Vector3i(roundi(x / STEP), roundi(at.y * 2.0), roundi(z / STEP))
				if seen.has(key):
					continue
				seen[key] = true
				var ground := _ground(x, z, at.y)
				if not ground.is_finite():
					continue
				var inside := zones.zones_at(ground, UseZones.MIN_GAP * 0.5)
				for a in inside.size():
					for b in range(a + 1, inside.size()):
						var pair := "%s | %s" % [inside[a]["name"], inside[b]["name"]]
						var entry: Dictionary = found.get(pair, {"count": 0, "worst": ground})
						entry["count"] += 1
						entry["apart"] = UseZones.flat(inside[a]["floor"], inside[b]["floor"])
						found[pair] = entry
	return found


func _check(scene_path: String, pending: Array[String] = []) -> void:
	var zones := await _start(scene_path)
	assert_int(zones.things().size()).is_greater(10)
	var found := _overlaps(zones)
	var lines: Array[String] = []
	for pair: String in found:
		if pending.has(pair):
			continue
		var entry: Dictionary = found[pair]
		lines.append(
			(
				"%s: %d points, e.g. %s, %.2f m apart"
				% [pair, entry["count"], entry["worst"], entry["apart"]]
			)
		)
	lines.sort()
	if not lines.is_empty():
		print("Overlapping use zones on %s:\n  %s" % [scene_path, "\n  ".join(lines)])
	assert_array(lines).is_empty()
	# A pair the map no longer has comes off the list, so the list only shrinks.
	var gone := pending.filter(func(pair: String) -> bool: return not found.has(pair))
	assert_array(gone).override_failure_message("Fixed, take off the list: %s" % [gone]).is_empty()


func test_lot_use_zones_do_not_overlap() -> void:
	await _check(LOT)


func test_small_map_use_zones_do_not_overlap() -> void:
	await _check(SMALL, SMALL_PENDING_917)
