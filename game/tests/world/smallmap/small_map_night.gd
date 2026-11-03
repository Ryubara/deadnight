class_name SmallMapNight
extends RefCounted
## A night on the second map for the suites about its doors, windows and buys: the real `Night`
## (server, rules and a client in one) built from the small map's scene and its rules overlay, in
## `MANUAL` mode (no autopilot), and a seated night (`SeatedNight`) for the suites that run bots or
## the dead by themselves.

const SCENE := "res://world/smallmap/smallmap_greybox.tscn"
const STEP := Night.STEP
## Physics frames a bought link's walking mesh gets to reach the map.
const MAP_FRAMES := 600


## A night on the map, ready to play. `tuning` is laid over by the map's overlay.
static func start(parent: Node, seed_value: int = 7, tuning: RulesTuning = null) -> Night:
	var night := Night.new()
	night.scene = load(SCENE) as PackedScene
	parent.add_child(night)
	await night.start(Night.Mode.MANUAL, seed_value, tuning)
	return night


## A seated night (`players` seats, no bots yet) on the map.
static func seat(
	parent: Node, players: int, tuning: RulesTuning = null, seed_value: int = 7
) -> SeatedNight:
	return await SeatedNight.start(
		parent, players, tuning, seed_value, true, load(SCENE) as PackedScene
	)


## Runs `count` ticks of a night driven by hand, sending `command` before each one.
static func run(night: Night, count: int, command: NightCommand = null) -> void:
	NightFixture.run(night, count, command)


## Waits until the walking mesh a bought link swapped in answers for `point` (a path from the
## players' start ends within half a metre of it).
static func map_reaches(night: Night, point: Vector3) -> bool:
	var from := night.world.player_spawn(0)
	for _i in MAP_FRAMES:
		var way := NavigationServer3D.map_get_path(night.world.map(), from, point, true)
		if not way.is_empty() and way[way.size() - 1].distance_to(point) < 0.5:
			return true
		await night.get_tree().physics_frame
	return false


## Puts the first player on `point` (feet) and lets the night settle for a few ticks.
static func stand_at(night: Night, point: Vector3) -> void:
	night.player().teleport(point + Vector3(0.0, 0.1, 0.0))
	run(night, 6)


## The use button, once.
static func press_use(night: Night) -> void:
	var command := NightCommand.new()
	command.use = true
	run(night, 1, command)
	run(night, 3)
