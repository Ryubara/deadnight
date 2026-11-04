class_name LevelTag
extends RefCounted
## Where a player's level and icon sit beside their name, everywhere the game shows both: over a
## head (`HudMarkers`), the bottom-left player boxes (`HudPlayerBox`), the scoreboard and the night
## report (`HudLevelCell`) and the lobby's seat list. One order and two gaps, kept here so that no
## place drifts from the others (docs/design/progression.md#the-level-over-a-head):
##
##     [icon] [level] [name]
##          ^      ^
##     ICON_GAP    NAME_GAP
##
## The icon and the level are one badge, close together; the name follows after the larger gap. A
## row with no level (a bot, a seat whose ticket had none, levels turned off) is the name alone: no
## badge and no gap, the name starts where a name always started.

## The icon's side, from the 64 px atlas (`LevelIcons`).
const ICON := 24.0
## Between the icon and the level: tight.
const ICON_GAP := 4.0
## Between the level and the name: visibly larger.
const NAME_GAP := 12.0
## A list keeps room for a level of two digits (the ladder ends at 55), so the names of its rows
## start on one line and no level is cut.
const DIGITS := "0123456789"


## How wide the level's room is in `font` at `size_px`: the widest two digits.
static func level_room(font: Font, size_px: int) -> float:
	var widest := 0.0
	for digit in DIGITS:
		var pair: String = digit + digit
		widest = maxf(widest, font.get_string_size(pair, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
	return ceilf(widest)


## The icon and the level together, `level_width` wide for the level.
static func badge_width(level_width: float) -> float:
	return ICON + ICON_GAP + level_width


## What the badge and the gap before the name take from a line, when there is a level.
static func taken(level_width: float) -> float:
	return badge_width(level_width) + NAME_GAP


## A `TextureRect` for the icon of `icon_level`, the size of the badge's icon.
static func icon_rect(icon_level: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = LevelIcons.FILTER
	icon.custom_minimum_size = Vector2.ONE * ICON
	set_icon(icon, icon_level)
	return icon


static func set_icon(icon: TextureRect, icon_level: int) -> void:
	icon.texture = LevelIcons.texture(icon_level)
