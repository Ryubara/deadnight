class_name GrenadesFixture
extends RefCounted
## Shared helpers for the grenade suites: the shipped grenade file, a flat world with an optional
## wall, a server over the real rules, and the events of a type.

const STEP := 1.0 / 60.0
const DEF_PATH := "res://gameplay/grenades/defs/frag.tres"

var rules: GameRules
var log: RulesFixture
var server: GrenadeServer
var zombies: Array[int] = []


static func def() -> GrenadeDef:
	return load(DEF_PATH) as GrenadeDef


## A cast for a floor at y = 0 and, when `wall_z` is not INF, a wall at that z facing +z.
static func world_cast(wall_z: float = INF) -> Callable:
	return func(from: Vector3, to: Vector3) -> Dictionary:
		var best := {}
		var length := from.distance_to(to)
		if from.y >= 0.0 and to.y < 0.0:
			var t := from.y / (from.y - to.y)
			best = {"distance": length * t, "normal": Vector3.UP}
		if wall_z != INF and from.z >= wall_z and to.z < wall_z:
			var t := (from.z - wall_z) / (from.z - to.z)
			if best.is_empty() or length * t < best["distance"]:
				best = {"distance": length * t, "normal": Vector3.BACK}
		return best


## The weapons' kind of ray: distance to the first thing on the segment, or -1.0.
static func box_ray(box: AABB) -> Callable:
	return func(from: Vector3, to: Vector3) -> float:
		var hit: Variant = box.intersects_segment(from, to)
		return from.distance_to(hit) if hit != null else -1.0


## A night in round one with `count` players (all standing at the origin until `place` moves them),
## a grenade server on its rules, and the zombies the first seconds spawn (their ids in `zombies`).
static func night(
	players: int = 1,
	world: Callable = Callable(),
	ray: Callable = Callable(),
	tuning: RulesTuning = null
) -> GrenadesFixture:
	var fixture := GrenadesFixture.new()
	fixture.rules = RulesFixture.make_rules(players, 1234, tuning)
	fixture.log = RulesFixture.record(fixture.rules)
	fixture.server = GrenadeServer.new(def(), fixture.rules, world, ray)
	RulesFixture.into_round_one(fixture.rules)
	RulesFixture.run(fixture.rules, 20.0)
	fixture.zombies = fixture.log.spawned_ids()
	var standing: Array = []
	for player_id in range(1, players + 1):
		standing.append({"id": player_id, "pos": Vector3.ZERO})
	fixture.server.apply(GrenadeAction.players(standing))
	return fixture


## Places zombies (id to feet position, facing +z... yaw 0) and, when given, players (the players
## listed are the only ones the server knows) for the next steps.
func place(zombie_positions: Dictionary, player_positions: Dictionary = {}) -> void:
	var list: Array = []
	for id in zombie_positions:
		list.append({"id": id, "pos": zombie_positions[id], "yaw": 0.0})
	server.apply(GrenadeAction.targets(list))
	if player_positions.is_empty():
		return
	var plist: Array = []
	for id in player_positions:
		plist.append({"id": id, "pos": player_positions[id]})
	server.apply(GrenadeAction.players(plist))


## Runs `steps` fixed steps and returns every event they caused.
func run(steps: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _i in steps:
		events.append_array(server.apply(GrenadeAction.tick(STEP)))
	return events


func run_seconds(seconds: float) -> Array[Dictionary]:
	return run(roundi(seconds / STEP))


## Cook now, wait `cook` seconds, then throw from `hand` along `aim`. Returns all events.
func cook_and_throw(
	player_id: int, hand: Vector3, aim: Vector3, cook: float = 0.0, underarm: bool = false
) -> Array[Dictionary]:
	var events := server.apply(GrenadeAction.cook(player_id, 1, hand))
	events.append_array(run_seconds(cook))
	events.append_array(
		server.apply(GrenadeAction.throw_grenade(player_id, 1, hand, aim, Vector3.ZERO, underarm))
	)
	return events


static func of(events: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in events:
		if event["type"] == type:
			found.append(event)
	return found
