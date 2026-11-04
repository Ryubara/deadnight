# A bot on ground the walking mesh does not hold (#1051): the scrap by the west midway's boards
# where a Rookie stood (#1041), an island among the cars, a car's bonnet. Such a piece of the mesh
# is the dead's alone (`NavmeshSplit`), so a person's path from there starts on the nearest walking
# ground, and it is a path like any other: whatever the bot was told to do, it walks.
extends GdUnitTestSuite

const SEED := 8
const TICKS_PER_SECOND := 60
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60
const DOORS: Array[StringName] = [
	&"door_concession", &"door_booth", &"door_back_lot", &"door_yard", &"door_road"
]
## The spots, each with open ground a few metres off where the person stands.
const SPOTS: Dictionary[Vector3, Vector3] = {
	Vector3(-14.3, 0.1, 31.6): Vector3(-11.0, 0.1, 28.0),
	Vector3(35.0, 0.1, -30.8): Vector3(35.0, 0.1, -26.0),
	Vector3(7.6, 1.1, -12.5): Vector3(7.6, 0.1, -8.5),
}
## Where the person stands who is followed: past the 10 m a calm bot keeps (`BotFollow.CALM_BAND`).
const FAR: Dictionary[Vector3, Vector3] = {
	Vector3(-14.3, 0.1, 31.6): Vector3(0.0, 0.1, 34.0),
	Vector3(35.0, 0.1, -30.8): Vector3(0.0, 0.1, -30.0),
	Vector3(7.6, 1.1, -12.5): Vector3(0.0, 0.1, -30.0),
}
## Seconds a bot is given to do as it was told.
const SECONDS := 15.0
## Metres from the spot of a hold that count as there, and from the person followed.
const AT_THE_SPOT := 3.5
const FOLLOWING := 10.5
## Metres from where it was set down that count as walked off (roam).
const OFF := 3.0
## Metres a path may end short of what it was asked for.
const REACHED := 1.0

var _catcher := ErrorCatcher.new()
var _night: SeatedNight


func after_test() -> void:
	_catcher.stop()
	if _night != null:
		_night.dispose()
		_night = null
		await get_tree().process_frame


func _seat() -> BotClient:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	_night = await NightFixture.seat(self, 2, tuning, SEED)
	for door in DOORS:
		_night.open_door(door)
	await _night.settle(SETTLE_FRAMES)
	assert_bool(await _night.settle_doors()).is_true()
	var bot := _night.seat(1, BotProfile.rookie(), SEED + 1)
	_night.human(2)
	_catcher.start()
	return bot


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Gives the order, sets the bot on `spot` and the person at `ground`, and returns where the bot is
## the first time `done` says so (`Vector3.INF` when the time ran out).
func _walk_off(order: StringName, spot: Vector3, ground: Vector3, done: Callable) -> Vector3:
	var body := _night.server.body_of(1)
	var person := _night.server.body_of(2)
	person.teleport(ground)
	body.teleport(ground + Vector3(1.0, 0.0, 0.0))
	_night.run(10)
	_night.give_order(order, 2, ground)
	_night.run(10)
	body.teleport(spot)
	for _t in int(SECONDS * TICKS_PER_SECOND):
		_night.tick()
		if done.call(body.global_position):
			return body.global_position
	return Vector3.INF


func test_a_path_from_each_spot_starts_on_the_walking_ground() -> void:
	await _seat()
	var map := _night.world.map()
	for spot: Vector3 in SPOTS:
		var ground: Vector3 = SPOTS[spot]
		var goal := NavigationServer3D.map_get_closest_point(map, ground)
		var path := NavigationServer3D.map_get_path(map, spot, goal, true, NavLayers.WALK)
		(
			assert_float(path[path.size() - 1].distance_to(goal))
			. override_failure_message("from %s the path ends at %s" % [spot, path])
			. is_less(REACHED)
		)


func test_a_bot_told_to_follow_walks_off_each_spot() -> void:
	await _seat()
	for spot: Vector3 in SPOTS:
		var person: Vector3 = FAR[spot]
		var there := func(at: Vector3) -> bool: return _flat(at, person) <= FOLLOWING
		var end := _walk_off(BotOrders.FOLLOW, spot, person, there)
		assert_vector(end).override_failure_message("never left %s" % spot).is_not_equal(
			Vector3.INF
		)
	assert_array(_catcher.lines).is_empty()


func test_a_bot_told_to_hold_walks_back_to_its_spot() -> void:
	await _seat()
	for spot: Vector3 in SPOTS:
		var ground: Vector3 = SPOTS[spot]
		var there := func(at: Vector3) -> bool: return _flat(at, ground) <= AT_THE_SPOT
		var end := _walk_off(BotOrders.HOLD, spot, ground, there)
		assert_vector(end).override_failure_message("never left %s" % spot).is_not_equal(
			Vector3.INF
		)
	assert_array(_catcher.lines).is_empty()


func test_a_roaming_bot_walks_off_each_spot() -> void:
	await _seat()
	for spot: Vector3 in SPOTS:
		var off := func(at: Vector3) -> bool: return _flat(at, spot) >= OFF
		var end := _walk_off(BotOrders.ROAM, spot, SPOTS[spot], off)
		assert_vector(end).override_failure_message("never left %s" % spot).is_not_equal(
			Vector3.INF
		)
	assert_array(_catcher.lines).is_empty()
