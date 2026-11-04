class_name PlateRow
extends RefCounted
## A player's calling card and emblem in a roster row (the scoreboard, the night report, the lobby's
## seats): the card is a chip behind the row's first cells (`CardArt.by_height`) under a dark veil
## so the row's light words keep their contrast; the emblem is a square after the name.

## The veil over the card in a row, the dark of the HUD.
const VEIL := 0.45
## The emblem's side as a share of the row's height.
const EMBLEM_SHARE := 0.62


## Puts the card `card` behind `holder`'s children, as its first child, `height` high. Nothing
## for no card. Returns the art, or null.
static func card_behind(holder: Control, card: StringName, height: float, ground: Color) -> CardArt:
	if card == &"":
		return null
	var art := CardArt.new()
	art.card_id = card
	art.by_height = true
	art.veil = Color(ground, VEIL)
	art.name = &"Card"
	art.custom_minimum_size = Vector2(0.0, height)
	holder.add_child(art)
	holder.move_child(art, 0)
	return art


## The emblem's side in a row `height` high.
static func emblem_side(height: float) -> float:
	return roundf(height * EMBLEM_SHARE)


## What an emblem takes from the line after a name: its side and a gap; nothing without one.
static func emblem_taken(emblem: StringName, height: float) -> float:
	return emblem_side(height) + float(HudStyle.SM) if emblem != &"" else 0.0


## An emblem control for a row `height` high, centred in a slot as high as the row.
static func emblem_slot(emblem: StringName, height: float) -> Control:
	var slot := CenterContainer.new()
	slot.name = &"EmblemSlot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(emblem_taken(emblem, height), height)
	var art := EmblemArt.make(emblem, emblem_side(height))
	art.name = &"Emblem"
	slot.add_child(art)
	return slot
