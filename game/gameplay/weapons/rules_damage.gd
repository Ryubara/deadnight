class_name RulesDamage
extends RefCounted
## The one seam between shooting and the rules engine. `CombatServer` finds out how much damage a
## zombie takes; this decides what that means and tells `GameRules`.
##
## Today `GameRules` does not own zombie health (it hands `health` out in `zombie_spawn_requested`
## and trusts `hit` and `kill`), so this adapter keeps the remaining health per zombie and turns
## damage into a `RulesAction.hit` or `kill`. Issue #60 moves the health into the rules: damage
## becomes one action carrying zombie id, zone and amount, and the rules answer with the kill and
## the points. When it lands, `deal` sends that one action and reads the answer from the events,
## `_ledger` goes away, and nothing outside this file changes.

var _rules: GameRules
## Interim: remaining health of each live zombie. To be deleted with #60.
var _ledger: Dictionary[int, float] = {}


func _init(p_rules: GameRules = null) -> void:
	_rules = p_rules


## A zombie that can be shot, with its health from `zombie_spawn_requested`.
func register(target_id: int, health: float) -> void:
	_ledger[target_id] = health


func forget(target_id: int) -> void:
	_ledger.erase(target_id)


func is_alive(target_id: int) -> bool:
	return _ledger.has(target_id)


func health_of(target_id: int) -> float:
	return _ledger.get(target_id, 0.0)


## Applies damage from `shooter_id` to a zombie in `zone` (unused until #60: today the rules only
## hear whether it was the head). Answers `{"applied": bool, "health": float,
## "killed": bool, "events": Array[Dictionary]}`: `events` are the rules' own, to pass on.
func deal(
	shooter_id: int, target_id: int, amount: float, _zone: StringName, headshot: bool, melee: bool
) -> Dictionary:
	var answer := {"applied": false, "health": 0.0, "killed": false, "events": []}
	if not _ledger.has(target_id):
		return answer
	_ledger[target_id] -= amount
	answer["applied"] = true
	answer["health"] = maxf(_ledger[target_id], 0.0)
	answer["killed"] = _ledger[target_id] <= 0.0
	var action: Dictionary
	if answer["killed"]:
		_ledger.erase(target_id)
		action = RulesAction.kill(shooter_id, target_id, headshot, melee)
	else:
		action = RulesAction.hit(shooter_id, target_id, headshot)
	if _rules != null:
		answer["events"] = _rules.apply(action)
	return answer
