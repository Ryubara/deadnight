class_name LookCatalog
extends RefCounted
## Every choice a player can make about how their character looks: the part options of each slot,
## the colours of each palette, and the eight presets. Plain data, no nodes.
##
## The data is `parts.json` of the modular Soldier parts (docs/design/characters.md), written by
## the build script beside the model: slots with their parts, colour channels with their
## palettes, and the presets. Nothing about a part is repeated here except what the file does not
## know: the titles of the screen's rows and what a locked entry asks for.
##
## The catalogue is append-only for a given `CharacterLook.VERSION`: the wire format sends a part
## as its index in its slot and a colour as its index in its palette, so entries are added at the
## end and never reordered or removed. A change that cannot follow that rule bumps the version.
## A slot with fewer than two parts is not shown on the customization screen.
##
## The character (#678) is the `body` part slot: `male` is the Soldier as built, `female` shows her
## variant of the face, mouth, torso and legs (`SoldierLook.visible_meshes`), so every other choice
## fits both. It has a row of its own at the top of the screen, not a part row. The `mouth` slot
## (#1061) came after it on the wire, and is free to everyone: `unlocks.json` does not name it.

const CATALOG_PATH := "res://assets/characters/soldier_parts/parts.json"

## Screen titles of the part slots.
const PART_TITLES := {
	&"head": "Face",
	&"hair": "Hair style",
	&"headwear": "Headwear",
	&"torso": "Top",
	&"legs": "Trousers",
	&"feet": "Footwear",
	&"eyewear": "Eyewear",
	&"neck": "Neckwear",
	&"arm": "Armwear",
	&"body": "Character",
	&"mouth": "Mouth",
}
## Rows that do not follow the wire's order: this slot's row comes right after that slot's.
const ROW_AFTER := {&"mouth": &"head"}
## Screen titles of the colour channels.
const COLOUR_TITLES := {
	&"skin": "Skin",
	&"hair": "Hair colour",
	&"primary": "Main colour",
	&"secondary": "Second colour",
	&"accent": "Trim colour",
}

## The fixed armband colour of each seat in the lot. Never part of the look: a teammate stays
## readable in the dark whatever they wear.
const ARMBAND_COLOURS: Array[Color] = [
	Color("ff4b3e"),
	Color("38d6ff"),
	Color("ffe14a"),
	Color("9cff57"),
	Color("ff9a2e"),
	Color("b57bff"),
	Color("ff6fc8"),
	Color("f2f2f2"),
]

## The ladder: which wearables and colours a level opens, the rows of the progression table
## (`gameplay/progression/unlocks.json`, #1065). A part or colour it does not name is free:
## it has no gate.
const UNLOCKS_PATH := "res://gameplay/progression/unlocks.json"
## The palette the ladder's colours belong to (the three cloth channels share it).
const CLOTH := "cloth"
## The slot that holds the character, and its two choices.
const BODY_SLOT := &"body"
const MALE := &"male"
const FEMALE := &"female"

static var _data: Dictionary = {}
static var _slots: Array[StringName] = []
static var _channels: Array[StringName] = []
static var _options: Dictionary = {}
static var _palettes: Dictionary = {}
static var _presets: Array[Dictionary] = []
static var _part_gates: Dictionary = {}
static var _palette_gates: Dictionary = {}
static var _pending: Dictionary = {}
static var _ladder_parts: Array[Dictionary] = []


## The part slots, in wire order.
static func part_slots() -> Array[StringName]:
	_load()
	return _slots


## The colour channels, in wire order.
static func colour_slots() -> Array[StringName]:
	_load()
	return _channels


## The parts of `slot` in wire order: `id`, `label`, `label_female` (what she calls it), `gate`
## and, for hair, `body` (the character the cut belongs to, or &"" for either).
static func options(slot: StringName) -> Array:
	_load()
	return _options.get(slot, [])


