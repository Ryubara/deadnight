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

var rules: GameRules
var sim: ZombieSim
var port: ZombieRulesPort
## Where zombies appear: ground positions. A request picks one with its `point_roll`.
var spawn_points: Array[Vector3] = []

var _waiting: Array[Dictionary] = []


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
		if event["type"] == &"zombie_struck":
			player_struck.emit(event["target_id"], event["zombie_id"], event["damage"])


func _on_rules_event(event: Dictionary) -> void:
	match event["type"]:
		&"zombie_spawn_requested":
			_waiting.append(event)
			_admit_waiting()
		&"zombie_removed":
			_remove(event["zombie_id"], event["cause"])
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


func _remove(zombie_id: int, cause: StringName) -> void:
	var index := _waiting.find_custom(
		func(e: Dictionary) -> bool: return e["zombie_id"] == zombie_id
	)
	if index != -1:
		_waiting.remove_at(index)
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
		sim.spawn(request["zombie_id"], request["speed"], point, 0.0, profile)
