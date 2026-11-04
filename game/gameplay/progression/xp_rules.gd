class_name XpRules
extends RefCounted
## What a night's XP is worth, as pure functions: no node, no clock, no file. The game server (a
## kill at a time) and a solo client (at a round's end) run this same code over the same
## `NightTally` counts, so they agree. The design is
## docs/design/progression.md#xp-and-the-ladder-of-55.
##
## Every number is in the table below and nowhere else; the 50, the 100 and the cap are first
## guesses, tuned here. XP is kept in **hundredths** while a night runs: a point a player earns
## is one hundredth, so a kill's points are added as they are earned and the bar rises with every
## kill. Whole XP is `hundredths / 100`, capped for the night.
##
## The lines (a player's own stats):
##   rounds reached   20 XP a round, 10 a round past round 20 (down or not: playing always counts)
##   points earned    1 XP per 100 points the player earned themselves
##   boards mended    2 XP a board, up to 100 XP a night
##   doors opened     15 XP;  fuel cans 15 XP;  a boss brought down 50 XP
##   revives          40 XP, up to 5 a night
##   opening night    50 XP, once ever;  first game of the day 100 XP, once a local day
##   dailies, orders  the amount the challenge board holds (`reward.xp`)
## No streak, no login reward, nothing for opening the game.

## What one XP is in the unit the running total is kept in.
const HUNDREDTHS := 100
## Points earned for one XP: a point is `HUNDREDTHS / POINTS_PER_XP` hundredths.
const POINTS_PER_XP := 100
const ROUND_XP := 20
## Rounds after `LATE_AFTER_ROUND` pay `LATE_ROUND_XP` each.
const LATE_ROUND_XP := 10
const LATE_AFTER_ROUND := 20
const BOARD_XP := 2
## The most boards can pay in a night, in XP (a barricade mended over and over is not a farm).
const BOARD_XP_CAP := 100
const DOOR_XP := 15
const FUEL_CAN_XP := 15
const BOSS_XP := 50
const REVIVE_XP := 40
const REVIVES_PER_NIGHT := 5
const OPENING_NIGHT_XP := 50
const FIRST_GAME_OF_THE_DAY_XP := 100
## The most one night pays, every line and every challenge together.
const NIGHT_CAP := 1500

## The stats that pay, for `stats_of`.
const PAYING: Array[StringName] = [
	ChallengeStats.POINTS,
	ChallengeStats.ROUND,
	ChallengeStats.BOARDS,
	ChallengeStats.DOORS,
	ChallengeStats.FUEL_CANS,
	ChallengeStats.KILLS_BOSS,
	ChallengeStats.REVIVES,
]


## The paying stats of one player's night as `settle` takes them (`{stat: count}`).
static func stats_of(tally: NightTally, player_id: int) -> Dictionary:
	var stats := {}
	for stat in PAYING:
		stats[stat] = tally.count(player_id, stat)
	return stats


## Hundredths of XP that a stat standing at `count` for the night is worth in all (0 for a stat
## that pays nothing). The point of one table: `live` and `settle` both read it.
@warning_ignore("integer_division")
static func worth(stat: StringName, count: int) -> int:
	var n := maxi(count, 0)
	match stat:
		ChallengeStats.POINTS:
			return n * HUNDREDTHS / POINTS_PER_XP
		ChallengeStats.ROUND:
			return round_xp(n) * HUNDREDTHS
		ChallengeStats.BOARDS:
			return mini(n * BOARD_XP, BOARD_XP_CAP) * HUNDREDTHS
		ChallengeStats.DOORS:
			return n * DOOR_XP * HUNDREDTHS
		ChallengeStats.FUEL_CANS:
			return n * FUEL_CAN_XP * HUNDREDTHS
		ChallengeStats.KILLS_BOSS:
			return n * BOSS_XP * HUNDREDTHS
		ChallengeStats.REVIVES:
			return mini(n, REVIVES_PER_NIGHT) * REVIVE_XP * HUNDREDTHS
	return 0


## XP for having reached round `reached` (a night that ends in round 5 reached 5 rounds).
static func round_xp(reached: int) -> int:
	var early := mini(reached, LATE_AFTER_ROUND)
	var late := maxi(reached - LATE_AFTER_ROUND, 0)
	return maxi(early, 0) * ROUND_XP + late * LATE_ROUND_XP


## The hundredths one `NightTally` change adds (`{player_id, stat, value, delta}`): what the stat
## was worth after it, less what it was worth before. This is the unit the server adds to per kill.
static func live(change: Dictionary) -> int:
	var value := int(change["value"])
	var before := value - int(change["delta"])
	var stat: StringName = change["stat"]
	return worth(stat, value) - worth(stat, before)


## Whole XP a finished night is worth, from a player's final stats (`{stat: count}`) and the
## one-off `awards`: `{opening_night: bool, first_game_of_the_day: bool, challenge_xp: int}`.
## Always the same number as the sum of `live` over the night's changes and the same awards.
static func settle(stats: Dictionary, awards: Dictionary = {}) -> int:
	var total := 0
	for stat: StringName in stats:
		total += worth(stat, int(stats[stat]))
	return to_xp(total + award_hundredths(awards))


## The hundredths the one-off `awards` of `settle` are worth.
static func award_hundredths(awards: Dictionary) -> int:
	var total := int(awards.get("challenge_xp", 0)) * HUNDREDTHS
	if awards.get("opening_night", false):
		total += OPENING_NIGHT_XP * HUNDREDTHS
	if awards.get("first_game_of_the_day", false):
		total += FIRST_GAME_OF_THE_DAY_XP * HUNDREDTHS
	return total


## Whole XP of a running total in hundredths, held to the night's cap.
@warning_ignore("integer_division")
static func to_xp(hundredths: int) -> int:
	return mini(maxi(hundredths, 0) / HUNDREDTHS, NIGHT_CAP)
