extends GdUnitTestSuite
## What a blast does to players: it hurts its thrower alone (#856), a teammate takes nothing however
## near; cover, and how much of the thrower's health it takes (`PlayerBlast`).

## Player 1 holds a grenade that goes off in the hand at `FEET` and the chest-high spot `BLAST`
## (hand 1.45 m up, the blast 0.25 m above it); a teammate at `apart` metres from that spot on the
## same level (chest height) is player 2.
const FEET := Vector3(0, 0, 0)
const BLAST := Vector3(0, 1.7, 0)

var _def: GrenadeDef
var _night: GrenadesFixture


func before_test() -> void:
	_def = GrenadesFixture.def()


func _held_blast(apart: float, ray: Callable = Callable()) -> Array[Dictionary]:
	_night = GrenadesFixture.night(2, GrenadesFixture.world_cast(), ray)
	_night.place({}, {1: FEET, 2: Vector3(apart, BLAST.y - _def.player_chest, 0)})
	_night.server.apply(GrenadeAction.cook(1, 1, FEET + Vector3(0, _def.hand_height, 0)))
	return GrenadesFixture.of(_night.run_seconds(_def.fuse + 0.1), &"player_blasted")


func _of_player(hurt: Array[Dictionary], player_id: int) -> Dictionary:
	for event in hurt:
		if event["player_id"] == player_id:
			return event
	return {}


func test_a_grenade_in_the_hand_takes_all_the_holders_health() -> void:
	var hurt := _held_blast(30.0)
	assert_int(hurt.size()).is_equal(1)
	assert_int(hurt[0]["player_id"]).is_equal(1)
	assert_bool(hurt[0]["own"]).is_true()
	assert_bool(hurt[0]["in_hand"]).is_true()
	assert_float(hurt[0]["share"]).is_equal(1.0)
	assert_float(hurt[0]["damage"]).is_equal(_night.rules.players[1].max_health)


func test_the_holder_takes_it_even_with_a_shelf_between_the_hand_and_the_chest() -> void:
	var wall := GrenadesFixture.box_ray(AABB(Vector3(-1, 1.3, -1), Vector3(2, 0.1, 2)))
	var hurt := _held_blast(30.0, wall)
	assert_float(_of_player(hurt, 1)["share"]).is_equal(1.0)


func test_a_teammate_takes_no_damage_however_near() -> void:
	# Player 2 stands at 0 to 5 m from the blast in the holder's hand: nothing is sent for them,
	# their health is whole, and the holder still takes all of theirs.
	for apart: float in [0.0, 0.5, 0.9, 2.0, 3.0, 5.0]:
		var hurt := _held_blast(apart)
		assert_dict(_of_player(hurt, 2)).is_empty()
		assert_float(_night.rules.health_of(2)).is_equal(_night.rules.players[2].max_health)
		assert_float(_of_player(hurt, 1)["share"]).is_equal(1.0)


func test_at_half_a_metre_the_teammate_takes_0_and_the_thrower_the_full_share() -> void:
	var hurt := _held_blast(0.5)
	assert_int(hurt.size()).is_equal(1)
	assert_dict(_of_player(hurt, 2)).is_empty()
	var thrower := _of_player(hurt, 1)
	assert_float(thrower["share"]).is_equal(1.0)
	assert_float(thrower["damage"]).is_equal(_night.rules.players[1].max_health)
	assert_float(_night.rules.health_of(2)).is_equal(_night.rules.players[2].max_health)


func test_the_thrower_beside_a_teammate_at_a_thrown_blast_takes_it_alone() -> void:
	# A grenade thrown at the thrower's own feet with a teammate at their side, both within the
	# inner radius: the thrower takes all of it by distance (`PlayerBlast`), the teammate none.
	_night = GrenadesFixture.night(2, GrenadesFixture.world_cast())
	_night.place({}, {1: Vector3(0, 0, 0), 2: Vector3(0.5, 0, 0)})
	_night.cook_and_throw(1, Vector3(0, 1.45, 0), Vector3(0, -1, 0), 0.0, true)
	var hurt := GrenadesFixture.of(_night.run_seconds(_def.fuse + 0.1), &"player_blasted")
	assert_dict(_of_player(hurt, 2)).is_empty()
	assert_int(hurt.size()).is_equal(1)
	assert_bool(hurt[0]["own"]).is_true()
	assert_bool(hurt[0]["in_hand"]).is_false()
	assert_float(hurt[0]["distance"]).is_less_equal(_def.player_full_radius)
	assert_float(hurt[0]["share"]).is_equal(1.0)
	assert_float(hurt[0]["damage"]).is_equal(_night.rules.players[1].max_health)


func test_a_wall_does_not_matter_to_the_holder_and_a_teammate_behind_it_takes_none_anyway() -> void:
	var wall := GrenadesFixture.box_ray(AABB(Vector3(2.0, 0, -3), Vector3(0.2, 3, 6)))
	var hurt := _held_blast(4.0, wall)
	assert_dict(_of_player(hurt, 2)).is_empty()
	assert_float(_of_player(hurt, 1)["share"]).is_equal(1.0)


func test_a_thrown_grenade_hurts_its_thrower_by_distance_not_by_a_discount() -> void:
	# Thrown, let go with the pin only just pulled, it lies where it lands: the thrower a few metres
	# off takes the curve's share at that distance, no discount for the throw.
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast())
	_night.place({}, {1: Vector3(0, 0, 0)})
	_night.cook_and_throw(1, Vector3(0, 1.45, 0), Vector3(0, -0.3, -1), 0.0, true)
	var hurt := GrenadesFixture.of(_night.run_seconds(_def.fuse + 0.1), &"player_blasted")
	assert_int(hurt.size()).is_equal(1)
	assert_bool(hurt[0]["in_hand"]).is_false()
	assert_float(hurt[0]["share"]).is_equal_approx(
		PlayerBlast.share(hurt[0]["distance"], _def.player_full_radius, _def.blast_radius), 0.001
	)
