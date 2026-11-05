class_name EndBoardFixtures
extends RefCounted
## The fullest end board the game can produce, for the tests and the capture of the board's fit
## (Deadnight #1145): the report with every line and the cap, the credits of a full night, and a
## night's standing for any number of players.

const NAMES := ["Ruby", "Moe", "Dee", "Cal", "Ada", "Bo", "Cy", "Flo"]


## Every line the report has, and the cap, for a night that crossed levels and unlocked things.
static func fullest_report(kept: bool = true) -> Dictionary:
	var sources := {}
	for line in NightReport.LINES:
		for source: StringName in line["sources"]:
			sources[source] = 1850 * XpRules.HUNDREDTHS
	var hundredths := 0
	for source: StringName in sources:
		hundredths += int(sources[source])
	return NightReport.compose(sources, XpRules.to_xp(hundredths), 40 if kept else 0, kept)


## Player n has the most of the nth title's stat, so every title is given while there are players.
static func fullest_credits(players: int, xp: int = 1500) -> Dictionary:
	var list := CrewTitles.shipped()
	var counts := {}
	var told := {}
	for i in players:
		var mine := {}
		if i < list.titles.size():
			mine[list.titles[i]["stat"]] = 10 + i
		counts[i + 1] = mine
		told[i + 1] = xp
	return {"counts": counts, "xp": told}


## The standing of `players` players, the first of them the local one.
static func state(players: int) -> HudState:
	var made := HudState.new()
	made.local_player_id = 1
	for i in players:
		made.set_player_name(i + 1, NAMES[i % NAMES.size()])
		made.team[i + 1]["points"] = 1000 * (players - i)
	made.round_number = 7
	made.night_clock = 300
	return made
