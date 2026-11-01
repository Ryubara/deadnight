class_name LookCatalog
extends RefCounted
## Every choice a player can make about how their character looks: the part options of each slot,
## the colours of each palette, and the eight presets. Plain data, no nodes.
##
## The data is a catalogue file in the schema of `parts.json` from the modular Soldier parts
## (docs/design/characters.md): slots with their parts, colour channels with their palettes, and
## presets. Until those parts land the file is `look_catalog.json`, a stand-in with the same
## slots, palettes and presets but only the parts the kit Soldier can show; then `CATALOG_PATH`
## points at the real `parts.json` and nothing else changes.
##
## The catalogue is append-only for a given `CharacterLook.VERSION`: the wire format sends a part
## as its index in its slot and a colour as its index in its palette, so entries are added at the
## end and never reordered or removed. A change that cannot follow that rule bumps the version.
## A slot with fewer than two parts is not shown on the customization screen.

const CATALOG_PATH := "res://gameplay/character/look_catalog.json"

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
}
## Screen titles of the colour channels.
const COLOUR_TITLES := {
	&"skin": "Skin",
	&"hair": "Hair colour",
	&"primary": "Main colour",
	&"secondary": "Second colour",
	&"accent": "Trim colour",
}

## The Soldier's materials that each colour channel tints (by material name in `soldier.glb`),
## for the stand-in assembly.
const MATERIAL_CHANNELS := {
	&"Skin": &"skin",
	&"Black": &"hair",
	&"Character_Main": &"primary",
	&"Pants": &"secondary",
	&"Grey": &"accent",
}

## The fixed armband colour of each seat in the lot. Never part of the look: a teammate stays
## readable in the dark whatever they wear.
const ARMBAND_COLOURS: Array[Color] = [
	Color("ff4b3e"), Color("38d6ff"), Color("ffe14a"), Color("9cff57")
]

## What a locked palette entry asks for, by "<channel>/<index>" (see `LookUnlocks` for the forms).
## Progression decides the real ones; no starting preset uses any of these.
const PALETTE_GATES := {
	"primary/11": {"billing": 10},
	"secondary/15": {"stubs": 400},
	"accent/14": {"stubs": 150},
}
## The same for parts, by "<slot>/<id>". None is locked yet.
const PART_GATES := {}

static var _data: Dictionary = {}
static var _slots: Array[StringName] = []
static var _channels: Array[StringName] = []
static var _options: Dictionary = {}
static var _palettes: Dictionary = {}
static var _presets: Array[Dictionary] = []


## The part slots, in wire order.
static func part_slots() -> Array[StringName]:
	_load()
	return _slots


## The colour channels, in wire order.
static func colour_slots() -> Array[StringName]:
	_load()
	return _channels


## The parts of `slot` in wire order: `id`, `label`, `gate`.
static func options(slot: StringName) -> Array:
	_load()
	return _options.get(slot, [])


## The colours of `channel` in wire order: `id`, `label`, `colour`, `gate`.
static func palette(channel: StringName) -> Array:
	_load()
	return _palettes.get(channel, [])


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


## The slots that give the player a real choice (two parts or more).
static func choosable_part_slots() -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in part_slots():
		if options(slot).size() > 1:
			out.append(slot)
	return out


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
	for slot_name: String in _data["slots"]:
		var slot := StringName(slot_name)
		_slots.append(slot)
		var list: Array[Dictionary] = []
		var parts: Dictionary = _data["slots"][slot_name]["parts"]
		for id: String in parts:
			var gate: Dictionary = PART_GATES.get("%s/%s" % [slot_name, id], {})
			list.append({"id": StringName(id), "label": parts[id]["label"], "gate": gate})
		_options[slot] = list
	for channel_name: String in _data["channels"]:
		var channel := StringName(channel_name)
		_channels.append(channel)
		var source: String = _data["channels"][channel_name]
		var colours: Array = _data["palettes"][source]
		var names: Array = _data["palette_names"][source]
		var entries: Array[Dictionary] = []
		for i in colours.size():
			var gate: Dictionary = PALETTE_GATES.get("%s/%d" % [channel_name, i], {})
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
