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
## Times the player went down (a blow took the last of their health, or the rules put them down).
const DOWNS := &"downs"
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
## Nights played to their end with another person in the lot (a bot is not one).
const NIGHTS_TOGETHER := &"nights:together"
## Points the player paid at the stand (a purchase's price), not points lost to a down.
const POINTS_SPENT := &"points_spent"
## Rounds that ended with the player on their feet and no gun fired by them in it (melee and
## grenades are no shots).
const ROUNDS_UNFIRED := &"rounds:unfired"
## Rounds that ended with the player on their feet and not one kill of theirs in it.
const ROUNDS_NO_KILLS := &"rounds:no_kills"
## Rounds that ended with every player in the round on their feet (two or more of them).
const ROUNDS_WHOLE := &"rounds:whole_crew"
## Rounds that ended with the player's gun dry: the magazine empty and nothing in reserve.
const ROUNDS_DRY := &"rounds:dry"
## Rounds the player spent whole inside the booth.
const ROUNDS_BOOTH := &"rounds:booth"
## The latest round started with nothing spent at the stand all night. A best stat.
const ROUND_UNSPENT := &"round:unspent"
## The latest round cleared with every circuit off from its start to its end. A best stat.
const ROUND_DARK := &"round:dark"
## The most zombies one blast killed. A best stat.
const BLAST_BEST := &"blast:best"
## Three boards put up on one window by the player in a short time.
const BOARD_RUSHES := &"board_rushes"
## Boards put up on a window a teammate was also mending, at once.
const BOARDS_SHARED := &"boards:shared"
## Doors bought in the night's first half minute.
const DOORS_EARLY := &"doors:early"
## Nights in which the last way through opened before round five, for the lot present.
const DOORS_ALL_EARLY := &"doors:all_early"
## Runs of five crawlers put down with the crowbar in half a minute.
const CRAWLER_RUNS := &"crawler_runs"
## Times the player went down in the first seconds of a round.
const DOWNS_EARLY := &"downs:early"
## Breaks (between two rounds) the player spent whole at the stand.
const BREAKS_STAND := &"breaks:stand"
## The latest round started with the map's second door still shut. A best stat.
const ROUND_LONG_WAY := &"round:long_way"
## Times the player died in the first round (bled out, or the night ended with them down).
const DEATHS_ROUND_ONE := &"deaths:round_one"
## Nights that ended with the same four or more people in the lot as at the first round.
const NIGHTS_FULL_LOT := &"nights:full_lot"

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
	DOWNS,
	REVIVES,
	POINTS,
	ROUNDS,
	ROUND,
	NIGHTS,
	NIGHTS_TOGETHER,
	POINTS_SPENT,
	ROUNDS_UNFIRED,
	ROUNDS_NO_KILLS,
	ROUNDS_WHOLE,
	ROUNDS_DRY,
	ROUNDS_BOOTH,
	ROUND_UNSPENT,
	ROUND_DARK,
	BLAST_BEST,
	BOARD_RUSHES,
	BOARDS_SHARED,
	DOORS_EARLY,
	DOORS_ALL_EARLY,
	CRAWLER_RUNS,
	DOWNS_EARLY,
	BREAKS_STAND,
	ROUND_LONG_WAY,
	DEATHS_ROUND_ONE,
	NIGHTS_FULL_LOT,
]
const BEST: Array[StringName] = [ROUND, ROUND_UNSPENT, ROUND_DARK, BLAST_BEST, ROUND_LONG_WAY]
const WEAPON_PREFIX := "kills:weapon:"
const TYPE_PREFIX := "kills:type:"
## Nights played to their end on a map: `nights:map:<id>`.
const MAP_PREFIX := "nights:map:"


## Kills made with this catalogue weapon (`shotgun`, `crowbar`).
static func weapon_kills(weapon_id: StringName) -> StringName:
	return StringName(WEAPON_PREFIX + String(weapon_id))


## Kills of this zombie type (`walker`, `brute`).
static func type_kills(type_id: StringName) -> StringName:
	return StringName(TYPE_PREFIX + String(type_id))


## Nights played to their end on this map (`drive_in`, `small_indoor`).
static func map_nights(map_id: StringName) -> StringName:
	return StringName(MAP_PREFIX + String(map_id))


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
	if text.begins_with(MAP_PREFIX):
		return MapRegistry.find(text.trim_prefix(MAP_PREFIX)) != null
	return false
