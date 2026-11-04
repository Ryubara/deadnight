class_name CharacterLook
extends RefCounted
## How one character looks: a part option for each part slot and a palette index for each colour
## slot (`LookCatalog`). Plain data with three forms: a Dictionary for saving (readable ids, so a
## catalogue that grows never breaks a save), a short byte string for the wire (indices), and the
## object itself.
##
## Whatever arrives from outside (a save file, a packet from another player) is untrusted:
## `from_dict` and `from_bytes` never fail on a bad entry, they put that slot back to its first
## option.

## Bump when the catalogue stops being append-only or a slot is added (2: the character's `body`
## slot, #678; 3: the `mouth` slot, #1061).
const VERSION := 3
## The oldest look `from_bytes` still reads. A look of an older version lacks the slots added since
## (`SLOT_SINCE`), which take their first option.
const OLDEST_VERSION := 2
## The version that added a slot, for the slots added after `OLDEST_VERSION`.
const SLOT_SINCE := {&"mouth": 3}
## Part option id by part slot.
var parts: Dictionary = {}
## Palette index by colour slot.
var colours: Dictionary = {}
## How far the torso colour was moved to tell this player from an identical look (see
## `LookResolver`). Never saved or sent.
var shift := 0


## Bytes on the wire: the version, then one byte per part slot and per colour slot.
static func wire_size(version := VERSION) -> int:
	return 1 + wire_slots(version).size() + LookCatalog.colour_slots().size()


