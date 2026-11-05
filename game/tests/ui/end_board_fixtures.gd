class_name EndBoardFixtures
extends RefCounted
## The fullest end board the game can produce, for the tests and the capture of the board's fit
## (Deadnight #1145): the report with every line and the cap, the credits of a full night, and a
## night's standing for any number of players.

const NAMES := ["Ruby", "Moe", "Dee", "Cal", "Ada", "Bo", "Cy", "Flo"]


## Every line the report has, and the cap, for a night that crossed levels, unlocked things and
## finished both poster sets.
static func fullest_report(kept: bool = true) -> Dictionary:
	var sources := {}
	for line in NightReport.LINES:
		for source: StringName in line["sources"]:
			sources[source] = 1850 * XpRules.HUNDREDTHS
	var hundredths := 0
	for source: StringName in sources:
		hundredths += int(sources[source])
	var sets: Array[Dictionary] = []
	var posters := PosterSets.shipped()
	for each in posters.all():
		sets.append(posters.event_of(each))
	return NightReport.compose(sources, XpRules.to_xp(hundredths), 40 if kept else 0, kept, sets)


## Player n has the most of the nth title's stat, so every title is given while there are players.
## The `bots` after the people have ids from `NightBots.FIRST_ID` and no XP (a bot has no account).
static func fullest_credits(players: int, xp: int = 1500, bots := 0) -> Dictionary:
	var list := CrewTitles.shipped()
	var counts := {}
	var told := {}
	for i in players + bots:
		var id := i + 1 if i < players else NightBots.id_at(i - players)
		var mine := {}
		if i < list.titles.size():
			mine[list.titles[i]["stat"]] = 10 + i
		counts[id] = mine
		if i < players:
			told[id] = xp
	return {"counts": counts, "xp": told}


## The standing of `players` people, the first of them the local one, and `bots` bots after them
## (ids from `NightBots.FIRST_ID`, flagged as bots as the rules' `player_added` does).
static func state(players: int, bots := 0) -> HudState:
	var made := HudState.new()
	made.local_player_id = 1
	for i in players:
		made.set_player_name(i + 1, NAMES[i % NAMES.size()])
		made.team[i + 1]["points"] = 1000 * (players + bots - i)
	for i in bots:
		var id := NightBots.id_at(i)
		made.set_player_name(id, NightBots.name_for(id))
		made.team[id]["bot"] = true
		made.team[id]["points"] = 1000 * (bots - i)
	made.round_number = 7
	made.night_clock = 300
	return made
