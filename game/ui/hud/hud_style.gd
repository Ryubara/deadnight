class_name HudStyle
extends RefCounted
## Shared drawing and type helpers for the HUD parts, so every part reads the tokens the same way.
## Sizes are canvas units (the project stretches the canvas to 1920 x 1080 and up), taken from
## the token type scale where there is a matching step.

## The HUD's scale against the first draft (#218 scaled it down): every length below is the old
## one times this, so the whole HUD is retuned by one number. Type is scaled less, so it stays
## readable: its floor is `MIN_TEXT`.
const UNIT := 0.75
## Type sizes in canvas units. `NUMERAL` and `BIG` are for the display face; the rest for text.
const NUMERAL := 84
const BIG := 64
## Your points in the player's container; a teammate's use `MEDIUM`.
const POINTS := 44
const MEDIUM := 32
const TEXT := 24
const SMALL := 20
## The smallest text the HUD draws, canvas units: 13 px at 720p, 20 px at 1080p.
const MIN_TEXT := 20
## Spacing steps, in canvas units (the tokens' steps times `UNIT`): a part's own padding and the
## gaps between rows, so everything sits on the same few distances.
const XS := 3
const SM := 6
const MD := 12
const LG := 18
## Screen margin: the gap between a corner card and the screen's edge, and between HUD parts.
const MARGIN := 36
const GAP := SM
## Hard shadow offset of a ticket, canvas units.
const SHADOW := Vector2(4.0, 4.0)
## Corner cut of a ticket, and the width of the accent stripe down its left side.
const NOTCH := 10.0
const STRIPE := 4.0
## A ticket's padding: the text starts `PAD_LEFT` from the card's left edge and ends `PAD` from its
## right edge, so every card's content shares two vertical lines (the text grid).
const PAD := MD
const PAD_LEFT := MD + 8
const TRACK_CAPTION := 2.0
## The longest display name the HUD shows, in characters: the state keeps no more, and a name that
## is still too wide for its place is ellipsized there.
const NAME_LIMIT := 20
## Width of the columns at the screen's sides (round, objective, the players, the generator and the
## lists), and of the cards in the middle (banner, prompt). On the smallest canvas (1536 x 864) the
## three leave a gap between them; a part never grows past its width, it shrinks or ellipsizes.
const COLUMN := 316.0
const CARD := 420.0
## Dark outline round every letter, so text holds on a lit ground at night.
const OUTLINE := 3


## A label in the display face (big numbers, banners) or the text face, upper case by habit.
static func label(
	text: String, size: int, colour: Color, display := false, tracking := 0.0
) -> Label:
	var tokens := UITokens.active()
	var node := HudLabel.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := (
		tokens.display_font(tokens.embolden_display * 0.5, tracking)
		if display
		else tokens.text_font(tokens.embolden_display * 0.3, tracking)
	)
	node.add_theme_font_override(&"font", font)
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", colour)
	node.add_theme_color_override(&"font_shadow_color", tokens.shadow)
	# The outline is the label's own (two draw calls for the outline and the shadow, `HudLabel`).
	node.halo_colour = Color(0.0, 0.0, 0.0, 0.7)
	node.halo_size = OUTLINE
	node.add_theme_constant_override(&"shadow_offset_x", 0)
	node.add_theme_constant_override(&"shadow_offset_y", maxi(2, int(size * 0.05)))
	return node


## Makes a label take no more width than it is given: a long text ends in an ellipsis instead of
## widening the part (a label's minimum width is its text unless it may trim).
static func clip(node: Label) -> Label:
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.clip_text = true
	return node


## Lets a label wrap onto more lines instead of ending in an ellipsis: for text that must be read in
## full and whose card may grow in height (a prompt). Fill it with `set_wrapped`. The lines sit with
## no extra gap, so the height `set_wrapped` reserves is the label's own.
static func wrap(node: Label) -> Label:
	(node as HudLabel).wrap_words(TextServer.AUTOWRAP_WORD_SMART)
	node.add_theme_constant_override(&"line_spacing", 0)
	return node