## The colours of `channel` in wire order: `id`, `label`, `colour`, `gate`.
static func palette(channel: StringName) -> Array:
	_load()
	return _palettes.get(channel, [])


## What a locked part asks for, by "<slot>/<id>" (a gate is `LookUnlocks`'s dictionary).
static func part_gates() -> Dictionary:
	_load()
	return _part_gates


## The same for a colour, by "<channel>/<palette index>": a gate of the cloth palette is on all
## three cloth channels.
static func palette_gates() -> Dictionary:
	_load()
	return _palette_gates


## The wearables the ladder promises that have no model yet, of `slot`: `id`, `label`,
## `label_female` and `gate`. They show in the wardrobe by their icon, locked or not, and cannot be
## worn; each leaves this list when `parts.json` gets it.
static func pending(slot: StringName) -> Array:
	_load()
	return _pending.get(slot, [])


## The part of `slot` a look falls back to when what it wears is not the player's: the first one
## this player may wear (every slot has a free one).
static func first_open(slot: StringName, unlocks: LookUnlocks) -> StringName:
	for option: Dictionary in options(slot):
		if unlocks.is_unlocked(slot, option["id"], option["gate"]):
			return option["id"]
	return options(slot)[0]["id"]


## The palette index of `channel` a look falls back to: the first the player may use.
static func first_open_colour(channel: StringName, unlocks: LookUnlocks) -> int:
	var entries := palette(channel)
	for i in entries.size():
		if unlocks.is_unlocked(channel, entries[i]["id"], entries[i]["gate"]):
			return i
	return 0


## The presets: `id`, `name`, `parts` (id by slot) and `colours` (palette index by channel). The
## first is the default look of a player who has not picked one.
static func presets() -> Array[Dictionary]:
	_load()
	return _presets


## Index of the part with `id` in `slot`, or -1.
static func option_index(slot: StringName, id: StringName) -> int:
	var list := options(slot)
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return -1


## The slots that give the player a real choice (two parts or more), the character's apart (it
## has its own row), in the order of the screen's rows.
static func choosable_part_slots() -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in part_slots():
		if slot == BODY_SLOT or options(slot).size() < 2 or ROW_AFTER.has(slot):
			continue
		out.append(slot)
		for moved: StringName in ROW_AFTER:
			if ROW_AFTER[moved] == slot:
				out.append(moved)
	return out


## What part `index` of `slot` is called on `body` (her face choices have names of their own).
static func label(slot: StringName, index: int, body: StringName) -> String:
	var option: Dictionary = options(slot)[index]
	return option["label_female"] if body == FEMALE else option["label"]


## The hair a character starts from (switching the character swaps one cut for the other).
static func body_hair(body: StringName) -> StringName:
	_load()
	return StringName(_data.get("body", {}).get("hair", {}).get(String(body), "crew"))


## The character a hair cut belongs to, or &"" when either wears it.
static func hair_body(hair: StringName) -> StringName:
	var index := option_index(&"hair", hair)
	return options(&"hair")[index]["body"] if index >= 0 else &""


static func armband_colour(seat: int) -> Color:
	return ARMBAND_COLOURS[posmod(seat, ARMBAND_COLOURS.size())]


## Reads the catalogue again (a test that swaps `CATALOG_PATH` uses this).
static func reload() -> void:
	_data = {}
	_load()


