# The drive-in greybox (docs/design/map.md): areas are named nodes, purchase doors carry their
# costs, and a player-sized capsule passes the doorways but is stopped by the doors.
extends GdUnitTestSuite

const SCENE := "res://world/drive_in_greybox.tscn"
const AREAS := [
	"Field",
	"Concession",
	"Midway",
	"ProjectionBooth",
	"GeneratorYard",
	"BackLot",
	"Road",
]
## Door node name and cost, in opening order.
const DOORS := {
	"Door_Concession_750": 750,
	"Gate_GeneratorYard_1000": 1000,
	"Door_ProjectionBooth_1250": 1250,
	"Gate_BackLot_1750": 1750,
	"Gate_Road_2500": 2500,
}
## The player controller's capsule (player.tscn): radius 0.35 m, height 1.8 m.
const PLAYER_RADIUS := 0.35
const PLAYER_HEIGHT := 1.8

var _lot: Node3D


func before_test() -> void:
	_lot = auto_free(load(SCENE).instantiate()) as Node3D
	add_child(_lot)
	# CSG builds its collision shape on the next frame; the physics server has it a tick later.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_every_area_is_a_named_node() -> void:
	for area: String in AREAS:
		assert_object(_lot.get_node_or_null(area)).is_not_null()


func test_purchase_doors_carry_their_cost() -> void:
	for door_name: String in DOORS:
		var door := _lot.get_node("Doors/%s" % door_name)
		assert_int(door.get_meta("cost")).is_equal(DOORS[door_name])


func test_doorways_pass_a_player_and_doors_stop_one() -> void:
	# Free: the stand's rear exits (south wall, z 8) and the midway's links to the yard and back lot.
	assert_bool(_can_walk(Vector3(-5, 0, 10), Vector3(-5, 0, 6))).is_true()
	assert_bool(_can_walk(Vector3(5, 0, 10), Vector3(5, 0, 6))).is_true()
	assert_bool(_can_walk(Vector3(14, 0, 20), Vector3(18, 0, 20))).is_true()
	assert_bool(_can_walk(Vector3(-14, 0, 20), Vector3(-18, 0, 20))).is_true()
	# The avenue from the apron to the stand is clear of cars.
	assert_bool(_can_walk(Vector3(0, 0, -42), Vector3(0, 0, -8))).is_true()
	# Blocked until bought: every purchase door.
	assert_bool(_can_walk(Vector3(0, 0, -8), Vector3(0, 0, 4))).is_false()
	assert_bool(_can_walk(Vector3(40, 0, -8), Vector3(40, 0, 4))).is_false()
	assert_bool(_can_walk(Vector3(-40, 0, -8), Vector3(-40, 0, 4))).is_false()
	assert_bool(_can_walk(Vector3(0, 0, 19), Vector3(0, 0, 25))).is_false()
	assert_bool(_can_walk(Vector3(0, 0, 36), Vector3(0, 0, 42))).is_false()


## True when a standing player capsule moves from `from` to `to` without touching anything.
func _can_walk(from: Vector3, to: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = PLAYER_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	# Lift it a little so the capsule does not graze the ground slab.
	query.transform = Transform3D(Basis.IDENTITY, from + Vector3(0, PLAYER_HEIGHT / 2.0 + 0.05, 0))
	query.motion = to - from
	var result := _lot.get_world_3d().direct_space_state.cast_motion(query)
	return result.size() == 2 and result[0] >= 1.0
