class_name PlayerState
extends RefCounted
## What the rules know about one player. Plain data; GameRules is the only thing that changes it.

## The keys of `to_dict`, each with the type it must have.
const SNAPSHOT_KEYS := {
	"id": TYPE_INT,
	"points": TYPE_INT,
	"downed": TYPE_BOOL,
	"weapons": TYPE_ARRAY,
	"tonics": TYPE_ARRAY,
	"grenades": TYPE_INT,
	"repair_points_this_round": TYPE_INT,
	"kills": TYPE_INT,
	"headshot_kills": TYPE_INT,
	"points_earned": TYPE_INT,
	"points_spent": TYPE_INT,
}

var id: int = 0
var points: int = 0
var downed: bool = false
var weapons: Array[StringName] = []
var tonics: Array[StringName] = []
var grenades: int = 0
var repair_points_this_round: int = 0
var kills: int = 0
var headshot_kills: int = 0
var points_earned: int = 0
var points_spent: int = 0


func _init(p_id: int, p_points: int) -> void:
	id = p_id
	points = p_points


func to_dict() -> Dictionary:
	return {
		"id": id,
		"points": points,
		"downed": downed,
		"weapons": weapons.duplicate(),
		"tonics": tonics.duplicate(),
		"grenades": grenades,
		"repair_points_this_round": repair_points_this_round,
		"kills": kills,
		"headshot_kills": headshot_kills,
		"points_earned": points_earned,
		"points_spent": points_spent,
	}


static func from_dict(data: Dictionary) -> PlayerState:
	var player := PlayerState.new(data["id"], data["points"])
	player.downed = data["downed"]
	player.weapons.assign(data["weapons"])
	player.tonics.assign(data["tonics"])
	player.grenades = data["grenades"]
	player.repair_points_this_round = data["repair_points_this_round"]
	player.kills = data["kills"]
	player.headshot_kills = data["headshot_kills"]
	player.points_earned = data["points_earned"]
	player.points_spent = data["points_spent"]
	return player
