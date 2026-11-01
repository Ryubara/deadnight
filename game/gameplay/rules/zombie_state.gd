class_name ZombieState
extends RefCounted
## What the rules know about one living zombie: its type, remaining health and how many of the hits
## on it have paid. Plain data; GameRules is the only thing that changes it.

var id: int = 0
var type: StringName = &"walker"
var health: float = 0.0
var max_health: float = 0.0
## Metres per second it was given at spawn (kept so a change of type can rescale it).
var speed: float = 0.0
## Non-lethal hits on this zombie that already paid points (capped: a zombie is a bounded purse).
var paid_hits: int = 0


func _init(
	p_id: int, p_health: float, p_type: StringName = &"walker", p_speed: float = 0.0
) -> void:
	id = p_id
	health = p_health
	max_health = p_health
	type = p_type
	speed = p_speed


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"health": health,
		"max_health": max_health,
		"speed": speed,
		"paid_hits": paid_hits,
	}


static func from_dict(data: Dictionary) -> ZombieState:
	var zombie := ZombieState.new(data["id"], data["health"], data["type"], data["speed"])
	zombie.max_health = data["max_health"]
	zombie.paid_hits = data["paid_hits"]
	return zombie
