class_name BalancePace
extends RefCounted
## How fast a balance cell levels a player up: a mean seeded night turned into XP and minutes, and
## those into the time to a level. The pace of the whole progression (about 8 hours to level 55 at
## 300 or more kills a night, docs/design/progression.md#xp-and-the-ladder-of-55) is read here, so
## a retune of the rounds or the economy that moves it, or a curve that goes flat, fails a test.
##
## Only what the simulator plays counts: rounds reached and points earned (XP lines are
## `XpRules`'); boards, doors, fuel, bosses, revives, challenges and the day's first game pay
## more, so every time here is an upper bound for a player who does those things. The opening
## night's XP is credited, once.

## Seconds in menus and the night report between two nights (the design page's assumption).
const MENU_SECONDS := 120.0


## A mean night of `cell`: `{xp, rounds, kills, play_seconds, total_seconds}`. `total_seconds`
## adds the intro, the breaks and the menus to the rounds' own clock.
static func night(cell: Dictionary, tuning: RulesTuning) -> Dictionary:
	var nights := float(cell["nights"])
	var xp := 0.0
	var rounds := 0.0
	var seconds := tuning.rounds.intro_seconds
	var kills := 0.0
	for r in range(1, cell["reached"].size()):
		var reached: float = cell["reached"][r]
		if reached <= 0.0:
			continue
		var share := reached / nights
		var earned: float = cell["earned"][r] / reached
		rounds += share
		xp += share * float(XpRules.round_xp(r) - XpRules.round_xp(r - 1))
		xp += share * earned / XpRules.POINTS_PER_XP
		seconds += share * (cell["duration"][r] / reached + tuning.rounds.break_seconds)
		kills += cell["kills"][r] / nights
	return {
		"xp": xp,
		"rounds": rounds,
		"kills": kills,
		"play_seconds": seconds,
		"total_seconds": seconds + MENU_SECONDS,
	}


## XP an hour of nights, with the menus between them.
static func xp_per_hour(cell: Dictionary, tuning: RulesTuning) -> float:
	var mean := night(cell, tuning)
	return mean["xp"] / (mean["total_seconds"] / 3600.0)


## Minutes of nights to reach `level` from nothing (the opening night's XP credited).
static func minutes_to(cell: Dictionary, tuning: RulesTuning, level: int) -> float:
	var needed := maxf(float(LevelCurve.xp_for(level) - XpRules.OPENING_NIGHT_XP), 0.0)
	return needed / xp_per_hour(cell, tuning) * 60.0


## Minutes to climb from `level` to the next, at the cell's pace (the last level to the one after).
static func minutes_for(cell: Dictionary, tuning: RulesTuning, level: int) -> float:
	return float(LevelCurve.to_leave(level)) / xp_per_hour(cell, tuning) * 60.0
