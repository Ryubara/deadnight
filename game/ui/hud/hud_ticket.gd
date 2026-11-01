class_name HudTicket
extends HudPart
## A HUD part drawn as a ticket: notched flat paper with a hard shadow and an accent stripe. Its
## children go in `body`, a vertical box inside the padding.

@export var accent := Color("ffb347")
## 0 to 1: how lit the paper is (a pulse for a warning).
var lit := 0.0:
	set(value):
		lit = value
		queue_redraw()

var body := VBoxContainer.new()

var _pad := MarginContainer.new()


func _init() -> void:
	super()
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.add_theme_constant_override(&"margin_left", HudStyle.PAD_LEFT)
	_pad.add_theme_constant_override(&"margin_right", HudStyle.PAD)
	_pad.add_theme_constant_override(&"margin_top", HudStyle.PAD)
	_pad.add_theme_constant_override(&"margin_bottom", HudStyle.PAD)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override(&"separation", 0)
	_pad.add_child(body)
	add_child(_pad)
	_pad.minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	return _pad.get_combined_minimum_size()


func _draw() -> void:
	HudStyle.draw_ticket(self, Rect2(Vector2.ZERO, size), accent, lit)
