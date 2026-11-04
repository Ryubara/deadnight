class_name ChallengeStats
extends RefCounted
## The names of the things a night can count for a player. A challenge names one of these; the
## `NightTally` produces them from the night's events and nothing else. A stat is a plain number
## per player: most only grow ("sum" stats), one is a high-water mark ("best" stats).

const KILLS := &"kills"
const KILLS_HEAD := &"kills:head"
const KILLS_MELEE := &"kills:melee"
## A zombie a grenade killed.
const KILLS_BLAST := &"kills:blast"
## A boss or one of its escorts is a type like any other; this counts the bosses alone.
const KILLS_BOSS := &"kills:boss"
const BOARDS := &"boards_repaired"
const DOORS := &"doors_bought"
const BUYS := &"buys"
const FUEL_CANS := &"fuel_cans"
## Teammates the player got up from being down (not themselves).
const REVIVES := &"revives"
## Points taken in (what the HUD shows as gains), without the starting purse.
const POINTS := &"points_earned"
## Rounds that ended while the player was in the lot, down or not: playing always counts.
const ROUNDS := &"rounds"
## The round reached. A best stat: a night's value is the latest round started while present.
const ROUND := &"round"
## Nights played to their end.
const NIGHTS := &"nights"

const FIXED: Array[StringName] = [
	KILLS,
	KILLS_HEAD,
	KILLS_MELEE,
	KILLS_BLAST,
	KILLS_BOSS,
	BOARDS,
	DOORS,
	BUYS,
	FUEL_CANS,
	REVIVES,
	POINTS,
	ROUNDS,
	ROUND,
	NIGHTS,
]
const BEST: Array[StringName] = [ROUND]
const WEAPON_PREFIX := "kills:weapon:"
const TYPE_PREFIX := "kills:type:"


## Kills made with this catalogue weapon (`shotgun`, `crowbar`).
static func weapon_kills(weapon_id: StringName) -> StringName:
	return StringName(WEAPON_PREFIX + String(weapon_id))


## Kills of this zombie type (`walker`, `brute`).
static func type_kills(type_id: StringName) -> StringName:
	return StringName(TYPE_PREFIX + String(type_id))


## True for a high-water mark: its value is the most reached, never a running total.
static func is_best(stat: StringName) -> bool:
	return BEST.has(stat)


## Whether the night can produce this stat, given the weapon and zombie type ids that exist.
static func is_known(
	stat: StringName, weapon_ids: Array[StringName], type_ids: Array[StringName]
) -> bool:
	if FIXED.has(stat):
		return true
	var text := String(stat)
	if text.begins_with(WEAPON_PREFIX):
		return weapon_ids.has(StringName(text.trim_prefix(WEAPON_PREFIX)))
	if text.begins_with(TYPE_PREFIX):
		return type_ids.has(StringName(text.trim_prefix(TYPE_PREFIX)))
	return false
