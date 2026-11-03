class_name TouchRotatePrompt
extends Control
## "Turn your phone": covers the game while a touch device is held upright. Deadnight is played
## sideways (the stick and the buttons need the width), and a web page cannot lock the orientation
## on every phone, so it asks. It shows only when the touch controls are wanted.

## The canvas layer it once sat on: above the router, below the film overlay (110). It now shares
## the router's layer, before the film (#883); the tours still give it a layer of its own.
const LAYER := 105
const TITLE := "TURN YOUR PHONE"
const NOTE := "Deadnight is played sideways."
const DIM := Color(0.02, 0.02, 0.04, 0.94)
const PHONE := Vector2(110.0, 190.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_refresh)
	get_viewport().size_changed.connect(_refresh)
	_refresh()


## True when it covers the screen: touch controls wanted and the canvas is taller than wide.
func showing() -> bool:
	return visible


func _refresh() -> void:
	var portrait := _canvas().y > _canvas().x
	visible = portrait and is_inside_tree() and TouchMode.wanted(get_tree())
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## This node's size, or the viewport's under a CanvasLayer.
func _canvas() -> Vector2:
	if size.x > 0.0 and size.y > 0.0:
		return size
	return get_viewport_rect().size


func _process(_delta: float) -> void:
	var portrait := _canvas().y > _canvas().x
	if visible != (portrait and TouchMode.wanted(get_tree())):
		_refresh()


func _draw() -> void:
	var canvas := _canvas()
	draw_rect(Rect2(Vector2.ZERO, canvas), DIM)
	var tokens := UITokens.active()
	var centre := canvas * 0.5 + Vector2(0.0, -canvas.y * 0.06)
	var unit := minf(canvas.x / 1080.0, 1.4)
	var phone := Rect2(centre - PHONE * unit * 0.5, PHONE * unit)
	draw_rect(phone, tokens.surface_raised)
	draw_rect(phone, tokens.ink, false, 5.0 * unit)
	draw_rect(
		Rect2(
			phone.position + phone.size * Vector2(0.4, 0.06),
			Vector2(phone.size.x * 0.2, 5.0 * unit)
		),
		tokens.ink
	)
	# The arrow that turns it a quarter, round the phone's right.
	var arrow_centre := centre
	var arrow_radius := PHONE.y * unit * 0.78
	draw_arc(arrow_centre, arrow_radius, -1.2, 0.2, 32, tokens.accent_bright, 8.0 * unit, true)
	var tip := arrow_centre + Vector2.from_angle(0.2) * arrow_radius
	var back := Vector2.from_angle(0.2 + PI * 0.5)
	draw_colored_polygon(
		PackedVector2Array(
			[
				tip + back * 28.0 * unit,
				tip - back * 28.0 * unit * 0.2 + Vector2(34.0, 10.0) * unit,
				tip - back * 36.0 * unit
			]
		),
		tokens.accent_bright
	)
	var font := tokens.display_font(tokens.embolden_display * 0.3)
	var title_px := int(64.0 * unit)
	var title_width := font.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, title_px).x
	var base := centre.y + PHONE.y * unit * 0.5 + 150.0 * unit
	draw_string(
		font,
		Vector2(centre.x - title_width * 0.5, base),
		TITLE,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		title_px,
		tokens.accent_bright
	)
	var note_px := int(34.0 * unit)
	var note_width := font.get_string_size(NOTE, HORIZONTAL_ALIGNMENT_LEFT, -1, note_px).x
	draw_string(
		font,
		Vector2(centre.x - note_width * 0.5, base + 64.0 * unit),
		NOTE,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		note_px,
		tokens.ink
	)
