# Packs sent up the booth ramp and the small map's stairs (Deadnight #681). The dead kept the height
# they spawned at ("the lot is flat"), so on a ramp each repath snapped their ground-level
# position to the floor beside it and sent them back to its foot: they never climbed. The control
# in each case is the same navigation with the heights left out (`FlatPathing`), the way the
# zombies used to walk.
extends GdUnitTestSuite

const SEED := 681
## Where the person stands on the booth's roost (the upper floor's top is 3.9 m up).
const ROOST := Vector3(2.5, 3.95, 27.0)
const ROOST_TOP := 3.5
const SPEED := 2.4
const PACK := 6
## The small map's upstairs floors are 3.4 m up.
const UPSTAIRS_TOP := 3.0

var _catcher := ErrorCatcher.new()


## The navigation of the night with the heights left out: what the zombies walked before.
class FlatPathing:
	extends NavmeshPathing

	func ground_offset() -> float:
		return NAN


func after_test() -> void:
	_catcher.stop()


# --- The booth ramp, in the real night ---


func _night() -> SeatedNight:
	var night := await NightFixture.seat(self, 1, SeatedNight.one_a_round(), SEED)
	night.human(1)
	night.open_door(&"door_concession")
	night.open_door(&"door_booth")
	await night.settle(12)
	night.start_round()
	night.server.body_of(1).teleport(ROOST)
	night.run(5)
	return night


## A pack of `count` sent from `from` at the person on the roost; `flat` walks them the old way.
func _booth_pack(count: int, from: Vector3, flat: bool, deadline := 40.0) -> ClimbPack:
	var night := await _night()
	if flat:
		night.server.sim.pathing = FlatPathing.new(night.world.map())
	night.server.sim.zombies.clear()
	var pack := ClimbPack.new(night.server.sim, night.tick, ROOST_TOP)
	pack.deadline = deadline
	pack.spawn(count, from, SPEED, Vector3(0.0, 0.0, -1.0))
	pack.run()
	night.dispose()
	return pack


func test_the_old_walk_never_gets_a_pack_up_the_ramp() -> void:
	var pack := await _booth_pack(PACK, Vector3(-4.8, 0.0, 23.0), true, 20.0)
	print(pack.summary("booth ramp, heights left out (before)"))
	assert_int(pack.reached()).is_equal(0)
	assert_float(pack.max_height).is_less(0.3)


func test_a_pack_at_the_ramps_foot_climbs_to_the_roost() -> void:
	var pack := await _booth_pack(PACK, Vector3(-4.8, 0.0, 23.0), false)
	print(pack.summary("booth ramp from its foot (after)"))
	assert_int(pack.reached()).is_equal(PACK)
	assert_float(pack.longest_stuck).is_less(2.0)


func test_a_pack_at_the_booth_door_climbs_to_the_roost() -> void:
	var pack := await _booth_pack(PACK, Vector3(-4.8, 0.0, 19.0), false)
	print(pack.summary("booth ramp from the door (after)"))
	assert_int(pack.reached()).is_equal(PACK)
	assert_float(pack.longest_stuck).is_less(2.0)


func test_a_big_pack_climbs_the_ramp_with_none_stuck() -> void:
	var pack := await _booth_pack(16, Vector3(-4.8, 0.0, 19.0), false, 60.0)
	print(pack.summary("booth ramp, sixteen from the door (after)"))
	assert_int(pack.reached()).is_equal(16)
	assert_float(pack.longest_stuck).is_less(2.0)


# --- The small map's stairs ---


## The small map with every link open and the zombies' mesh on a map of its own, and a bare sim.
func _small_map(flat: bool) -> Dictionary:
	var lot := auto_free((load(SmallMapMeasure.SCENE) as PackedScene).instantiate()) as Node3D
	add_child(lot)
	for _i in 4:
		await get_tree().physics_frame
	var doors := lot.get_node("Doors") as LotDoors
	for door in doors.get_children():
		doors.open(StringName(door.get_meta(&"shop_id")))
	for _i in 4:
		await get_tree().physics_frame
	var nav := SmallMapNavigation.new(lot, SmallMapNavigation.zombie_mesh())
	await nav.settle(get_tree())
	var sim := ZombieSim.new(null, SEED)
	sim.pathing = FlatPathing.new(nav.map()) if flat else NavmeshPathing.new(nav.map())
	return {"lot": lot, "nav": nav, "sim": sim}


func _small_pack(spawn: String, target: Vector3, flat: bool, deadline := 40.0) -> ClimbPack:
	var world := await _small_map(flat)
	var sim: ZombieSim = world["sim"]
	var lot: Node3D = world["lot"]
	var from := (lot.get_node("ZombieSpawns/" + spawn) as Node3D).global_position
	var targets := {1: target}
	var pack := ClimbPack.new(sim, func() -> void: sim.tick(ClimbPack.STEP, targets), UPSTAIRS_TOP)
	pack.deadline = deadline
	pack.spawn(PACK, from, SPEED, Vector3(0.0, 0.0, 1.0))
	pack.run()
	(world["nav"] as SmallMapNavigation).free_map()
	return pack


func test_the_old_walk_never_gets_a_pack_up_the_first_stair() -> void:
	var pack := await _small_pack("Spawn_start_1", Vector3(11.0, 3.4, 2.3), true, 20.0)
	print(pack.summary("small map stair A, heights left out (before)"))
	assert_int(pack.reached()).is_less(PACK)


func test_a_pack_climbs_the_first_stair() -> void:
	var pack := await _small_pack("Spawn_start_1", Vector3(11.0, 3.4, 2.3), false)
	print(pack.summary("small map stair A (after)"))
	assert_int(pack.reached()).is_equal(PACK)
	assert_float(pack.longest_stuck).is_less(2.0)


func test_a_pack_climbs_the_second_stair() -> void:
	var pack := await _small_pack("Spawn_side_1", Vector3(5.0, 3.4, -4.0), false)
	print(pack.summary("small map stair B (after)"))
	assert_int(pack.reached()).is_equal(PACK)
	assert_float(pack.longest_stuck).is_less(2.0)
