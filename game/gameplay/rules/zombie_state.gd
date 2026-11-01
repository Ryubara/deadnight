class_name ZombieState
extends RefCounted
## What the rules know about one living zombie: its type, remaining health and how many of the hits
## on it have paid. Plain data; GameRules is the only thing that changes it.

## The keys of `to_dict`, each with the type it must have.
const SNAPSHOT_KEYS := {
	"id": TYPE_INT,
	"type": TYPE_STRING_NAME,
	"health": TYPE_FLOAT,
	"max_health": TYPE_FLOAT,
	"speed": TYPE_FLOAT,
	"leg_damage": TYPE_FLOAT,
	"crippled": TYPE_BOOL,
	"paid_hits": TYPE_INT,
}

var id: int = 0
var type: StringName = &"walker"
var health: float = 0.0
## The health it spawned with: the crippling bands are fractions of it.
var max_health: float = 0.0
## Metres per second it was given at spawn.
var speed: float = 0.0
## Blast damage that landed on its legs so far.
var leg_damage: float = 0.0
## Its legs are gone: it is a crawler now (once, never undone).
var crippled: bool = false
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
		"leg_damage": leg_damage,
		"crippled": crippled,
		"paid_hits": paid_hits,
	}


static func from_dict(data: Dictionary) -> ZombieState:
	var zombie := ZombieState.new(data["id"], data["health"], data["type"], data["speed"])
	zombie.max_health = data["max_health"]
	zombie.leg_damage = data["leg_damage"]
	zombie.crippled = data["crippled"]
	zombie.paid_hits = data["paid_hits"]
	return zombie
