class_name HudStyle
extends RefCounted
## Shared drawing and type helpers for the HUD parts, so every part reads the tokens the same way.
## Sizes are canvas units (the project stretches the canvas to 1920 x 1080 and up), taken from
## the token type scale where there is a matching step.

## Type sizes in canvas units. `NUMERAL` and `BIG` are for the display face; the rest for text.
const NUMERAL := 120
const BIG := 84
## Points readout: big, but the bottom-left stack must leave room for the party above it.
const POINTS := 72
const MEDIUM := 44
const TEXT := 30
const SMALL := 24
## The smallest text the HUD draws, canvas units; at 720p it is still 16 px.
const MIN_TEXT := 24
## Screen margin and the gap between HUD parts, in token steps.
const MARGIN_STEPS := 1.2
## Hard shadow offset of a ticket, canvas units.
const SHADOW := Vector2(6.0, 6.0)
## Corner cut of a ticket.
const NOTCH := 14.0
const TRACK_CAPTION := 3.0
## Dark outline round every letter, so text holds on a lit ground at night.
const OUTLINE := 4


## A label in the display face (big numbers, banners) or the text face, upper case by habit.
static func label(
	text: String, size: int, colour: Color, display := false, tracking := 0.0
) -> Label:
	var tokens := UITokens.active()
	var node := Label.new()
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
	node.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	node.add_theme_constant_override(&"outline_size", OUTLINE)
	node.add_theme_constant_override(&"shadow_offset_x", 0)
	node.add_theme_constant_override(&"shadow_offset_y", maxi(2, int(size * 0.05)))
	return node


## Sets the text of a label made by `label` without touching its style.
static func set_text(node: Label, text: String) -> void:
	if node.text != text:
		node.text = text


static func margin() -> int:
	return int(UITokens.active().space_xl * MARGIN_STEPS)


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
	var tokens := UITokens.active()
	var outline := ticket_points(rect)
	var shadow := PackedVector2Array()
	for point in outline:
		shadow.append(point + SHADOW)
	item.draw_colored_polygon(shadow, tokens.shadow)
	item.draw_colored_polygon(outline, tokens.surface_raised.lerp(tokens.accent_bright, lit * 0.16))
	var closed := outline.duplicate()
	closed.append(outline[0])
	item.draw_polyline(closed, tokens.outline.lightened(lit * 0.4), float(tokens.border))
	item.draw_rect(
		Rect2(rect.position + Vector2(0.0, NOTCH), Vector2(6.0, rect.size.y - 2.0 * NOTCH)), accent
	)
