class_name HudBotWheel
extends Control
## The bot command wheel, drawn over the middle of the screen while it is held open: three tickets
## (Follow on top, Roam lower right, Hold lower left), the one under the pointer lit, the standing
## order marked "NOW", a small dial in the middle where letting go gives nothing. It reads a
## `BotWheel` and nothing else; `BotWheelDriver` feeds that. The look is the HUD's: flat paper, a
## hard shadow, a notched corner, an accent stripe (`HudStyle.draw_ticket`), no blur.

## Where a ticket's middle stands from the wheel's middle, canvas units.
const REACH := 190.0
## A ticket's size.
const CARD := Vector2(236.0, 88.0)
## The dial in the middle, and the pointer's dot.
const DIAL := 52.0
const DOT := 9.0
## How far the pointer's dot goes from the middle at the rim, and how much a lit ticket lifts.
const DOT_REACH := 120.0
const LIFT := 8.0
## The dim over the night behind the wheel (flat, no blur).
const DIM := 0.28
const NAME_SIZE := 30
const CAPTION_SIZE := HudStyle.MIN_TEXT
const HINT_SIZE := HudStyle.MIN_TEXT

## The wheel to draw; null draws nothing.
var wheel: BotWheel:
	set(value):
		wheel = value
		queue_redraw()

var _tokens := UITokens.active()
## The last frame's openness and hover, so a redraw is asked for only on a change.
var _drawn_growth := -1.0
var _drawn_hover: StringName = &""
var _drawn_pointer := Vector2.ZERO
var _drawn_current: StringName = &""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(_delta: float) -> void:
	if wheel == null:
		visible = false
		return
	visible = wheel.growth > 0.0
	if not visible:
		_drawn_growth = -1.0
		return
	if (
		wheel.growth != _drawn_growth
		or wheel.hovered() != _drawn_hover
		or wheel.pointer != _drawn_pointer
		or wheel.current != _drawn_current
	):
		_drawn_growth = wheel.growth
		_drawn_hover = wheel.hovered()
		_drawn_pointer = wheel.pointer
		_drawn_current = wheel.current
		queue_redraw()


## The rectangle of an order's ticket, in this control's coordinates, as drawn at full growth.
func card_rect(order: StringName) -> Rect2:
	var middle := size * 0.5 + BotWheel.direction_of(order) * REACH
	return Rect2(middle - CARD * 0.5, CARD)


## The dial's middle, where the wheel stands.
func centre() -> Vector2:
	return size * 0.5


func _draw() -> void:
	if wheel == null or wheel.growth <= 0.0:
		return
	var grow := 1.0 if UIMotion.reduced else _ease(wheel.growth)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, DIM * grow))
	var middle := centre()
	var hovered := wheel.hovered()
	for order in BotWheel.ORDERS:
		_draw_card(order, middle, grow, order == hovered)
	_draw_dial(middle, grow, hovered)


func _draw_card(order: StringName, middle: Vector2, grow: float, lit: bool) -> void:
	var rect := card_rect(order)
	# Grows out of the middle, and a lit ticket steps out a little further.
	var from_middle := rect.get_center() - middle
	var at := middle + from_middle * grow + BotWheel.direction_of(order) * (LIFT if lit else 0.0)
	rect = Rect2(at - rect.size * 0.5 * grow, rect.size * grow)
	# A ticket smaller than its notched corners has no outline to triangulate.
	if rect.size.y < HudStyle.NOTCH * 3.0 or rect.size.x < HudStyle.NOTCH * 3.0:
		return
	var current := order == wheel.current
	var accent := _tokens.accent_bright if (lit or current) else _tokens.accent
	HudStyle.draw_ticket(self, rect, accent, 1.0 if lit else 0.0)
	if grow < 0.85:
		return
	var font := _tokens.display_font(_tokens.embolden_display * 0.3)
	var text_font := _tokens.text_font(_tokens.embolden_display * 0.3, 1.0)
	var left := rect.position.x + HudStyle.PAD_LEFT
	var ink := _tokens.ink if lit else _tokens.ink_muted
	if lit:
		ink = _tokens.accent_bright
	draw_string(
		font,
		Vector2(left, rect.position.y + 38.0),
		BotWheel.NAMES[order],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		NAME_SIZE,
		ink
	)
	draw_string(
		text_font,
		Vector2(left, rect.position.y + 68.0),
		BotWheel.CAPTIONS[order],
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - HudStyle.PAD_LEFT - HudStyle.PAD,
		CAPTION_SIZE,
		_tokens.ink_muted if not lit else _tokens.ink
	)
	if current:
		var tag := "NOW"
		var width := text_font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
		draw_string(
			text_font,
			Vector2(rect.end.x - HudStyle.PAD - width, rect.position.y + 32.0),
			tag,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			CAPTION_SIZE,
			_tokens.hot
		)


func _draw_dial(middle: Vector2, grow: float, hovered: StringName) -> void:
	var radius := DIAL * grow
	draw_circle(middle + Vector2(3.0, 4.0), radius, _tokens.shadow)
	draw_circle(middle, radius, _tokens.surface_raised)
	draw_arc(middle, radius, 0.0, TAU, 48, _tokens.outline.lightened(0.4), float(_tokens.border))
	if grow < 0.85:
		return
	var font := _tokens.text_font(_tokens.embolden_display * 0.3, 1.0)
	var hint := "RELEASE TO SEND" if hovered != &"" else "CANCEL"
	var width := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE).x
	# The word under the dial says what letting go does now.
	draw_string(
		font,
		middle + Vector2(-width * 0.5, _below()),
		hint,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		HINT_SIZE,
		_tokens.ink if hovered != &"" else _tokens.ink_muted
	)
	# How to pick on the device in hand, and the dial's name.
	var how := _how_to_pick()
	var how_width := font.get_string_size(how, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE).x
	draw_string(
		font,
		middle + Vector2(-how_width * 0.5, _below() + HINT_SIZE + 6.0),
		how,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		HINT_SIZE,
		_tokens.ink_muted
	)
	var label := "BOTS"
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_SIZE).x
	draw_string(
		font,
		middle + Vector2(-label_width * 0.5, HINT_SIZE * 0.35),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		HINT_SIZE,
		_tokens.accent
	)
	var dot := middle + wheel.pointer * DOT_REACH * grow
	if hovered != &"":
		var along := (dot - middle).normalized()
		draw_line(middle + along * radius, dot, Color(_tokens.accent_bright, 0.6), 3.0, true)
	draw_circle(dot, DOT, _tokens.accent_bright if hovered != &"" else _tokens.ink)
	draw_arc(dot, DOT, 0.0, TAU, 20, _tokens.shadow, 2.0, true)


## Where the words under the wheel start, below the two lower tickets.
func _below() -> float:
	return REACH * 0.5 + CARD.y * 0.5 + LIFT + 32.0


## What picks an order with the device the player last used.
func _how_to_pick() -> String:
	if UIInputMode.touch:
		return "DRAG TO PICK"
	if UIInputMode.gamepad:
		return "RIGHT STICK TO PICK"
	return "MOUSE TO PICK"


func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)
