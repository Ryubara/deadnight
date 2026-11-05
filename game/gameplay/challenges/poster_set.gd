class_name PosterSet
extends RefCounted
## One poster set, as `data/poster_sets.json` writes it: six challenges themed as a fake B-movie,
## each one done uncovers a panel of the poster, all six give the set's `grants` (a calling card
## and an emblem of the plate, the same `card:<id>` / `emblem:<id>` as a challenge's). A plain
## value: what is done is the player's, and the set only reads it.

## How many challenges a set has, and so how many panels its poster has (two across, three down).
const PANELS := 6
const COLUMNS := 2
const ROWS := 3

var id: StringName = &""
var title := ""
## A word or two for a caption too small for the title ("Generator"): the tile of its prize.
var short := ""
## The title as the poster prints it, top to bottom.
var lines: Array[String] = []
## The colour family (`PlatePalettes`) and the large picture (`PlateMotifs`) the poster is made of.
var palette: StringName = &""
var motif: StringName = &""
## The six challenge ids, the order of the panels.
var challenges: Array[StringName] = []
var grants: Array[StringName] = []


static func from_dict(record: Dictionary) -> PosterSet:
	var poster_set := PosterSet.new()
	poster_set.id = StringName(str(record.get("id", "")))
	poster_set.title = String(record.get("title", ""))
	poster_set.short = String(record.get("short", poster_set.title))
	for line: Variant in record.get("lines", []):
		poster_set.lines.append(String(line))
	poster_set.palette = StringName(str(record.get("palette", "")))
	poster_set.motif = StringName(str(record.get("motif", "")))
	for each: Variant in record.get("challenges", []):
		poster_set.challenges.append(StringName(str(each)))
	for grant: Variant in record.get("grants", []):
		poster_set.grants.append(StringName(str(grant)))
	return poster_set


## The piece of `kind` (`card`, `emblem`) the set gives, `&""` for none.
func piece(kind: StringName) -> StringName:
	for grant in grants:
		var parts := String(grant).split(":")
		if parts.size() == 2 and parts[0] == String(kind):
			return StringName(parts[1])
	return &""


## Which panels (0 to 5) the challenges in `done` have uncovered.
func uncovered(done: Array[StringName]) -> Array[int]:
	var found: Array[int] = []
	for index in challenges.size():
		if done.has(challenges[index]):
			found.append(index)
	return found


## Whether every challenge of the set is in `done`.
func is_done(done: Array[StringName]) -> bool:
	return challenges.size() == PANELS and uncovered(done).size() == PANELS
