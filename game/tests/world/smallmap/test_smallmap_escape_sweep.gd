# Nobody leaves the second map or gets into a closed room by climbing what stands beside its walls
# (#848): the counters, cabinets, machines and window sills. The body climbs 1.25 m
# (`CameraProbe.BODY_REACH`), not the jump's 1.1 m: the hall's counter, 1.2 m high, was climbed
# (#847). This runs the real body (`EscapeSweep`, `tools/world/map_escape_probe.gd`'s method trimmed
# to the props within 6 m of a wall or a closed link's slab) with the links in each of the eight
# sets a team can have bought, and fails on any standing place outside the building, inside a room
# the links do not open yet, or on top of a wall.
extends GdUnitTestSuite

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const DEPTH := 3
## The three links (each opens a way between two rooms) and the rooms they join.
const LINKS := {
	"door_side": ["start", "side"],
	"door_stairs_start": ["start", "upstairs"],
	"door_stairs_side": ["side", "upstairs"],
}
## The rooms as boxes (min corner, max corner) with the floor's height; NAN for a stair, which has
## no one floor. A stair belongs to the upstairs: it is behind its link's slab. The first box that
## holds a point is its room, so the stairs come before the rooms they stand in. The hall's roof
## and the yards are in no box: beyond the map.
const ROOMS := [
	["upstairs", Vector3(3.15, -0.5, 0.0), Vector3(8.25, 3.6, 2.0), NAN],
	["upstairs", Vector3(-2.85, -0.5, -7.8), Vector3(2.25, 3.6, -5.8), NAN],
	["upstairs", Vector3(-6.3, 3.2, -8.1), Vector3(16.3, 6.65, 4.6), 3.4],
	["start", Vector3(-0.3, -0.5, 0.0), Vector3(16.3, 3.2, 14.8), 0.0],
	["side", Vector3(-6.3, -0.5, -8.1), Vector3(16.3, 3.2, 0.0), 0.0],
	# The side room's south-west alcove under the gallery (the rescue cooler's, #917): open to the room
	# through its south wall, walled on its west and back sides, the hall's west wall its east.
	["side", Vector3(-2.6, -0.5, -0.2), Vector3(-0.3, 3.2, 1.35), 0.0],
]
## The groups whose thin, tall boxes are the walls.
const WALL_GROUPS := ["Start", "Side", "UpperA", "UpperB"]


func test_no_prop_beside_a_wall_is_a_way_out_for_any_set_of_links() -> void:
	var cache := {}
	var all_slabs: Array[AABB] = []
	var slab_door: Array[String] = []
	var started := Time.get_ticks_msec()
	var total_hops := 0
	var total_starts := 0
	for sold in _sold_sets():
		var world := SubViewport.new()
		world.own_world_3d = true
		add_child(world)
		var map := (load(SCENE) as PackedScene).instantiate() as Node3D
		world.add_child(map)
		for _i in 3:
			await get_tree().physics_frame
		if all_slabs.is_empty():
			for door in map.get_node("Doors").get_children():
				for part in door.get_children():
					if part is CSGBox3D:
						all_slabs.append(EscapeSweep.bounds_of(part))
						slab_door.append(String(door.get_meta("shop_id")))
		var doors := map.get_node("Doors") as LotDoors
		for id: String in sold:
			doors.open(StringName(id))
		for _i in 3:
			await get_tree().physics_frame
		var present: Array[bool] = []
		for door in slab_door:
			present.append(not sold.has(door))
		var sweep := EscapeSweep.new(map, _rooms(sold), _barriers(map), all_slabs, present, cache)
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
		world.free()
		(
			assert_array(found)
			. override_failure_message("sold %s: %s" % [sold, "\n".join(found)])
			. is_empty()
		)
	assert_int(total_starts).is_greater(20)
	assert_int(total_hops).is_greater(500)


## Every set of the three links (none needs another).
func _sold_sets() -> Array:
	var ids := LINKS.keys()
	var sets := []
	for mask in 1 << ids.size():
		var sold := []
		for i in ids.size():
			if mask & (1 << i):
				sold.append(ids[i])
		sets.append(sold)
	return sets


## The rooms a team can walk to from the hall with `sold` bought.
func _open_rooms(sold: Array) -> Array:
	var open := ["start"]
	var grew := true
	while grew:
		grew = false
		for id: String in sold:
			var ends: Array = LINKS[id]
			for i in 2:
				if open.has(ends[i]) and not open.has(ends[1 - i]):
					open.append(ends[1 - i])
					grew = true
	return open


func _rooms(sold: Array) -> Array:
	var open := _open_rooms(sold)
	var rooms: Array = []
	for room: Array in ROOMS:
		var low: Vector3 = room[1]
		var boxes: Array[AABB] = [AABB(low, room[2] - low)]
		rooms.append({"name": room[0], "boxes": boxes, "floor": room[3], "open": open.has(room[0])})
	return rooms


## The walls, and the slabs of the links still closed.
func _barriers(map: Node3D) -> Array[AABB]:
	var bounds: Array[AABB] = []
	for group: String in WALL_GROUPS:
		for wall in LotFixture.walls_of(map.get_node(group)):
			bounds.append(EscapeSweep.bounds_of(wall))
	for slab in _slabs(map):
		bounds.append(EscapeSweep.bounds_of(slab))
	return bounds


func _slabs(map: Node3D) -> Array[CSGBox3D]:
	var slabs: Array[CSGBox3D] = []
	for door in map.get_node("Doors").get_children():
		for part in door.get_children():
			if part is CSGBox3D:
				slabs.append(part)
	return slabs
