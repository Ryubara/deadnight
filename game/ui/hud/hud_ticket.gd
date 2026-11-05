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

## The box the card's words go in, inside the padding. The padding and the box are made the first
## time something asks for them, so a card that stays hidden until it is needed (the scoreboard)
## holds neither: the late-round budget counts every canvas item of the tree, shown or not.
var body: VBoxContainer:
	get:
		if _body == null:
			_build_body()
		return _body

var _pad: MarginContainer
var _body: VBoxContainer


func _get_minimum_size() -> Vector2:
	return _pad.get_combined_minimum_size() if _pad != null else Vector2.ZERO


func _build_body() -> void:
	_pad = MarginContainer.new()
	_body = VBoxContainer.new()
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.add_theme_constant_override(&"margin_left", HudStyle.PAD_LEFT)
	_pad.add_theme_constant_override(&"margin_right", HudStyle.PAD)
	_pad.add_theme_constant_override(&"margin_top", HudStyle.PAD)
	_pad.add_theme_constant_override(&"margin_bottom", HudStyle.PAD)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override(&"separation", 0)
	_pad.add_child(_body)
	add_child(_pad)
	_pad.minimum_size_changed.connect(update_minimum_size)
	update_minimum_size()


func _draw() -> void:
	HudStyle.draw_ticket(self, Rect2(Vector2.ZERO, size), accent, lit)
