class_name Costumes
extends RefCounted
## The twelve presets as costumes (#1066): a whole look made of wearables, put on in one press,
## in the colours the costume comes with ("Default"). A costume is data on the preset
## (`parts.json`); nothing is saved about it: wearing one sets an ordinary look, and the look is
## told to wear a costume by its pieces (`of_look`).
##
## The pieces decide whether a costume is the player's: it is lit when every piece of it is
## (`LookUnlocks.owns_costume`), whatever level that takes. Its default colours need no colour
## unlock, but only as the set the costume has: `CharacterLook.without_locked` keeps the three
## cloth colours of an owned costume while the look wears all three, and puts a locked one back
## once the player changes another of them (own colours come from the palette they have).

## The part slots that make a costume what it is. Face, hair and mouth are the player's own and a
## costume does not decide them for the others.
const SLOTS: Array[StringName] = [
	&"body", &"headwear", &"torso", &"legs", &"feet", &"eyewear", &"neck", &"arm"
]
## The colours "Default" sets: the cloth. Skin and hair colour are the Body and Hair tabs'.
const COLOUR_CHANNELS: Array[StringName] = [&"primary", &"secondary", &"accent"]


static func count() -> int:
	return LookCatalog.presets().size()


static func id(index: int) -> StringName:
	return LookCatalog.presets()[index]["id"]


static func title(index: int) -> String:
	return LookCatalog.presets()[index]["name"]


## The look that wearing costume `index` sets: its pieces and its colours.
static func look(index: int) -> CharacterLook:
	return CharacterLook.from_preset(index)


## The pieces of costume `index` that a level or an order opens: `slot`, `id` and `gate`.
static func gated_pieces(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parts: Dictionary = LookCatalog.presets()[index]["parts"]
	for slot: StringName in parts:
		var at := LookCatalog.option_index(slot, parts[slot])
		if at < 0:
			continue
		var gate: Dictionary = LookCatalog.options(slot)[at]["gate"]
		if not gate.is_empty():
			out.append({"slot": slot, "id": parts[slot], "gate": gate})
	return out


## The level that opens the last piece of costume `index` (0 when every piece is a starting one).
static func level_needed(index: int) -> int:
	var level := 0
	for piece in gated_pieces(index):
		level = maxi(level, LookUnlocks.level_of(piece["gate"]))
	return level


## The colour that costume `index` has in `channel`, as a palette index.
static func colour_index(index: int, channel: StringName) -> int:
	return int(LookCatalog.presets()[index]["colours"].get(channel, 0))


## The costume `look` wears, or -1: the one whose pieces it wears (the face, the hair and the
## colours may be changed, and it is still the costume).
static func of_look(worn: CharacterLook) -> int:
	for index in count():
		var preset: Dictionary = LookCatalog.presets()[index]
		var matches := true
		for slot in SLOTS:
			if worn.parts[slot] != preset["parts"].get(slot, LookCatalog.options(slot)[0]["id"]):
				matches = false
				break
		if matches:
			return index
	return -1


## Whether `worn` has the default colours of the costume it wears.
static func has_default_colours(worn: CharacterLook, index: int) -> bool:
	for channel in COLOUR_CHANNELS:
		if int(worn.colours[channel]) != colour_index(index, channel):
			return false
	return true


## Puts the default colours of costume `index` on `worn`.
static func give_default_colours(worn: CharacterLook, index: int) -> void:
	for channel in COLOUR_CHANNELS:
		worn.colours[channel] = colour_index(index, channel)
