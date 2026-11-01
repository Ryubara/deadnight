class_name ZombieRulesPort
extends RefCounted
## The one place a zombie's doing reaches the rules: a hit on it, and a board it pulled off.
## Zombies keep no health: the rules take the damage off the zombie's health, pay for it and decide
## whether it killed (`RulesAction.hit`), and answer with events. This port only turns the answer
## into what a zombie needs to know.

var rules: GameRules


func _init(p_rules: GameRules) -> void:
	rules = p_rules


## Sends `damage` to the zombie through the rules. Returns `{"accepted": bool, "killed": bool}`:
## `accepted` when the rules took damage off a live zombie (a dead, gone or unknown one, a downed
## shooter or a wrong phase is rejected), `killed` when that hit removed it.
func deal_damage(
	shooter_id: int, zombie_id: int, zone: StringName, damage: float, melee: bool
) -> Dictionary:
	var events := rules.apply(RulesAction.hit(shooter_id, zombie_id, zone, damage, melee))
	var accepted := false
	var killed := false
	for event in events:
		if event["type"] == &"zombie_damaged" and event["zombie_id"] == zombie_id:
			accepted = true
		elif event["type"] == &"zombie_removed" and event["zombie_id"] == zombie_id:
			killed = true
	return {"accepted": accepted, "killed": killed}


## A zombie pulled a board off `gate_id`. Nothing happens when none stands (two zombies finishing
## the last one in one step: the second has nothing to tear).
func tear_board(gate_id: StringName, zombie_id: int) -> void:
	if rules.barricades.boards_of(gate_id) > 0:
		rules.apply(RulesAction.tear_board(gate_id, zombie_id))
