class_name PlayerState
extends RefCounted
## What the rules know about one player. Plain data; GameRules is the only thing that changes it.

## The keys of `to_dict`, each with the type it must have.
const SNAPSHOT_KEYS := {
	"id": TYPE_INT,
	"points": TYPE_INT,
	"downed": TYPE_BOOL,
	"health": TYPE_FLOAT,
	"max_health": TYPE_FLOAT,
	"since_blow": TYPE_FLOAT,
	"weapons": TYPE_ARRAY,
	"tonics": TYPE_ARRAY,
	"upgraded": TYPE_ARRAY,
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
## Health left, 0 to `max_health`; a player is down at zero (and `downed` says so).
var health: float = 0.0
## The most `health` can be. Per player, so a tonic can raise it.
var max_health: float = 0.0
## Seconds since the last blow, counted up to the regeneration delay and no further.
var since_blow: float = 0.0
var weapons: Array[StringName] = []
var tonics: Array[StringName] = []
## The weapons (catalogue ids) this player has had tuned up this night.
var upgraded: Array[StringName] = []
var grenades: int = 0
var repair_points_this_round: int = 0
var kills: int = 0
var headshot_kills: int = 0
var points_earned: int = 0
var points_spent: int = 0


## What a repair pays now, under the cap on repair pay from one round's end to the next; counts it.
func repair_pay(economy: EconomyTuning) -> int:
	var pay := maxi(
		mini(economy.repair, economy.repair_cap_per_round - repair_points_this_round), 0
	)
	repair_points_this_round += pay
	return pay


func _init(p_id: int, p_points: int) -> void:
	id = p_id
	points = p_points


func to_dict() -> Dictionary:
	return {
		"id": id,
		"points": points,
		"downed": downed,
		"health": health,
		"max_health": max_health,
		"since_blow": since_blow,
		"weapons": weapons.duplicate(),
		"tonics": tonics.duplicate(),
		"upgraded": upgraded.duplicate(),
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
	player.health = data["health"]
	player.max_health = data["max_health"]
	player.since_blow = data["since_blow"]
	player.weapons.assign(data["weapons"])
	player.tonics.assign(data["tonics"])
	player.upgraded.assign(data["upgraded"])
	player.grenades = data["grenades"]
	player.repair_points_this_round = data["repair_points_this_round"]
	player.kills = data["kills"]
	player.headshot_kills = data["headshot_kills"]
	player.points_earned = data["points_earned"]
	player.points_spent = data["points_spent"]
	return player
