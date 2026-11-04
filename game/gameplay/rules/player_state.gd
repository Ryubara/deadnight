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
	"downs": TYPE_INT,
	"revives": TYPE_INT,
	"dead": TYPE_BOOL,
	"bleed_left": TYPE_FLOAT,
	"self_revives": TYPE_INT,
	"self_revive_left": TYPE_FLOAT,
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
## The weapons carried, as shop ids, at most `WeaponCatalog.CARRY_LIMIT`, the oldest first. The
## start weapons are in it; one replaced by a third is taken out (`WeaponCarry`).
var weapons: Array[StringName] = []
## The tonics (perks, `ShopItem.Kind.TONIC`) this player has had and still has, in the order they
## were had. A player who goes down loses some or all of them (`PerkTuning.lost_on_down`).
var tonics: Array[StringName] = []
## The weapons (catalogue ids) this player has had re-cut this night.
var upgraded: Array[StringName] = []
var grenades: int = 0
var repair_points_this_round: int = 0
var kills: int = 0
var headshot_kills: int = 0
## How many times this player went down this night (a blow or a forced down), for the scoreboard.
var downs: int = 0
## How many teammates this player has pulled up this night, for the scoreboard. A getting up at a
## round's end is nobody's revive.
var revives: int = 0
## Bled out: down until the round ends, and not to be revived. `downed` stays true as well, so every
## rule that refuses a downed player refuses a dead one.
var dead: bool = false
## Seconds a downed player has left before they are dead (0 when up or dead).
var bleed_left: float = 0.0
## How many times the revive perk has got this player up alone this night, and the seconds left of
## the one under way (0 when none is).
var self_revives: int = 0
var self_revive_left: float = 0.0
var points_earned: int = 0
var points_spent: int = 0
## Whether a bot plays this seat. A person who joins takes a bot's seat as it stands (points,
## weapons, health) and the flag goes (`RulesAction.seat_person`).
var bot: bool = false


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
		"downs": downs,
		"revives": revives,
		"dead": dead,
		"bleed_left": bleed_left,
		"self_revives": self_revives,
		"self_revive_left": self_revive_left,
		"points_earned": points_earned,
		"points_spent": points_spent,
		"bot": bot,
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
	player.downs = data["downs"]
	player.revives = data["revives"]
	player.dead = data["dead"]
	player.bleed_left = data["bleed_left"]
	player.self_revives = data["self_revives"]
	player.self_revive_left = data["self_revive_left"]
	player.points_earned = data["points_earned"]
	player.points_spent = data["points_spent"]
	player.bot = bool(data.get("bot", false))
	return player
