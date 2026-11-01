class_name ZombieRulesPort
extends RefCounted
## The one place a hit on a zombie reaches the rules. Zombies keep no health: the rules decide
## whether a hit kills and what it pays, and answer with events.
##
## INTERIM: today `GameRules` hands out a zombie's health in `zombie_spawn_requested` but does not
## track it (issue #60 moves that into the rules as a damage action). Until that lands this port
## keeps the remaining health in `_health` and turns each hit into the `hit` or `kill` action the
## rules have. When #60 is merged, delete `_health` and `note_spawn`, and make `deal_damage` send
## the new damage action; nothing outside this file changes, because callers only look at the
## returned `killed` and `accepted`.

var rules: GameRules

## Remaining health per live zombie id. Interim, see above.
var _health: Dictionary[int, float] = {}


func _init(p_rules: GameRules) -> void:
	rules = p_rules


## Called for each `zombie_spawn_requested` event.
func note_spawn(zombie_id: int, health: float) -> void:
	_health[zombie_id] = health


## Forgets a zombie the rules removed.
func note_removed(zombie_id: int) -> void:
	_health.erase(zombie_id)


## Sends `damage` to the zombie through the rules. Returns `{"accepted": bool, "killed": bool}`:
## `accepted` when the zombie was alive to take it, `killed` when the rules removed it for it.
func deal_damage(
	shooter_id: int, zombie_id: int, zone: StringName, damage: float, melee: bool
) -> Dictionary:
	if not _health.has(zombie_id):
		return {"accepted": false, "killed": false}
	_health[zombie_id] -= damage
	var headshot := zone == &"head"
	var events: Array[Dictionary]
	if _health[zombie_id] <= 0.0:
		events = rules.apply(RulesAction.kill(shooter_id, zombie_id, headshot, melee))
	else:
		events = rules.apply(RulesAction.hit(shooter_id, zombie_id, headshot))
	var killed := false
	for event in events:
		if event["type"] == &"zombie_removed" and event["zombie_id"] == zombie_id:
			killed = true
	return {"accepted": true, "killed": killed}
