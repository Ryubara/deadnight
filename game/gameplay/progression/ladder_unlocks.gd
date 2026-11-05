class_name LadderUnlocks
extends RefCounted
## What each level of the ladder gives, from `unlocks.json` (the design page's table: a row is
## `{level, slot, item, part, label, available}`; `part` is a wearable's catalogue key, `label` the
## name of one the art does not have yet). A level with no row gives only its icon. An item whose
## art is not drawn yet has `available` false: it is listed, but nobody is told they earned it (the
## level's own card is enough) until the piece lands and the row is flipped. The wardrobe, the maps
## and the plate read the same file, so a row is added in one place.

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
					"part": String(row.get("part", "")),
					"label": String(row.get("label", "")),
					"available": row.get("available", true) == true,
				}
			)
		)
	return table


## The row of `item` in `slot`, or an empty dictionary: what the server's `unlock_earned` names.
func find(slot: StringName, item: StringName) -> Dictionary:
	for at in levels():
		for row: Dictionary in _by_level[at]:
			if row["slot"] == slot and row["item"] == item:
				return row
	return {}


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


## The first level after `level` that gives something a player can be told about, as
## `{level, label}` (the label names its first item, `label_of`); empty past the last one.
func next_after(level: int) -> Dictionary:
	for at in levels():
		if at > level:
			var rows := earned_at(at)
			if not rows.is_empty():
				return {"level": at, "label": label_of(rows[0])}
	return {}


## What a row gives, in words ("rolled_sleeves" is "rolled sleeves"; a map is named as one).
static func label_of(row: Dictionary) -> String:
	var words := String(row["item"]).replace("_", " ")
	match row["slot"]:
		&"map":
			return "%s map" % words
		&"tier_card":
			return "%s card" % words
		&"tier_emblem", &"emblem":
			return "%s emblem" % words
	return words


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
