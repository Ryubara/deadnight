class_name ZombieDirector
extends RefCounted
## Joins the rules to the zombie simulation, on the server. Spawn requests and removals come from
## the rules' events; hits go back through `ZombieRulesPort`. The director owns no health and no
## clock.
##
## Each zombie takes its type's numbers from the spawn request (`ZombieProfile`): its blow, its
## telegraph, its look and the size of its hit zones.
##
## The rules may ask for more zombies than the crowd budget allows (their alive cap grows with the
## player count): requests wait here until a zombie falls, in the order they came.

signal player_struck(player_id: int, zombie_id: int, damage: float)
## A frozen zombie was killed and broke apart: the `zombie_shattered` event (`ZombieSim.shatter`).
signal zombie_shattered(event: Dictionary)

## Seconds a round stands down to its last dead with nothing happening to them before they are
## walked to the people, how far from every person the point they rise on is at the least, and how
## many of the nearest points the stragglers are spread over.
const RESCUE_AFTER := 30.0
const RESCUE_RANGE := 25.0
const RESCUE_SPREAD := 3

var rules: GameRules
var sim: ZombieSim
var port: ZombieRulesPort
## Where zombies appear: ground positions. A request picks one with its `point_roll`.
var spawn_points: Array[Vector3] = []
## The breach (`ZombieGate.id`) a spawn point lies outside, by point; a zombie spawned there comes
## in through its boards. A point not in it is already inside.
var spawn_gates: Dictionary[Vector3, StringName] = {}

## How many stranded zombies were put back on a spawn point (`ZombieSim.relocate`), for the reports.
var relocated := 0
## How many stragglers were walked to the people (`_watch_the_tail`), for the reports.
var rescued := 0

var _waiting: Array[Dictionary] = []
## Seconds the round has stood down to its last few dead with no blow struck, no damage done and
## no kill (`RESCUE_AFTER`).
var _quiet := 0.0


func _init(p_rules: GameRules, p_sim: ZombieSim, p_spawn_points: Array[Vector3]) -> void:
	rules = p_rules
	sim = p_sim
	spawn_points = p_spawn_points
	port = ZombieRulesPort.new(p_rules)
	rules.event_emitted.connect(_on_rules_event)


## Ends the match's hold on the rules (the rules' signal holds this object, and this object holds
## the rules: a cycle that is never freed otherwise). Call it when the match is over.
func close() -> void:
	if rules.event_emitted.is_connected(_on_rules_event):
		rules.event_emitted.disconnect(_on_rules_event)


## Requests waiting for room in the crowd.
func waiting_count() -> int:
	return _waiting.size()


## The seam for weapons: a hit on a zombie. `zone` is a Hitbox zone name, `damage` the final
## amount after falloff and zone multipliers. The rules decide the outcome; the zombie reacts.
## A zombie the sim does not hold (still waiting for room, or gone) cannot be hit: rejected, no
## damage, no kill, no payment.
func take_hit(
	zombie_id: int, zone: StringName, damage: float, shooter_id: int = -1, melee: bool = false
) -> Dictionary:
	if not sim.zombies.has(zombie_id):
		return {"accepted": false, "killed": false}
	var result := port.deal_damage(shooter_id, zombie_id, zone, damage, melee)
	if result["accepted"] and not result["killed"]:
		sim.react_to_hit(zombie_id)
	return result


## One fixed step: lets waiting requests in, moves the zombies, and reports blows on players.
## `targets` maps player id to position, the players a zombie may chase.
func tick(delta: float, targets: Dictionary) -> void:
	_admit_waiting()
	for event in sim.tick(delta, targets):
		match event["type"]:
			&"zombie_struck":
				_quiet = 0.0
				player_struck.emit(event["target_id"], event["zombie_id"], event["damage"])
			&"zombie_tore":
				port.tear_board(event["gate_id"], event["zombie_id"])
			&"zombie_burst":
				port.tear_all(event["gate_id"], event["zombie_id"])
			&"zombie_stranded":
				_relocate(event["zombie_id"])
	_watch_the_tail(delta, targets)


## A zombie with no way to its target, far from it: back on a spawn point (the next one in turn, so
## two in one pocket do not go to the same).
func _relocate(zombie_id: int) -> void:
	if spawn_points.is_empty():
		return
	var point := spawn_points[(zombie_id + relocated) % spawn_points.size()]
	relocated += 1
	sim.relocate(zombie_id, point, spawn_gates.get(point, &""))


