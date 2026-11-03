class_name WeaponsFixture
extends RefCounted
## Shared helpers for the weapons suites: the shipped weapon files, a server over them, a stub
## world and a few shot shapes.

const IDS: Array[StringName] = WeaponCatalog.IDS
const STEP := 1.0 / 60.0
const SEED := 7
## Long enough for the rules to spawn one more round-one zombie.
const SPAWN_SECONDS := 2.5
## A shooter 8 m from the origin, chest high, looking down -z; targets stand at the origin.
const SHOOTER := Vector3(0, 1.1, 8)


static func def(id: StringName) -> WeaponDef:
	return WeaponCatalog.get_def(id)


static func all_defs() -> Array[WeaponDef]:
	return WeaponCatalog.all()


## A world that is one box; the Callable `AimResolver` expects.
static func box_world(box: AABB) -> Callable:
	return func(from: Vector3, to: Vector3) -> float:
		var hit: Variant = box.intersects_segment(from, to)
		return from.distance_to(hit) if hit != null else -1.0


## The targets map `AimResolver` expects, from `{id: position}` (all facing the same way).
static func targets_of(positions: Dictionary) -> Dictionary:
	var placed := {}
	for id in positions:
		placed[id] = {"pos": positions[id], "yaw": 0.0, "pose": Hitbox.STANDING}
	return placed


## A server over `rules`, or over a night in round one with `zombies` zombies already spawned
## (ids 1 to n, health 60, player 1 in the game) when none is given.
static func make_server(
	rules: GameRules = null, world: Callable = Callable(), zombies: int = 2
) -> CombatServer:
	var night := rules
	if night == null:
		night = RulesFixture.make_rules(1)
	var server := CombatServer.new(all_defs(), night, world, SEED)
	if rules == null:
		RulesFixture.into_round_one(night)
		RulesFixture.run(night, SPAWN_SECONDS * zombies)
	return server


## One fixed step: tell the server where the targets are, then let a step pass.
static func step(server: CombatServer, positions: Dictionary, steps: int = 1) -> void:
	for _i in steps:
		server.apply(CombatAction.targets(list_of(positions)))
		server.apply(CombatAction.tick(STEP))


static func list_of(positions: Dictionary) -> Array:
	var list: Array = []
	for id in positions:
		list.append({"id": id, "pos": positions[id], "yaw": 0.0, "pose": Hitbox.STANDING})
	return list


## A fire action from `from` straight at `to`, camera and muzzle on the same point.
static func fire_at(
	shooter_id: int, seq: int, from: Vector3, to: Vector3, view_time: float = 0.0
) -> Dictionary:
	return CombatAction.fire(shooter_id, seq, from, (to - from).normalized(), from, view_time)


static func of(events: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in events:
		if event["type"] == type:
			found.append(event)
	return found