## The part slots a look of `version` carries, in wire order.
static func wire_slots(version: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for slot in LookCatalog.part_slots():
		if int(SLOT_SINCE.get(slot, OLDEST_VERSION)) <= version:
			out.append(slot)
	return out


## Whether `size` bytes can be a look of a version this build reads.
static func fits_wire(size: int) -> bool:
	for version in range(OLDEST_VERSION, VERSION + 1):
		if size == wire_size(version):
			return true
	return false


func _init() -> void:
	for slot in LookCatalog.part_slots():
		parts[slot] = LookCatalog.options(slot)[0]["id"]
	for slot in LookCatalog.colour_slots():
		colours[slot] = 0


static func from_preset(index: int) -> CharacterLook:
	var look := CharacterLook.new()
	var preset: Dictionary = LookCatalog.presets()[posmod(index, LookCatalog.presets().size())]
	for slot: StringName in preset["parts"]:
		if LookCatalog.option_index(slot, preset["parts"][slot]) >= 0:
			look.parts[slot] = preset["parts"][slot]
	for slot: StringName in preset["colours"]:
		look.colours[slot] = preset["colours"][slot]
	return look


## The look of a player who has picked nothing: the first preset.
static func default_look() -> CharacterLook:
	return from_preset(0)


## A random look from the free options only, so it can always be saved. `rng` makes it repeatable.
## With a `body` the character is that one and the hair one of its cuts; without, either.
static func randomized(
	rng: RandomNumberGenerator, unlocks: LookUnlocks = null, body: StringName = &""
) -> CharacterLook:
	var look := CharacterLook.new()
	var open := unlocks if unlocks != null else LookUnlocks.new()
	for slot in LookCatalog.part_slots():
		var choices: Array = []
		for option: Dictionary in LookCatalog.options(slot):
			if body != &"" and slot == LookCatalog.BODY_SLOT and option["id"] != body:
				continue
			if body != &"" and slot == &"hair" and option["body"] not in [&"", body]:
				continue
			if open.is_unlocked(slot, option["id"], option["gate"]):
				choices.append(option["id"])
		look.parts[slot] = choices[rng.randi_range(0, choices.size() - 1)]
	for slot in LookCatalog.colour_slots():
		var choices: Array = []
		var palette := LookCatalog.palette(slot)
		for i in palette.size():
			if open.is_unlocked(slot, palette[i]["id"], palette[i]["gate"]):
				choices.append(i)
		look.colours[slot] = choices[rng.randi_range(0, choices.size() - 1)]
	return look


func duplicate_look() -> CharacterLook:
	var copy := CharacterLook.new()
	copy.parts = parts.duplicate()
	copy.colours = colours.duplicate()
	copy.shift = shift
	return copy


## A string that is equal for equal looks.
func key() -> String:
	return to_bytes().hex_encode()


func equals(other: CharacterLook) -> bool:
	return other != null and key() == other.key()


## The character: `LookCatalog.MALE` or `LookCatalog.FEMALE`.
func body() -> StringName:
	return parts.get(LookCatalog.BODY_SLOT, LookCatalog.MALE)


## Makes this look `body`'s. A hair cut of the other character's is swapped for this one's own
## (crew cut for him, bob for her); every other part fits both and stays.
func set_body(value: StringName) -> void:
	if LookCatalog.option_index(LookCatalog.BODY_SLOT, value) < 0 or value == body():
		return
	parts[LookCatalog.BODY_SLOT] = value
	var cut := LookCatalog.hair_body(parts[&"hair"])
	if cut != &"" and cut != value:
		parts[&"hair"] = LookCatalog.body_hair(value)


## The palette entry of `slot` that this look uses.
func colour(slot: StringName) -> Color:
	return LookCatalog.palette(slot)[colours[slot]]["colour"]


## Moves the colour of `slot` by `steps` places in its palette, wrapping.
func shift_colour(slot: StringName, steps: int) -> void:
	colours[slot] = posmod(int(colours[slot]) + steps, LookCatalog.palette(slot).size())


## A copy with every option this player has not unlocked put back to the slot's first option.
func without_locked(unlocks: LookUnlocks) -> CharacterLook:
	var out := duplicate_look()
	for slot in LookCatalog.part_slots():
		var index := LookCatalog.option_index(slot, parts[slot])
		var option: Dictionary = LookCatalog.options(slot)[index]
		if not unlocks.is_unlocked(slot, option["id"], option["gate"]):
			out.parts[slot] = LookCatalog.options(slot)[0]["id"]
	for slot in LookCatalog.colour_slots():
		var entry: Dictionary = LookCatalog.palette(slot)[colours[slot]]
		if not unlocks.is_unlocked(slot, entry["id"], entry["gate"]):
			out.colours[slot] = 0
	return out


# --- saving ------------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var named_parts := {}
	for slot in LookCatalog.part_slots():
		named_parts[String(slot)] = String(parts[slot])
	var named_colours := {}
	for slot in LookCatalog.colour_slots():
		named_colours[String(slot)] = String(LookCatalog.palette(slot)[colours[slot]]["id"])
	return {"version": VERSION, "parts": named_parts, "colours": named_colours}


## Reads a saved look. Anything missing or unknown becomes the slot's first option; a wrong type
## anywhere yields the default look.
static func from_dict(data: Variant) -> CharacterLook:
	var look := CharacterLook.new()
	if typeof(data) != TYPE_DICTIONARY:
		return look
	var saved_parts: Variant = data.get("parts", {})
	var saved_colours: Variant = data.get("colours", {})
	if typeof(saved_parts) == TYPE_DICTIONARY:
		for slot in LookCatalog.part_slots():
			var id := StringName(str(saved_parts.get(String(slot), "")))
			if LookCatalog.option_index(slot, id) >= 0:
				look.parts[slot] = id
	if typeof(saved_colours) == TYPE_DICTIONARY:
		for slot in LookCatalog.colour_slots():
			var id := StringName(str(saved_colours.get(String(slot), "")))
			var palette := LookCatalog.palette(slot)
			for i in palette.size():
				if palette[i]["id"] == id:
					look.colours[slot] = i
	return look


## The look as `SoldierLook` takes it: `{parts: {slot: id}, colours: {channel: index}}`.
func to_soldier_look() -> Dictionary:
	var named_parts := {}
	for slot in LookCatalog.part_slots():
		named_parts[String(slot)] = String(parts[slot])
	var indices := {}
	for slot in LookCatalog.colour_slots():
		indices[String(slot)] = int(colours[slot])
	return {"parts": named_parts, "colours": indices}


func to_json() -> String:
	return JSON.stringify(to_dict())


static func from_json(text: String) -> CharacterLook:
	# `JSON.new().parse` reports a bad text through its return value; `parse_string` would log an
	# engine error for every damaged save file.
	var json := JSON.new()
	if text == "" or json.parse(text) != OK:
		return CharacterLook.new()
	return from_dict(json.data)


# --- the wire ----------------------------------------------------------------------------------


## `VERSION`, then the option index of each part slot, then the palette index of each colour slot.
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.append(VERSION)
	for slot in LookCatalog.part_slots():
		out.append(LookCatalog.option_index(slot, parts[slot]))
	for slot in LookCatalog.colour_slots():
		out.append(int(colours[slot]))
	return out


## Reads a look from the wire. Returns null when the bytes are not a look of a version this build
## reads (the caller falls back to the default); an index that is out of range becomes the first
## option, and so does a slot the look's version did not have yet.
static func from_bytes(data: PackedByteArray) -> CharacterLook:
	if data.is_empty() or data[0] < OLDEST_VERSION or data[0] > VERSION:
		return null
	if data.size() != wire_size(data[0]):
		return null
	var look := CharacterLook.new()
	var at := 1
	for slot in wire_slots(data[0]):
		var list := LookCatalog.options(slot)
		if data[at] < list.size():
			look.parts[slot] = list[data[at]]["id"]
		at += 1
	for slot in LookCatalog.colour_slots():
		if data[at] < LookCatalog.palette(slot).size():
			look.colours[slot] = data[at]
		at += 1
	return look
