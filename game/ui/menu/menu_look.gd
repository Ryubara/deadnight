class_name MenuLook
extends RefCounted
## How the menu's panels look: the colours, the type and the small drawn parts (the film-frame
## strip, the amber focus bar, the hairlines). Every panel builds its controls through here, so the
## look of the whole menu is decided in one file. Colours that exist as tokens come from the
## active `UITokens`; the few the menu adds are named here.
##
## The type sizes are in design units (the 1920 x 1080 canvas). They are also the floors for a
## phone: at 844 x 390 with the phone factor (`MenuScale`) one unit is 0.72 px, so a caption of
## 22 is 15.8 px and a body of 26 is 18.7 px, over the written minimums of 14 and 18.

const SIZE_CAPTION := 22
const SIZE_BODY := 26
const SIZE_TITLE := 32
const SIZE_ITEM := 46
const SIZE_TAB := 34
const SIZE_NUMBER := 28
## The least height of anything that can be pressed, in units: 44 real pixels on a phone (a unit
## is 0.72 px there).
const TAP_TARGET := 62.0
## Letter spacing of the wide face, in pixels.
const TRACKING := 2

## Text on the dark of the stage.
const INK := Color("f4ead2")
const MUTED := Color("b6a98f")
const AMBER := Color("ffb347")
const HAIRLINE := Color(1.0, 1.0, 1.0, 0.16)
const BOARD := Color(0.04, 0.035, 0.06, 0.8)
## The paper of a ticket and the program, its shaded edge, its ink, and its one accent.
const PAPER := Color("efe4cb")
const PAPER_SHADE := Color("d8cba9")
const PAPER_INK := Color("1c1612")
const PAPER_MUTED := Color("5c5144")
const PAPER_RULE := Color("c9bc9a")
const RED := Color("d6392f")
## The hole of a punched mark: the dark of the night behind the paper.
const HOLE := Color(0.07, 0.05, 0.08)
## The darkening behind a panel, at its strongest edge.
const SCRIM := Color(0.02, 0.015, 0.04, 0.78)

static var _wide: FontVariation


## The wide-tracked text face (small caps lines, tab names).
static func wide_font() -> Font:
	if _wide == null:
		_wide = FontVariation.new()
		_wide.base_font = UITokens.active().font_text
		_wide.spacing_glyph = TRACKING
	return _wide


## A label in the menu's type: the text face, the wide face, or the display face.
static func label(
	text: String, size: int, color := INK, face := &"text", align := HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var node := Label.new()
	node.text = text
	node.horizontal_alignment = align
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", color)
	var tokens := UITokens.active()
	var font: Font = tokens.font_text
	if face == &"wide":
		font = wide_font()
	elif face == &"display":
		font = tokens.font_display
	node.add_theme_font_override(&"font", font)
	return node


## A one-pixel rule.
static func hairline(color := HAIRLINE) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## A column's heading: the display face, a rule under it, and a small note at the right.
## `on_paper` draws it in ink for a heading on a sheet.
static func heading(title: String, note := "", note_color := MUTED, on_paper := false) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	var line := HBoxContainer.new()
	box.add_child(line)
	var name_label := label(title, SIZE_TITLE, PAPER_INK if on_paper else INK, &"display")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	if note != "":
		var side := label(
			note.to_upper(), SIZE_CAPTION, note_color, &"wide", HORIZONTAL_ALIGNMENT_RIGHT
		)
		side.size_flags_vertical = Control.SIZE_SHRINK_END
		line.add_child(side)
	box.add_child(hairline(PAPER_RULE if on_paper else Color(1.0, 1.0, 1.0, 0.3)))
	return box


## Draws a ticket into `item`: paper with a half-round notch cut into each side, a shaded foot,
## and (at `perf_x` above 0) a line of perforation. The notches are cut out of the polygon, so the
## stage shows through them.
static func draw_ticket(
	item: CanvasItem, size: Vector2, paper: Color, shade: Color, notch: float, perf_x := -1.0
) -> void:
	var body := PackedVector2Array()
	var middle := size.y * 0.5
	body.append(Vector2(0.0, 0.0))
	body.append(Vector2(size.x, 0.0))
	if notch > 0.0:
		body.append(Vector2(size.x, middle - notch))
		for step in range(1, 12):
			var angle := PI * step / 12.0
			body.append(Vector2(size.x - sin(angle) * notch, middle - cos(angle) * notch))
		body.append(Vector2(size.x, middle + notch))
	body.append(Vector2(size.x, size.y))
	body.append(Vector2(0.0, size.y))
	if notch > 0.0:
		body.append(Vector2(0.0, middle + notch))
		for step in range(1, 12):
			var angle := PI * step / 12.0
			body.append(Vector2(sin(angle) * notch, middle + cos(angle) * notch))
		body.append(Vector2(0.0, middle - notch))
	item.draw_colored_polygon(body, paper)
	item.draw_rect(Rect2(0.0, size.y - 4.0, size.x, 4.0), shade)
	if perf_x > 0.0:
		var y := 12.0
		while y < size.y - 10.0:
			item.draw_circle(Vector2(perf_x, y), 1.8, shade.darkened(0.25))
			y += 9.0


## Paper that is only a surface: a panel of a ticket's paper behind other controls.
class Paper:
	extends Control
	var notch := 0.0
	var perf_x := -1.0
	var paper := MenuLook.PAPER
	var shade := MenuLook.PAPER_SHADE

	func _init(notch_radius := 0.0) -> void:
		notch = notch_radius
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		MenuLook.draw_ticket(self, size, paper, shade, notch, perf_x)


## The punch card: `total` marks of which the first `have` are punched through (the night shows
## in the hole). Each is a tenth of the goal, rounded.
class Punches:
	extends Control
	const CELL := 26.0
	var total := 10
	var have := 0

	func _init(cells := 10, punched := 0) -> void:
		total = cells
		have = punched
		custom_minimum_size = Vector2(CELL * cells, 22.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for index in total:
			var at := Vector2(CELL * 0.5 + index * CELL, size.y * 0.5)
			if index < have:
				draw_circle(at, CELL * 0.34, MenuLook.HOLE)
				draw_arc(at, CELL * 0.34, 0.0, TAU, 24, MenuLook.PAPER_INK, 1.5, true)
			else:
				draw_circle(at, CELL * 0.34, MenuLook.PAPER_SHADE.darkened(0.04))
				draw_arc(at, CELL * 0.34, 0.0, TAU, 24, MenuLook.PAPER_RULE, 1.5, true)


## The ring that fills clockwise: the way to the next Billing level.
class Ring:
	extends Control
	var fraction := 0.0
	var thickness := 5.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var centre := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - thickness
		draw_arc(centre, radius, 0.0, TAU, 48, MenuLook.PAPER_SHADE, thickness, true)
		draw_arc(
			centre,
			radius,
			-PI * 0.5,
			-PI * 0.5 + TAU * clampf(fraction, 0.0, 1.0),
			48,
			MenuLook.RED,
			thickness,
			true
		)


## The punch card for a fraction of a goal.
static func punches(have: int, need: int) -> Punches:
	var punched := 10 if need <= 0 else roundi(10.0 * float(have) / float(need))
	return Punches.new(10, clampi(punched, 0, 10))
