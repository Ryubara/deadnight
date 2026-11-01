class_name ZombieState
extends RefCounted
## What the rules know about one living zombie: its remaining health and how many of the hits on it
## have paid. Plain data; GameRules is the only thing that changes it.

var id: int = 0
var health: float = 0.0
## Non-lethal hits on this zombie that already paid points (capped: a zombie is a bounded purse).
var paid_hits: int = 0


func _init(p_id: int, p_health: float) -> void:
	id = p_id
	health = p_health


func to_dict() -> Dictionary:
	return {"id": id, "health": health, "paid_hits": paid_hits}


static func from_dict(data: Dictionary) -> ZombieState:
	var zombie := ZombieState.new(data["id"], data["health"])
	zombie.paid_hits = data["paid_hits"]
	return zombie
