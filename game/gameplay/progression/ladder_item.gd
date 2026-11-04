class_name LadderItem
extends RefCounted
## What a row of the ladder (`unlocks.json`, `LadderUnlocks`) is, as the wardrobe and the maps know
## it: its name and what to draw for it. The popup card and the wardrobe's grid both ask here, so
## they never say two things.
##
##     var item := LadderItem.of(&"top", &"rolled_sleeves")
##     item["name"]    # "Rolled sleeves", the wardrobe cell's own title
##     item["kind"]    # LadderItem.Kind.PART, with item["slot"] = &"torso", item["id"] = &"rolled"
##
## A wearable is read from the part registry (`LookCatalog`), a colour from the cloth palette, a map
## from `MapRegistry`; anything else (a plate item whose art is not drawn) is its id spelled out.

enum Kind { PART, COLOUR, MAP, OTHER }

## The colour channel whose palette the ladder's colours belong to (the cloth channels share it).
const COLOUR_CHANNEL := &"primary"


## The item `item` of `slot` gives. `{kind, name}` and, by kind: a PART has `slot` and `id` (the
## catalogue's), a COLOUR has `colour`, a MAP has `info`. `table` is `unlocks.json`.
static func of(slot: StringName, item: StringName, table: LadderUnlocks = null) -> Dictionary:
	var rows := table if table != null else LadderUnlocks.shipped()
	var row := rows.find(slot, item)
	var out := {"kind": Kind.OTHER, "name": spelled(item)}
	if row.is_empty():
		return out
	if slot == &"colour":
		for entry: Dictionary in LookCatalog.palette(COLOUR_CHANNEL):
			if entry["id"] == item:
				return {"kind": Kind.COLOUR, "name": entry["label"], "colour": entry["colour"]}
	elif slot == &"map":
		for info in MapRegistry.all():
			if info.unlock_level == int(row["level"]):
				return {"kind": Kind.MAP, "name": info.title, "info": info}
	elif String(row["part"]) != "":
		var part_slot := StringName(String(row["part"]).get_slice("/", 0))
		var part_id := StringName(String(row["part"]).get_slice("/", 1))
		var label := part_label(part_slot, part_id)
		if label != "":
			return {"kind": Kind.PART, "name": label, "slot": part_slot, "id": part_id}
	return out


## The name the wardrobe gives the part `id` of `slot` (a piece with a model, or one still to come).
static func part_label(slot: StringName, id: StringName) -> String:
	for option: Dictionary in LookCatalog.options(slot):
		if option["id"] == id:
			return option["label"]
	for option: Dictionary in LookCatalog.pending(slot):
		if option["id"] == id:
			return option["label"]
	return ""


## An id as words: spaces for the underscores and a capital.
static func spelled(item: StringName) -> String:
	var words := String(item).replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)
