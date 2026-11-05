class_name CrewTitles
extends RefCounted
## The crew titles of the film credits, from `crew_titles.json` (docs/design/progression.md#the-
## night-report-and-credits): each names a stat `NightTally` counts and the words that say what the
## player did most. The list is in billing order, which is also the order they are handed out in
## (`NightCredits`: the rarer deeds first, so the night's top scorer does not take every title). The
## `extra` entry is the credit of a player who did none of them.

const PATH := "res://gameplay/progression/crew_titles.json"
## The events that can move a title's stat, beyond those the tally hears for every stat (a client
## reads only these for the credits, so a frame or a shot costs it nothing).
const HEARD: Dictionary[StringName, bool] = {
	&"board_repaired": true,
	&"purchase_made": true,
	&"player_downed": true,
	&"player_revived": true,
	&"points_changed": true,
	&"zombie_removed": true,
}

static var _shared: CrewTitles

## `[{id, title, stat, reason}]` in billing order.
var titles: Array[Dictionary] = []
## `{id, title, reason}` for a player with no title.
var extra := {"id": &"extra", "title": "Extra", "reason": ""}


## The shipped list, read once for the process.
static func shipped() -> CrewTitles:
	if _shared == null:
		_shared = from_text(FileAccess.get_file_as_string(PATH))
	return _shared


## A list from JSON text (`{titles: [...], extra: {...}}`); an entry that is not whole is left out.
static func from_text(text: String) -> CrewTitles:
	var made := CrewTitles.new()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return made
	var data: Dictionary = json.data
	var rows: Variant = data.get("titles", [])
	if typeof(rows) == TYPE_ARRAY:
		for row: Variant in rows:
			if typeof(row) == TYPE_DICTIONARY and _is_title(row):
				(
					made
					. titles
					. append(
						{
							"id": StringName(row["id"]),
							"title": str(row["title"]),
							"stat": StringName(row["stat"]),
							"reason": str(row["reason"]),
						}
					)
				)
	var held: Variant = data.get("extra", {})
	if typeof(held) == TYPE_DICTIONARY and held.has("title"):
		made.extra = {
			"id": StringName(held.get("id", "extra")),
			"title": str(held["title"]),
			"reason": str(held.get("reason", "")),
		}
	return made


## The stats the credits read, once each, in billing order.
func stats() -> Array[StringName]:
	var out: Array[StringName] = []
	for row in titles:
		if not out.has(row["stat"]):
			out.append(row["stat"])
	return out


static func _is_title(row: Dictionary) -> bool:
	for key in ["id", "title", "stat", "reason"]:
		if not row.has(key) or typeof(row[key]) != TYPE_STRING:
			return false
	return true
