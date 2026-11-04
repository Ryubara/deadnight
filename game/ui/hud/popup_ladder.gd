class_name PopupLadder
extends RefCounted
## What the popup cards say about the ladder: the words of an unlocked item (its slot's caption,
## its name), the swatch beside it, the cue it sounds, and, for a level card, the next unlock and
## how far along the way to it the player is. The rows are `unlocks.json` (`LadderUnlocks`); only a
## row whose art is drawn (`available`) is ever announced, so the next unlock is the next of those.

## The punch holes of a level card: one more is punched the nearer the next unlock is.
const HOLES := 8

## Slot -> the caption of its card.
const CAPTIONS := {
	&"top": "NEW TOP",
	&"colour": "NEW COLOUR",
	&"headwear": "NEW HEADWEAR",
	&"trousers": "NEW TROUSERS",
	&"shoes": "NEW SHOES",
	&"eyewear": "NEW EYEWEAR",
	&"neck": "NEW NECKWEAR",
	&"map": "NEW MAP",
	&"calling_cards": "NEW CALLING CARDS",
	&"emblem": "NEW EMBLEM",
	&"tier_card": "NEW TIER CARD",
	&"tier_emblem": "NEW TIER EMBLEM",
	&"plate_frame": "NEW PLATE FRAME",
}
## The slots whose card is a card, an emblem or a frame of the plate (the unlock sound with a paper
## rustle): the rest are clothes, colours and maps.
const PLATE_SLOTS: Array[StringName] = [
	&"calling_cards", &"emblem", &"tier_card", &"tier_emblem", &"plate_frame"
]
## The names that are not their id read aloud.
const NAMES := {
	&"ushers_cap": "Usher's cap",
	&"ushers_jacket": "Usher's jacket",
	&"projectionists_visor": "Projectionist's visor",
	&"rolled_sleeves": "Rolled sleeves",
	&"press_lanyard": "Press lanyard",
}
## The cloth colours of the wardrobe (`parts.json`, `palettes.cloth`) as a swatch.
const COLOURS := {
	&"black": Color("1c1b1f"),
	&"cream": Color("e9dfc3"),
	&"grey": Color("8c8c8c"),
	&"charcoal": Color("3b3d42"),
	&"olive": Color("6b6b33"),
	&"green": Color("3f7a3a"),
	&"red": Color("c0392b"),
	&"cherry": Color("9c1c3a"),
	&"blue": Color("2f5fa8"),
	&"denim": Color("40608a"),
	&"mustard": Color("d1a21f"),
	&"gold": Color("e0b43a"),
	&"tan": Color("c5a572"),
	&"brown": Color("7a4a2b"),
	&"teal": Color("2a8c8c"),
	&"pink": Color("e58fb0"),
}
## The chip of an item that has no swatch (until the wardrobe has thumbnails): a plain dark chip
## with the first letter of its slot.
const CHIP_FALLBACK := Color("2b2740")


## The caption of the card an item earns (`NEW TOP`).
static func caption_of(slot: StringName) -> String:
	return CAPTIONS.get(slot, "NEW ITEM")


## An item's name as a person reads it: its id with spaces, a capital, and the few with an
## apostrophe as written.
static func name_of(item: StringName) -> String:
	if NAMES.has(item):
		return NAMES[item]
	var words := String(item).replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)


## The cue an unlock sounds: the rustle for a card, an emblem or a frame, the bell for the rest.
static func cue_of(slot: StringName) -> StringName:
	return &"card_earned" if PLATE_SLOTS.has(slot) else &"unlock"


## The swatch of a colour item, or null when the slot has no colour to show.
static func swatch_of(slot: StringName, item: StringName) -> Variant:
	if slot == &"colour" and COLOURS.has(item):
		return COLOURS[item]
	return null


## The letter on the chip of an item without a swatch.
static func chip_letter(slot: StringName) -> String:
	return String(slot).substr(0, 1).to_upper()


## The first row after `level` the player can be told about: `{level, slot, item}`, empty past the
## last one.
static func next_unlock(level: int, unlocks: LadderUnlocks = null) -> Dictionary:
	var table := unlocks if unlocks != null else LadderUnlocks.shipped()
	for at in table.levels():
		if at > level:
			var rows := table.earned_at(at)
			if not rows.is_empty():
				return rows[0]
	return {}


## Holes punched out of `HOLES` on the way to the next unlock: one more for every level nearer it,
## none when it is `HOLES` levels away or more, all of them on the last level (nothing is left to
## reach).
static func punched(level: int, unlocks: LadderUnlocks = null) -> int:
	var next := next_unlock(level, unlocks)
	if next.is_empty():
		return HOLES
	return HOLES - clampi(int(next["level"]) - level, 1, HOLES)
