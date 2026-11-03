extends GdUnitTestSuite
## The dead swing at a player in reach on the second map as they do on the first (#764). On a map
## with storeys a swing needs no wall between the zombie and the player, and that check is a ray; it
## used to end on the player's own body, so a zombie 1.2 m from a player (inside its 1.4 m reach)
## never began a swing until it overlapped them.

const REACH_FRACTION := 0.85
const TICKS := 150

var _seated: SeatedNight
var _hurts := 0


func after_test() -> void:
	if _seated != null:
		_seated.dispose()
		_seated = null


func _night(scene: PackedScene) -> void:
	_hurts = 0
	_seated = await SeatedNight.start(self, 1, null, 7, false, scene)
	_seated.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"player_hurt":
			_hurts += 1
	_seated.start_round()
	for _i in 4:
		await get_tree().physics_frame


## A motionless zombie in its chase `gap` m from the player, then `TICKS` ticks.
func _swing_at(gap: float, wall_between: bool = false) -> void:
	var player := _seated.server.body_of(1).global_position
	var at := player + Vector3(gap, 0.0, 0.0)
	if wall_between:
		var wall := CSGBox3D.new()
		wall.size = Vector3(0.2, 3.0, 3.0)
		wall.use_collision = true
		_seated.world.add_child(wall)
		wall.global_position = player + Vector3(gap * 0.5, 1.5, 0.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
	var zombie := _seated.server.sim.spawn(5000, 0.0, at)
	zombie.enter(ZombieBody.Mode.CHASE)
	for tick in TICKS:
		_seated.tick()
		if tick % 30 == 0:
			await get_tree().physics_frame


func test_a_zombie_in_reach_hurts_a_player_on_the_second_map() -> void:
	await _night(load(SmallMapNight.SCENE) as PackedScene)
	var reach := _seated.server.sim.tuning.reach
	await _swing_at(reach * REACH_FRACTION)
	assert_int(_hurts).is_greater(0)


func test_a_zombie_in_reach_hurts_a_player_on_the_first_map() -> void:
	await _night(null)
	var reach := _seated.server.sim.tuning.reach
	await _swing_at(reach * REACH_FRACTION)
	assert_int(_hurts).is_greater(0)


func test_a_wall_between_still_stops_the_swing_on_the_second_map() -> void:
	await _night(load(SmallMapNight.SCENE) as PackedScene)
	var reach := _seated.server.sim.tuning.reach
	await _swing_at(reach * REACH_FRACTION, true)
	assert_int(_hurts).is_equal(0)
