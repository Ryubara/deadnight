extends GdUnitTestSuite
## What a person's ping key marks, from the camera ray and what the client knows.

const EYE := Vector3(0, 2, 0)
const AHEAD := Vector3(0, 0, -1)


func _zombie(id: int, at: Vector3) -> Dictionary:
	return {"id": id, "position": at, "mode": ZombieBody.Mode.CHASE}


func _pick(
	zombies: Array[Dictionary] = [],
	players := {},
	doors := {},
	ammo: Array[Vector3] = [],
	landed := Vector3(0, 0, -20)
) -> Dictionary:
	return PingAim.pick(EYE, AHEAD, zombies, players, 1, doors, ammo, landed)


func test_open_ground_is_a_place_to_hold() -> void:
	var action := _pick()
	assert_str(action["kind"]).is_equal("here")
	assert_vector(action["pos"]).is_equal(Vector3(0, 0, -20))


func test_a_ray_that_hits_nothing_marks_a_point_along_it() -> void:
	var action := _pick([], {}, {}, [], Vector3.INF)
	assert_vector(action["pos"]).is_equal_approx(Vector3(0, 2, -PingAim.REACH), Vector3.ONE * 0.01)


func test_the_zombie_under_the_crosshair_is_an_enemy() -> void:
	var near: Array[Dictionary] = [_zombie(5, Vector3(0.4, 0, -10)), _zombie(6, Vector3(8, 0, -10))]
	var action := _pick(near)
	assert_str(action["kind"]).is_equal("enemy")
	assert_int(action["subject"]).is_equal(5)


func test_the_nearest_of_two_on_the_ray_wins_and_a_dying_one_is_skipped() -> void:
	var line: Array[Dictionary] = [
		_zombie(5, Vector3(0, 0, -20)),
		_zombie(6, Vector3(0.2, 0, -8)),
		{"id": 7, "position": Vector3(0, 0, -4), "mode": ZombieBody.Mode.DYING},
	]
	assert_int(_pick(line)["subject"]).is_equal(6)


func test_a_downed_teammate_under_the_crosshair_is_to_be_raised() -> void:
	var players := {
		1: {"pos": Vector3.ZERO, "downed": false},
		2: {"pos": Vector3(0.3, 0, -6), "downed": true},
		3: {"pos": Vector3(0.0, 0, -9), "downed": false},
	}
	var action := _pick([], players)
	assert_str(action["kind"]).is_equal("downed")
	assert_int(action["subject"]).is_equal(2)


func test_a_shut_door_near_where_the_ray_lands_is_a_door() -> void:
	var doors := {2: [Vector3(1.0, 0, -22.0)]}
	var action := _pick([], {}, doors)
	assert_str(action["kind"]).is_equal("door")
	assert_int(action["subject"]).is_equal(2)
	assert_vector(action["pos"]).is_equal(Vector3(1.0, 0, -22.0))


func test_an_ammunition_spot_near_the_landing_is_ammunition() -> void:
	var ammo: Array[Vector3] = [Vector3(-2, 0, -19)]
	assert_str(_pick([], {}, {}, ammo)["kind"]).is_equal("ammo")
	assert_str(_pick([], {}, {}, ammo, Vector3(30, 0, 0))["kind"]).is_equal("here")


func test_a_zombie_behind_the_camera_is_not_under_the_crosshair() -> void:
	var behind: Array[Dictionary] = [_zombie(5, Vector3(0, 0, 6))]
	assert_str(_pick(behind)["kind"]).is_equal("here")
