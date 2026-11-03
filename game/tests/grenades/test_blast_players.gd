extends GdUnitTestSuite
## What a blast does to players: the holder, a teammate, cover, and how much of their health it
## takes (`PlayerBlast`).

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


func test_a_player_inside_the_inner_radius_takes_all_of_it() -> void:
	var hurt := _held_blast(_def.player_full_radius - 0.05)
	assert_float(_of_player(hurt, 2)["share"]).is_equal(1.0)
	assert_float(_of_player(hurt, 2)["damage"]).is_equal(_night.rules.players[2].max_health)


func test_halfway_out_a_player_takes_a_part_of_it() -> void:
	var halfway := (_def.player_full_radius + _def.blast_radius) / 2.0
	var hurt := _held_blast(halfway)
	var event := _of_player(hurt, 2)
	assert_float(event["share"]).is_equal_approx(
		PlayerBlast.share(halfway, _def.player_full_radius, _def.blast_radius), 0.001
	)
	assert_float(event["share"]).is_between(0.05, 0.6)
	assert_float(event["damage"]).is_equal_approx(
		_night.rules.players[2].max_health * event["share"], 0.01
	)


func test_a_grenade_a_few_metres_away_hurts_but_does_not_down() -> void:
	var event := _of_player(_held_blast(3.0), 2)
	assert_float(event["damage"]).is_greater(20.0)
	assert_float(event["damage"]).is_less(_night.rules.players[2].max_health)


func test_at_the_edge_of_the_blast_a_player_takes_nothing() -> void:
	assert_dict(_of_player(_held_blast(_def.blast_radius), 2)).is_empty()
	assert_dict(_of_player(_held_blast(_def.blast_radius + 2.0), 2)).is_empty()


func test_a_teammate_takes_what_the_thrower_would_at_that_spot() -> void:
	var hurt := _held_blast(0.9)
	assert_float(_of_player(hurt, 2)["share"]).is_equal(1.0)
	assert_bool(_of_player(hurt, 2)["own"]).is_false()
	assert_int(_of_player(hurt, 2)["thrower_id"]).is_equal(1)


func test_a_wall_protects_a_teammate_but_not_the_holder() -> void:
	var wall := GrenadesFixture.box_ray(AABB(Vector3(2.0, 0, -3), Vector3(0.2, 3, 6)))
	var hurt := _held_blast(4.0, wall)
	assert_dict(_of_player(hurt, 2)).is_empty()
	assert_float(_of_player(hurt, 1)["share"]).is_equal(1.0)


func test_a_thrown_grenade_hurts_its_thrower_by_distance_not_by_a_discount() -> void:
	# Thrown, let go with the pin only just pulled, it lies where it lands: the thrower a few metres
	# off takes the same share a teammate would at that distance.
	_night = GrenadesFixture.night(1, GrenadesFixture.world_cast())
	_night.place({}, {1: Vector3(0, 0, 0)})
	_night.cook_and_throw(1, Vector3(0, 1.45, 0), Vector3(0, -0.3, -1), 0.0, true)
	var hurt := GrenadesFixture.of(_night.run_seconds(_def.fuse + 0.1), &"player_blasted")
	assert_int(hurt.size()).is_equal(1)
	assert_bool(hurt[0]["in_hand"]).is_false()
	assert_float(hurt[0]["share"]).is_equal_approx(
		PlayerBlast.share(hurt[0]["distance"], _def.player_full_radius, _def.blast_radius), 0.001
	)
