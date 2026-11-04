class_name LadderUnlocks
extends RefCounted
## What each level of the ladder gives, from `unlocks.json` (the design page's table: a row is
## `{level, slot, item, available}`). A level with no row gives only its icon. An item whose art is
## not drawn yet has `available` false: it is listed, but nobody is told they earned it (the level's
## own card is enough) until the piece lands and the row is flipped. The wardrobe, the maps and the
## plate read the same file, so a row is added in one place.

const PATH := "res://gameplay/progression/unlocks.json"

static var _shared: LadderUnlocks

## Level -> the rows of that level (`{level, slot, item, available}`).
var _by_level: Dictionary[int, Array] = {}


## The shipped table, read once for the process.
static func shipped() -> LadderUnlocks:
	if _shared == null:
		_shared = from_text(FileAccess.get_file_as_string(PATH))
	return _shared


## A table from JSON text (an array of rows). A row that is not a row is left out.
static func from_text(text: String) -> LadderUnlocks:
	var table := LadderUnlocks.new()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_ARRAY:
		return table
	for row: Variant in json.data:
		if typeof(row) != TYPE_DICTIONARY or not _is_row(row):
			continue
		var level := int(row["level"])
		var rows: Array = table._by_level.get_or_add(level, [])
		(
			rows
			. append(
				{
					"level": level,
					"slot": StringName(row["slot"]),
					"item": StringName(row["item"]),
					"available": row.get("available", true) == true,
				}
			)
		)
	return table


## Every row a level gives, available or not.
func at_level(level: int) -> Array:
	return _by_level.get(level, [])


## The rows a level gives that a player can be told about now (art drawn).
func earned_at(level: int) -> Array:
	var rows: Array = []
	for row: Dictionary in at_level(level):
		if row["available"]:
			rows.append(row)
	return rows


## Every level that has a row.
func levels() -> Array[int]:
	var out: Array[int] = []
	out.assign(_by_level.keys())
	out.sort()
	return out


static func _is_row(row: Dictionary) -> bool:
	return (
		typeof(row.get("level")) in [TYPE_INT, TYPE_FLOAT]
		and typeof(row.get("slot")) == TYPE_STRING
		and typeof(row.get("item")) == TYPE_STRING
	)
