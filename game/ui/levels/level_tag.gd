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
## The height of a digit when the font cannot say (a share of the font size).
const DIGIT_HEIGHT_SHARE := 0.7
## A list keeps room for a level of two digits (the ladder ends at 55), so the names of its rows
## start on one line and no level is cut.
const DIGITS := "0123456789"

## font id and size -> the digits' ink span (`digit_span`) or a line's baseline (`line_baseline`).
static var _digit_spans := {}


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


# --- Where the icon sits: on the digits, not on a box ---
#
# A level's digits and its icon are placed from a box each, and neither box is what is seen: the
# digits sit at their own height in the font's line (the line keeps room for a descender) and an
# icon's art has padding of its own in its cell (`LevelIcons.body_centre`: above the cell's middle,
# and by a different amount for each of its frames). So every place sets the icon from where the
# digits' ink is: its centre is the digits' centre. A place with the digits' baseline (drawn text, a
# box's labels) calls `icon_top` with `digits_centre`; a label that centres its line in a row calls
# `icon_top_in_row` (`icon_top_in_line` for one that starts at the top). The reasoning and the
# measurements: docs/research/level-badge-alignment.md.


## The rows the digits "0" to "9" cover in `font` at `size_px`, from the baseline (the top is
## negative: above it), read from the glyph outlines: the same for every place, and it follows the
## font, so a different face or size moves the icon with it. A font with no outlines to read
## (the engine's fallback in a test) gets `DIGIT_HEIGHT_SHARE` of the size.
static func digit_span(font: Font, size_px: int) -> Vector2:
	var rids := font.get_rids()
	if rids.is_empty():
		return Vector2(-DIGIT_HEIGHT_SHARE * size_px, 0.0)
	var key := "%d/%d" % [rids[0].get_id(), size_px]
	if _digit_spans.has(key):
		return _digit_spans[key]
	var server := TextServerManager.get_primary_interface()
	var top := 0.0
	var bottom := 0.0
	var seen := false
	for digit in DIGITS:
		var glyph := server.font_get_glyph_index(rids[0], size_px, digit.unicode_at(0), 0)
		var outline := server.font_get_glyph_contours(rids[0], size_px, glyph)
		for point: Vector3 in outline.get("points", PackedVector3Array()):
			# The outline's y is the screen's: negative above the baseline.
			top = minf(top, point.y) if seen else point.y
			bottom = maxf(bottom, point.y) if seen else point.y
			seen = true
	var span := Vector2(top, bottom) if seen else Vector2(-DIGIT_HEIGHT_SHARE * size_px, 0.0)
	_digit_spans[key] = span
	return span


## Where the digits' ink is centred, in the coordinate the `baseline` is in.
static func digits_centre(font: Font, size_px: int, baseline: float) -> float:
	var span := digit_span(font, size_px)
	return baseline + (span.x + span.y) * 0.5


## The top of the icon (`side` high: the badge's, or a bigger one) whose body is centred on
## `centre`, the y of the digits' centre.
static func icon_top(centre: float, icon_level: int, side := ICON) -> float:
	return centre - LevelIcons.body_centre(icon_level) * side


## Where the baseline of a label's line is, from the top of the line's block (the font's height:
## what a label centres in a row). The engine sets the shaped line in that block, centred, and the
## shaped line is not the font's height (a font's ascent counts its fallbacks, and an emboldened
## face is shorter than its box).
static func line_baseline(font: Font, size_px: int) -> float:
	var rids := font.get_rids()
	var key := "line/%d/%d" % [rids[0].get_id() if not rids.is_empty() else 0, size_px]
	if _digit_spans.has(key):
		return _digit_spans[key]
	var line := TextLine.new()
	line.add_string(DIGITS, font, size_px)
	var at := (font.get_height(size_px) - line.get_size().y) * 0.5 + line.get_line_ascent()
	_digit_spans[key] = at
	return at


## The top of the icon beside a label whose line block starts at `block_top` (a label that is
## top-aligned: `block_top` is 0; one that centres its line in a row: `icon_top_in_row`).
static func icon_top_in_line(
	block_top: float, font: Font, size_px: int, icon_level: int, side := ICON
) -> float:
	var centre := digits_centre(font, size_px, block_top + line_baseline(font, size_px))
	return icon_top(centre, icon_level, side)


## The top of the icon, in a row `row_height` high whose label centres its line.
static func icon_top_in_row(
	row_height: float, font: Font, size_px: int, icon_level: int, side := ICON
) -> float:
	# The engine puts the line at a whole unit: the half of an odd remainder is dropped.
	var block_top := floorf((row_height - font.get_height(size_px)) * 0.5)
	return icon_top_in_line(block_top, font, size_px, icon_level, side)


## Lets go of what was measured, for the end of a test run.
static func release() -> void:
	_digit_spans.clear()