static func _load() -> void:
	if not _data.is_empty():
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CATALOG_PATH)) != OK:
		push_error("LookCatalog: cannot read %s" % CATALOG_PATH)
		return
	_data = json.data
	_slots.clear()
	_channels.clear()
	_options.clear()
	_palettes.clear()
	_presets.clear()
	_read_unlocks()
	for slot_name: String in _data["slots"]:
		var slot := StringName(slot_name)
		_slots.append(slot)
		var list: Array[Dictionary] = []
		var parts: Dictionary = _data["slots"][slot_name]["parts"]
		for id: String in parts:
			var gate: Dictionary = _part_gates.get("%s/%s" % [slot_name, id], {})
			var entry: Dictionary = parts[id]
			(
				list
				. append(
					{
						"id": StringName(id),
						"label": entry["label"],
						"label_female": entry.get("label_female", entry["label"]),
						"body": StringName(entry.get("body", "")),
						"gate": gate,
					}
				)
			)
		_options[slot] = list
		_pending[slot] = _pending_of(slot, parts)
	for channel_name: String in _data["channels"]:
		var channel := StringName(channel_name)
		_channels.append(channel)
		var source: String = _data["channels"][channel_name]
		var colours: Array = _data["palettes"][source]
		var names: Array = _data["palette_names"][source]
		var entries: Array[Dictionary] = []
		for i in colours.size():
			var gate: Dictionary = _palette_gates.get("%s/%d" % [channel_name, i], {})
			(
				entries
				. append(
					{
						"id": StringName(String(names[i]).replace(" ", "_")),
						"label": String(names[i]).capitalize(),
						"colour": Color.html(colours[i]),
						"gate": gate,
					}
				)
			)
		_palettes[channel] = entries
	for source: Dictionary in _data["presets"]:
		var parts := {}
		for slot_name: String in source["parts"]:
			parts[StringName(slot_name)] = StringName(source["parts"][slot_name])
		var colours := {}
		for channel_name: String in source["colours"]:
			colours[StringName(channel_name)] = int(source["colours"][channel_name])
		(
			_presets
			. append(
				{
					"id": StringName(source["id"]),
					"name": source["name"],
					"parts": parts,
					"colours": colours,
				}
			)
		)


## Reads the ladder (`unlocks.json`: one row `{level, slot, item, available}` per reward, shared
## with the level popups and the maps) into the two gate tables. A wearable's row carries `part`,
## its catalogue key ("torso/rolled"), and a `label` when the art is not drawn; a `colour` row's
## `item` is a name of the cloth palette. Every other row is not the wardrobe's.
static func _read_unlocks() -> void:
	_part_gates.clear()
	_palette_gates.clear()
	_pending.clear()
	_ladder_parts.clear()
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(UNLOCKS_PATH)) != OK:
		push_error("LookCatalog: cannot read %s" % UNLOCKS_PATH)
		return
	for row: Dictionary in json.data:
		var level := int(row["level"])
		if row["slot"] == "colour":
			_read_colour_row(String(row["item"]), level)
		elif row.has("part"):
			var key := String(row["part"])
			if level > 1:
				_part_gates[key] = {"level": level}
			(
				_ladder_parts
				. append(
					{
						"slot": StringName(key.get_slice("/", 0)),
						"id": StringName(key.get_slice("/", 1)),
						"level": level,
						"label": row.get("label", ""),
					}
				)
			)


## A colour of the cloth palette that a level opens, on each of the channels that use the palette.
static func _read_colour_row(item: String, level: int) -> void:
	if level <= 1:
		return
	for channel_name: String in _data["channels"]:
		var source: String = _data["channels"][channel_name]
		if source != CLOTH:
			continue
		var at: int = (_data["palette_names"][source] as Array).find(item.replace("_", " "))
		if at >= 0:
			_palette_gates["%s/%d" % [channel_name, at]] = {"level": level}


## The ladder's wearables of `slot` that `parts` (the slot's entries of `parts.json`) lacks.
static func _pending_of(slot: StringName, parts: Dictionary) -> Array:
	var out: Array = []
	for entry: Dictionary in _ladder_parts:
		if StringName(entry["slot"]) != slot or parts.has(entry["id"]):
			continue
		var label: String = (
			entry["label"] if entry["label"] != "" else String(entry["id"]).capitalize()
		)
		(
			out
			. append(
				{
					"id": StringName(entry["id"]),
					"label": label,
					"label_female": label,
					"gate": {"level": int(entry["level"])},
				}
			)
		)
	return out
