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
## from `MapRegistry`; a calling card, an emblem or a frame of the plate from `PlateCatalog` (its
## title, its art); anything else (a plate item whose art is not drawn) is its id spelled out.

enum Kind { PART, COLOUR, MAP, OTHER, CARD, EMBLEM, FRAME }

## The ladder's slots that give a piece of the plate, and the kind of piece. The `calling_cards`
## row (level 2) opens the feature and shows the first card.
const PLATE_SLOTS := {
	&"tier_card": PlateCatalog.CARD,
	&"tier_emblem": PlateCatalog.EMBLEM,
	&"emblem": PlateCatalog.EMBLEM,
	&"plate_frame": PlateCatalog.FRAME,
}
const CALLING_CARDS_SLOT := &"calling_cards"

## The colour channel whose palette the ladder's colours belong to (the cloth channels share it).
const COLOUR_CHANNEL := &"primary"


## The item `item` of `slot` gives. `{kind, name}` and, by kind: a PART has `slot` and `id` (the
## catalogue's), a COLOUR has `colour`, a MAP has `info`, a CARD, an EMBLEM or a FRAME has `plate`
## (the piece's id). `table` is `unlocks.json`.
static func of(slot: StringName, item: StringName, table: LadderUnlocks = null) -> Dictionary:
	var rows := table if table != null else LadderUnlocks.shipped()
	var row := rows.find(slot, item)
	var out := {"kind": Kind.OTHER, "name": spelled(item)}
	if row.is_empty():
		return out
	var plate := plate_item(slot, item)
	if not plate.is_empty():
		return plate
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


## What a plate row gives, `{kind, name, plate}`; empty for a row of another slot or a piece the
## plate has not got.
static func plate_item(slot: StringName, item: StringName) -> Dictionary:
	var plates := PlateCatalog.shipped()
	if slot == CALLING_CARDS_SLOT:
		var cards := plates.ids(PlateCatalog.CARD)
		return (
			{}
			if cards.is_empty()
			else {"kind": Kind.CARD, "name": "Calling cards", "plate": cards[0]}
		)
	if not PLATE_SLOTS.has(slot) or not plates.has(PLATE_SLOTS[slot], item):
		return {}
	var kind: StringName = PLATE_SLOTS[slot]
	var title := plates.title(kind, item)
	if kind == PlateCatalog.CARD:
		return {"kind": Kind.CARD, "name": "%s calling card" % title, "plate": item}
	if kind == PlateCatalog.FRAME:
		return {"kind": Kind.FRAME, "name": "%s plate frame" % title, "plate": item}
	return {"kind": Kind.EMBLEM, "name": "%s emblem" % title, "plate": item}


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
