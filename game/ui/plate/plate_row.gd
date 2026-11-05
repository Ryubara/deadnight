class_name PlateRow
extends RefCounted
## A player's calling card, emblem and frame in a roster row (the scoreboard, the night report, the
## lobby's seats): the card is a chip behind the row's first cells (`CardArt.by_height`) under a
## dark veil so the row's light words keep their contrast; the emblem is a square after the name;
## the frame is a border round the whole row, over everything and inside its edge (`FrameArt`).

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


## Puts the frame `frame` round `holder`, as its last child (over the card and the row). Nothing for
## no frame. Returns the art, or null.
static func frame_over(holder: Control, frame: StringName) -> FrameArt:
	if frame == &"":
		return null
	var art := FrameArt.new()
	art.frame_id = frame
	art.name = &"Frame"
	holder.add_child(art)
	return art


## The room a frame takes at the right end of a row `height` high: the last cell gives it up and
## `clear_the_frame` keeps it empty, so the last numbers do not run into the border. Nothing for no
## frame.
static func frame_clear(frame: StringName, height: float) -> float:
	if frame == &"":
		return 0.0
	return ceilf(PlateFrames.width_for(height) * PlateFrames.THICKNESS) + 2.0


## Keeps `clear` free after the last cell of `row` (the room `frame_over`'s border takes). The row
## is as wide as it was: the last cell is that much narrower.
static func clear_the_frame(row: Control, clear: float) -> void:
	if clear <= 0.0:
		return
	var gap := Control.new()
	gap.name = &"FrameClear"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(clear, 0.0)
	row.add_child(gap)


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