## The rescue of a round that will not end: with only the last few dead left (the ones the screen
## outlines) and nothing happening to them for `RESCUE_AFTER` seconds, no blow struck, no damage
## done, no kill, a dead that has no way to its target (the walking mesh gives it a path that stops
## `ZombieSim.STRAND_GAP` or more short: a pocket of the mesh, where the strand watch does not look
## when the map is small enough that someone is always within 12 m) goes to the spawn point nearest
## the people that is `RESCUE_RANGE` metres or more from them (the farthest one when the map has
## none that far), away from the breach it was stuck at, and rises there as a new one: the dead
## walk to the people. A dead that has a way is coming, however slowly (a headliner after a person
## with an empty gun), and is left where it is. The soak found rounds that stood on one such dead
## for minutes (#950).
func _watch_the_tail(delta: float, targets: Dictionary) -> void:
	var left := rules.zombies_remaining()
	if (
		rules.phase != GameRules.Phase.ACTIVE
		or left < 1
		or left > sim.tuning.mark_last
		or not _waiting.is_empty()
		or targets.is_empty()
	):
		_quiet = 0.0
		return
	_quiet += delta
	if _quiet < RESCUE_AFTER:
		return
	_quiet = 0.0
	var nth := 0
	for zombie: ZombieBody in sim.zombies.values():
		if zombie.mode == ZombieBody.Mode.DYING or zombie.mode == ZombieBody.Mode.EMERGING:
			continue
		if zombie.path_gap < ZombieSim.STRAND_GAP:
			continue
		var point := _rescue_point(zombie, targets, nth)
		if point == Vector3.INF:
			continue
		nth += 1
		rescued += 1
		sim.relocate(zombie.id, point, spawn_gates.get(point, &""))


## The spawn point to walk a straggler in from: of those `RESCUE_RANGE` or more from every person
## and not at the breach it stood at, the `nth` nearest to the nearest person (so two stragglers do
## not rise on the same point); with none that far, the `nth` farthest; `Vector3.INF` for no point.
func _rescue_point(zombie: ZombieBody, targets: Dictionary, nth: int) -> Vector3:
	var scored: Array[Dictionary] = []
	for point in spawn_points:
		if zombie.gate_id != &"" and spawn_gates.get(point, &"") == zombie.gate_id:
			continue
		var nearest := INF
		for at: Vector3 in targets.values():
			nearest = minf(nearest, Vector2(at.x - point.x, at.z - point.z).length())
		scored.append({"point": point, "apart": nearest})
	if scored.is_empty():
		return Vector3.INF
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["apart"] < b["apart"])
	var far := scored.filter(func(row: Dictionary) -> bool: return row["apart"] >= RESCUE_RANGE)
	if far.is_empty():
		scored.reverse()
		return scored[nth % mini(scored.size(), RESCUE_SPREAD)]["point"]
	return far[nth % mini(far.size(), RESCUE_SPREAD)]["point"]


func _on_rules_event(event: Dictionary) -> void:
	if event["type"] == &"zombie_removed" or event["type"] == &"zombie_damaged":
		_quiet = 0.0
	match event["type"]:
		&"zombie_spawn_requested":
			_waiting.append(event)
			_admit_waiting()
		&"zombie_removed":
			_remove(event["zombie_id"], event["cause"], event.get("shattered", false))
		&"zombie_crippled":
			_cripple(event)
		&"zombie_damaged":
			if event["zone"] == RulesAction.ZONE_WEAK:
				sim.weak_hit(event["zombie_id"])


## A blast took its legs: the zombie becomes the type the rules say (a crawler), in its look.
func _cripple(event: Dictionary) -> void:
	var type := rules.tuning.roster.type_of(event["zombie_type"])
	if type == null:
		return
	var profile := ZombieProfile.from_type(type, event.get("look", type.id), sim.tuning)
	sim.cripple(event["zombie_id"], profile, event["speed_scale"])


func _remove(zombie_id: int, cause: StringName, shattered: bool = false) -> void:
	var index := _waiting.find_custom(
		func(e: Dictionary) -> bool: return e["zombie_id"] == zombie_id
	)
	if index != -1:
		_waiting.remove_at(index)
	elif cause == &"killed" and shattered:
		var broken := sim.shatter(zombie_id)
		if not broken.is_empty():
			zombie_shattered.emit(broken)
	elif cause == &"killed":
		sim.begin_death(zombie_id)
	else:
		sim.despawn(zombie_id)


func _admit_waiting() -> void:
	while not _waiting.is_empty() and sim.has_room() and not spawn_points.is_empty():
		var request: Dictionary = _waiting.pop_front()
		var point := spawn_points[request["point_roll"] % spawn_points.size()]
		var profile := ZombieProfile.from_event(request, sim.tuning)
		var type := rules.tuning.roster.type_of(profile.type)
		profile.weak = type != null and type.weak_multiplier > 1.0
		sim.spawn(
			request["zombie_id"], request["speed"], point, 0.0, profile, spawn_gates.get(point, &"")
		)