## How wide `text` is at `size_px` in `font`.
static func text_width(font: Font, text: String, size_px: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x


## The largest size from `wanted` down to `floor_size` at which `text` is at most `width` wide.
static func fit_size(
	font: Font, text: String, wanted: int, width: float, floor_size := MIN_TEXT
) -> int:
	var size_px := wanted
	var natural := text_width(font, text, size_px)
	if natural <= width or wanted <= floor_size:
		return wanted
	# Start from the proportional guess (shaping a string at each size is the cost), then step down
	# until it really fits: letter spacing does not scale exactly.
	size_px = clampi(int(float(wanted) * width / natural), floor_size, wanted)
	while size_px > floor_size and text_width(font, text, size_px) > width:
		size_px -= 2
	return size_px


## Writes `text` into `node` (a label made by `label`), shrinking the type from `wanted` toward
## `floor_size` until it fits `width` and ellipsizing what still does not. For numbers and names
## that must stay on one line.
static func set_fitted(
	node: Label, text: String, wanted: int, width: float, floor_size := MIN_TEXT
) -> void:
	var size_px := fit_size(node.get_theme_font(&"font"), text, wanted, width, floor_size)
	if node.get_theme_font_size(&"font_size") != size_px:
		node.add_theme_font_size_override(&"font_size", size_px)
	set_text(node, text)


## Writes `text` into a label made by `label` and `wrap`: the type shrinks from `wanted` toward
## `floor_size` while the text is wider than `width`, then what is still too wide wraps onto more
## lines, and the label reserves their height at once (a label learns its wrapped height a frame
## late). Nothing is cut.
static func set_wrapped(
	node: Label, text: String, wanted: int, width: float, floor_size := MIN_TEXT
) -> void:
	var font := node.get_theme_font(&"font")
	var size_px := fit_size(font, text, wanted, width, floor_size)
	if node.get_theme_font_size(&"font_size") != size_px:
		node.add_theme_font_size_override(&"font_size", size_px)
	set_text(node, text)
	var flags := (
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	)
	var block := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, -1, flags
	)
	node.custom_minimum_size.y = block.y


## `text` cut with an ellipsis to fit `width` at `size_px`: for a name that is followed by words
## that must survive ("RUBY  POINTS"), which a label's own ellipsis would cut.
static func trimmed(font: Font, text: String, size_px: int, width: float) -> String:
	if text_width(font, text, size_px) <= width:
		return text
	var cut := text.length()
	while cut > 1:
		cut -= 1
		var candidate := text.substr(0, cut).strip_edges() + "…"
		if text_width(font, candidate, size_px) <= width:
			return candidate
	return "…"


## Sets the text of a label made by `label` without touching its style.
static func set_text(node: Label, text: String) -> void:
	if node.text != text:
		node.text = text


static func margin() -> int:
	return MARGIN


## The outline of a ticket: a rectangle with its top-left and bottom-right corners cut.
static func ticket_points(rect: Rect2, notch := NOTCH) -> PackedVector2Array:
	var r := rect
	return PackedVector2Array(
		[
			r.position + Vector2(notch, 0.0),
			Vector2(r.end.x, r.position.y),
			r.end - Vector2(0.0, notch),
			r.end - Vector2(notch, 0.0),
			Vector2(r.position.x, r.end.y),
			r.position + Vector2(0.0, notch),
		]
	)


## Draws a flat ticket: a hard offset shadow, an opaque fill, a thin edge and a stripe of `accent`
## down its left side. No blur, no gradient (the style bible's paper-and-sign rule).
static func draw_ticket(item: CanvasItem, rect: Rect2, accent: Color, lit := 0.0) -> void:
	var shapes := HudShapes.new()
	add_ticket(shapes, rect, accent, lit)
	shapes.flush(item)


## The shapes of a ticket (`draw_ticket`) added to `shapes`, so a part can draw more in the same
## command (the banner's bulbs): one command for the four shapes, not four (`HudShapes`).
static func add_ticket(shapes: HudShapes, rect: Rect2, accent: Color, lit := 0.0) -> void:
	var tokens := UITokens.active()
	var outline := ticket_points(rect)
	var shadow := PackedVector2Array()
	for point in outline:
		shadow.append(point + SHADOW)
	shapes.polygon(shadow, tokens.shadow)
	shapes.polygon(outline, tokens.surface_raised.lerp(tokens.accent_bright, lit * 0.16))
	var closed := outline.duplicate()
	closed.append(outline[0])
	shapes.polyline(closed, tokens.outline.lightened(lit * 0.4), float(tokens.border))
	shapes.rect(
		Rect2(rect.position + Vector2(0.0, NOTCH), Vector2(STRIPE, rect.size.y - 2.0 * NOTCH)),
		accent
	)
