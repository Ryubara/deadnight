class_name NightReport
extends RefCounted
## The card at the end of a night, as data: the lines of the XP the night paid, the level bar and
## what the next level gives (docs/design/progression.md#the-night-report-and-credits). It adds no
## XP of its own. The numbers are the night's `sources` (hundredths of XP by the stat or award that
## paid them, as `XpAward` tells them in `xp_gained`, or as `XpRules.worth` counts them for a night
## nobody keeps) and the night's whole XP (`XpRules.to_xp` of their sum). The lines are those
## numbers cut into whole XP so that **they add up to the total exactly**: each line is rounded
## down and the XP left over goes to the lines that lost the most to the rounding.
##
## A night over the cap (`XpRules.NIGHT_CAP`) shows the part the cap took as a last, negative line.

## The lines, in the order they are shown: `id`, the heading and the sources each one adds up.
const LINES: Array[Dictionary] = [
	{"id": &"rounds", "label": "Rounds", "sources": [ChallengeStats.ROUND]},
	{"id": &"points", "label": "Points", "sources": [ChallengeStats.POINTS]},
	{
		"id": &"upkeep",
		"label": "Upkeep",
		"sources": [ChallengeStats.BOARDS, ChallengeStats.DOORS, ChallengeStats.FUEL_CANS],
	},
	{"id": &"headliners", "label": "Headliners", "sources": [ChallengeStats.KILLS_BOSS]},
	{"id": &"rescues", "label": "Rescues", "sources": [ChallengeStats.REVIVES]},
	{"id": &"challenges", "label": "Challenges", "sources": [XpAward.CHALLENGE]},
	{"id": &"opening_night", "label": "Opening night", "sources": [XpAward.OPENING_NIGHT]},
	{"id": &"first_game", "label": "First game of the day", "sources": [XpAward.FIRST_GAME]},
]
## Where a source no line names goes, so the lines still add up.
const OTHER := {"id": &"other", "label": "Other"}
const CAP := {"id": &"cap", "label": "Night limit"}

## The lines of a night: `[{id, label, xp}]` in the order of `LINES`, only those that paid at
## least one whole XP, adding up to `xp` (the night's whole XP, the cap held).
@warning_ignore("integer_division")
static func lines(sources: Dictionary, xp: int) -> Array[Dictionary]:
	var shares := _shares(sources)
	var floors := 0
	for share in shares:
		share["xp"] = int(share["hundredths"]) / XpRules.HUNDREDTHS
		share["rest"] = int(share["hundredths"]) % XpRules.HUNDREDTHS
		floors += int(share["xp"])
	var owed := xp - floors
	if owed > 0:
		var by_rest := shares.duplicate()
		by_rest.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				if a["rest"] != b["rest"]:
					return int(a["rest"]) > int(b["rest"])
				return int(a["order"]) < int(b["order"])
		)
		var given := 0
		for share in by_rest:
			if given < owed and int(share["rest"]) > 0:
				share["xp"] = int(share["xp"]) + 1
				given += 1
		# XP the sources do not show (a client that came in after the night began never heard what
		# paid it) is "other", so the lines still add up.
		if given < owed:
			var other := _other(shares)
			other["xp"] = int(other["xp"]) + owed - given
	var out: Array[Dictionary] = []
	for share in shares:
		if int(share["xp"]) > 0:
			out.append({"id": share["id"], "label": share["label"], "xp": int(share["xp"])})
	if owed < 0:
		out.append({"id": CAP["id"], "label": CAP["label"], "xp": owed})
	return out


## The whole report. `sources` and `xp` are the night's; `start_total` is the account's raw XP
## when the night began and `kept` whether an account holds this night (false: the night would
## have paid this much and nothing was saved, and there is no level bar). Keys: `kept`, `lines`,
## `xp`, and when kept `level_from`, `level_to`, `crossed` (the levels the night reached),
## `unlocked` (what they gave: `{level, slot, item, label}`), `fraction_from` and `fraction_to` (the
## bar of the level the night ended in: where the night started in it, 0 when it crossed a level,
## and where it ended), `in_level`, `to_leave` (0 at the top), `to_next` and `next` (the next level
## that gives something to wear or play, `{level, label}`, empty when there is none).
static func compose(sources: Dictionary, xp: int, start_total: int, kept: bool) -> Dictionary:
	var model := {"kept": kept, "lines": lines(sources, xp), "xp": xp}
	if not kept:
		return model
	var begin := maxi(start_total, 0)
	var end := begin + xp
	var from := LevelCurve.level_of(begin)
	var to := LevelCurve.level_of(end)
	var crossed: Array[int] = []
	var unlocked: Array[Dictionary] = []
	for level in range(from + 1, to + 1):
		crossed.append(level)
		for row: Dictionary in LadderUnlocks.shipped().earned_at(level):
			(
				unlocked
				. append(
					{
						"level": level,
						"slot": row["slot"],
						"item": row["item"],
						"label": LadderUnlocks.label_of(row),
					}
				)
			)
	model["level_from"] = from
	model["level_to"] = to
	model["crossed"] = crossed
	model["unlocked"] = unlocked
	model["fraction_from"] = LevelCurve.fraction(begin) if from == to else 0.0
	model["fraction_to"] = LevelCurve.fraction(end)
	model["in_level"] = LevelCurve.xp_in_level(end)
	model["to_leave"] = LevelCurve.to_leave(to)
	model["to_next"] = LevelCurve.to_next(end)
	var next := LadderUnlocks.shipped().next_after(to)
	model["next"] = ({} if next.is_empty() else {"level": next["level"], "label": next["label"]})
	return model


## The night's `sources` of a stat count (`{stat: count}`, `XpRules.stats_of`) for a night nobody
## keeps: what `XpRules.worth` says each paid.
static func sources_of_stats(stats: Dictionary) -> Dictionary:
	var out := {}
	for stat: StringName in stats:
		var worth := XpRules.worth(stat, int(stats[stat]))
		if worth > 0:
			out[stat] = worth
	return out


## The `OTHER` share of `shares`, added when there is none.
static func _other(shares: Array[Dictionary]) -> Dictionary:
	for share in shares:
		if share["id"] == OTHER["id"]:
			return share
	var made := {
		"id": OTHER["id"],
		"label": OTHER["label"],
		"hundredths": 0,
		"order": shares.size(),
		"xp": 0,
		"rest": 0,
	}
	shares.append(made)
	return made


## The hundredths in each line of `LINES` (and `OTHER`, for what no line names).
static func _shares(sources: Dictionary) -> Array[Dictionary]:
	var named := {}
	var out: Array[Dictionary] = []
	for line in LINES:
		var hundredths := 0
		for source: StringName in line["sources"]:
			hundredths += int(sources.get(source, 0))
			named[source] = true
		(
			out
			. append(
				{
					"id": line["id"],
					"label": line["label"],
					"hundredths": hundredths,
					"order": out.size(),
				}
			)
		)
	var other := 0
	for source: Variant in sources:
		if not named.has(source):
			other += int(sources[source])
	if other > 0:
		(
			out
			. append(
				{
					"id": OTHER["id"],
					"label": OTHER["label"],
					"hundredths": other,
					"order": out.size(),
				}
			)
		)
	return out
