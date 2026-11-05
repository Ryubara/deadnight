# Whether a dead is in reach of the quick melee on the client's picture of the night (#1285): the
# phone's Strike button waits for it. Pure rule over a `ClientState`, no night.
extends GdUnitTestSuite

var _reach: StrikeReach
var _state: ClientState


func before_test() -> void:
	_reach = StrikeReach.new()
	_state = ClientState.new()
	_state.player_id = 1
	_state.frame = {"players": {1: {"pos": Vector3(10.0, 0.0, 10.0), "downed": false}}}


func _dead_at(metres: float, mode := ZombieBody.Mode.CHASE) -> Dictionary:
	return {"position": Vector3(10.0 + metres, 0.0, 10.0), "mode": mode}


func _zombies(list: Array[Dictionary]) -> void:
	_state.zombies = list


func test_the_reach_is_the_quick_melees_own() -> void:
	assert_float(_reach.reach()).is_equal(WeaponCatalog.quick_melee().melee_range)


func test_no_dead_no_button() -> void:
	assert_bool(_reach.update(_state)).is_false()
	assert_bool(_reach.update(null)).is_false()
	assert_bool(_reach.update(ClientState.new())).is_false()


func test_a_dead_inside_the_reach_brings_it_and_one_outside_does_not() -> void:
	_zombies([_dead_at(_reach.reach() - 0.05)])
	assert_bool(_reach.update(_state)).is_true()
	_reach = StrikeReach.new()
	_zombies([_dead_at(_reach.reach() + 0.05)])
	assert_bool(_reach.update(_state)).is_false()


func test_the_ground_between_counts_not_the_height() -> void:
	var up := {"position": Vector3(11.0, 6.0, 10.0), "mode": ZombieBody.Mode.CHASE}
	_zombies([up])
	assert_bool(_reach.update(_state)).is_true()


func test_a_dying_dead_is_no_target() -> void:
	_zombies([_dead_at(0.5, ZombieBody.Mode.DYING)])
	assert_bool(_reach.update(_state)).is_false()
	_zombies([_dead_at(3.0), _dead_at(0.5, ZombieBody.Mode.DYING), _dead_at(1.0)])
	assert_bool(_reach.update(_state)).is_true()


func test_a_downed_player_has_no_blow() -> void:
	_zombies([_dead_at(1.0)])
	_state.frame["players"][1]["downed"] = true
	assert_bool(_reach.update(_state)).is_false()


func test_a_dead_at_the_edge_does_not_flicker_it() -> void:
	var edge := _reach.reach()
	_zombies([_dead_at(edge - 0.1)])
	assert_bool(_reach.update(_state)).is_true()
	# A step back inside the margin keeps it; past the margin it goes; and it needs the reach again.
	_zombies([_dead_at(edge + StrikeReach.LEAVE_MARGIN * 0.5)])
	assert_bool(_reach.update(_state)).is_true()
	_zombies([_dead_at(edge + StrikeReach.LEAVE_MARGIN + 0.05)])
	assert_bool(_reach.update(_state)).is_false()
	_zombies([_dead_at(edge + StrikeReach.LEAVE_MARGIN * 0.5)])
	assert_bool(_reach.update(_state)).is_false()
	_zombies([_dead_at(edge - 0.05)])
	assert_bool(_reach.update(_state)).is_true()


func test_the_nearest_dead_is_the_gap_a_browser_test_reads_and_minus_one_with_none() -> void:
	assert_float(StrikeReach.nearest(_state)).is_equal(-1.0)
	_zombies([_dead_at(3.0), _dead_at(0.5, ZombieBody.Mode.DYING), _dead_at(1.25)])
	assert_float(StrikeReach.nearest(_state)).is_equal_approx(1.25, 0.0001)
	assert_float(StrikeReach.nearest(null)).is_equal(-1.0)
