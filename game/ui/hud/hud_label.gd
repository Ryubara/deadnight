class_name HudLabel
extends Label
## A HUD label whose dark outline and shadow cost two draw calls, not four (#948).
##
## A `Label` with an outline and a shadow draws four runs of glyphs: the shadow of the outline, the
## shadow of the letters, the outline, the letters. The outline's glyphs and the letters' glyphs are
## on different textures, so the four runs alternate and each is a draw call of its own. Here the
## label draws the outline itself, in a canvas item behind its own, and leaves the engine to draw
## the shadow and the letters (one texture: one call). The shadow of the outline is not drawn at
## all: it is a quarter-pixel rim at the shadow's alpha, under an outline that covers it, and the
## picture differs from the engine's by at most one level of 255 in a few pixels (the order the
## black runs are blended in).
##
## The halo is set by `halo_size` and `halo_colour` (not the theme's `outline_size`, which stays 0
## for the engine); the shadow is the theme's own (`font_shadow_color`, `shadow_offset_x`,
## `shadow_offset_y`), which the engine draws.

## The outline's width and colour; 0 for none.
var halo_size := 0:
	set(value):
		if value != halo_size:
			halo_size = value
			queue_redraw()
var halo_colour := Color.BLACK:
	set(value):
		if value != halo_colour:
			halo_colour = value
			queue_redraw()

var _line := TextLine.new()
var _paragraph := TextParagraph.new()
## The label's `self_modulate` alpha as `set_enter_alpha` last set it: a canvas item's own modulate
## does not reach its children, so the outline's item is given it too.
var _enter_alpha := 1.0
## The canvas item behind the label's own that holds the outline.
var _halo := RID()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _halo.is_valid():
		RenderingServer.free_rid(_halo)
		_halo = RID()


func _draw() -> void:
	if not _halo.is_valid():
		_halo = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_halo, get_canvas_item())
		RenderingServer.canvas_item_set_draw_behind_parent(_halo, true)
		RenderingServer.canvas_item_set_self_modulate(_halo, Color(1.0, 1.0, 1.0, _enter_alpha))
	RenderingServer.canvas_item_clear(_halo)
	if halo_size <= 0 or halo_colour.a <= 0.0 or text.is_empty():
		return
	if autowrap_mode != TextServer.AUTOWRAP_OFF:
		_draw_wrapped()
		return
	# The same box the engine sets the line in: the line height with the theme's spacing, the line
	# centred in it.
	_line.clear()
	_line.add_string(text, get_theme_font(&"font"), get_theme_font_size(&"font_size"))
	_line.width = size.x
	_line.alignment = horizontal_alignment
	_line.text_overrun_behavior = text_overrun_behavior
	var block := float(get_line_height())
	var at := Vector2(0.0, _top(block) + (block - _line.get_size().y) * 0.5)
	_line.draw_outline(_halo, at, halo_size, halo_colour)


## The outline of wrapped lines, on the engine's own breaks (`TextParagraph`).
func _draw_wrapped() -> void:
	_paragraph.clear()
	_paragraph.add_string(text, get_theme_font(&"font"), get_theme_font_size(&"font_size"))
	_paragraph.width = size.x
	_paragraph.alignment = horizontal_alignment
	_paragraph.break_flags = _break_flags()
	# The engine sets each line in a box of the font's height, the theme's spacing between the boxes,
	# and centres the shaped line in its box: the paragraph's own lines are shorter than the box.
	var box := float(get_line_height())
	var line := _paragraph.get_line_size(0).y
	_paragraph.line_spacing = box + float(get_theme_constant(&"line_spacing")) - line
	_paragraph.draw_outline(_halo, Vector2(0.0, (box - line) * 0.5), halo_size, halo_colour)


func _break_flags() -> int:
	var flags := TextServer.BREAK_MANDATORY
	match autowrap_mode:
		TextServer.AUTOWRAP_ARBITRARY:
			flags |= TextServer.BREAK_GRAPHEME_BOUND
		TextServer.AUTOWRAP_WORD:
			flags |= TextServer.BREAK_WORD_BOUND
		_:
			flags |= TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	return flags


## Fades the label in or out by its own `self_modulate` (the way a row stack fades its rows, which
## leaves `modulate` to the feed): the letters, the shadow and the outline.
func set_enter_alpha(alpha: float) -> void:
	self_modulate.a = alpha
	_enter_alpha = alpha
	if _halo.is_valid():
		RenderingServer.canvas_item_set_self_modulate(_halo, Color(1.0, 1.0, 1.0, alpha))


## Lets the label wrap its words: its outline follows the engine's breaks.
func wrap_words(mode: TextServer.AutowrapMode) -> void:
	autowrap_mode = mode
	queue_redraw()


## Where the line's top sits for the vertical alignment.
func _top(line_height: float) -> float:
	match vertical_alignment:
		VERTICAL_ALIGNMENT_CENTER:
			return floorf((size.y - line_height) * 0.5)
		VERTICAL_ALIGNMENT_BOTTOM:
			return size.y - line_height
	return 0.0
