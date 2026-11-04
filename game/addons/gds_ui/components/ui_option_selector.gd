@tool
class_name UIOptionSelector
extends Control
## Picks one of a short list: chevrons on both sides, the choice in the middle. Click either side,
## press left/right (or the d-pad), or accept to step forward; stepping wraps round the ends.
## The old
## choice slides out and the new one slides in from the side it came from.

signal selected_changed(index: int)

const SLIDE_DISTANCE := 28.0
const CHEVRON_SIZE := 9.0
const CHEVRON_WIDTH := 3.0
const EDGE_ZONE := 0.3

@export var options := PackedStringArray():
	set(value):
		options = value
		_index = clampi(_index, 0, maxi(options.size() - 1, 0))
		queue_redraw()
@export var selected := 0:
	get:
		return _index
	set(value):
		select(value, false)

var _tokens := UITokens.active()
var _index := 0
var _hover: UISpring
var _focus: UISpring
var _change: UISpring
var _left: UISpring
var _right: UISpring
var _previous := ""
var _direction := 1.0
var _inside := false
var _ring: UIFocusRing
var _fill := StyleBoxFlat.new()


func _init() -> void:
	_hover = UISpring.new()
	_focus = UISpring.new()
	_change = UISpring.new()
	_left = UISpring.new()
	_right = UISpring.new()
	_change.snap(1.0)
	_fill.anti_aliasing = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_tokens()


## Reads the active tokens into everything this control caches: spring tuning, shapes and size.
func _apply_tokens() -> void:
	_tokens = UITokens.active()
	for spring in [_hover, _change]:
		spring.stiffness = _tokens.spring_stiffness
		spring.damping = _tokens.spring_damping
	_focus.stiffness = _tokens.spring_stiffness * 0.7
	_focus.damping = _tokens.spring_damping * 0.8
	for spring in [_left, _right]:
		spring.stiffness = _tokens.spring_stiffness * 1.4
		spring.damping = _tokens.spring_damping
	_ring = UIFocusRing.new(_tokens, _tokens.radius_md)
	_fill.set_corner_radius_all(_tokens.radius_md)
	_fill.set_border_width_all(_tokens.border)
	custom_minimum_size = Vector2(_tokens.control_width * 0.5, _tokens.control_height)
	queue_redraw()


func _on_tokens_changed(_next: UITokens) -> void:
	_apply_tokens()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	UITokens.active_changed().connect(_on_tokens_changed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(UIAudio.play.bind(&"focus", self))


## Chooses an index (clamped, no wrap). Emits `selected_changed` if it changed and `emit` is set.
func select(index: int, emit := true) -> void:
	var clamped := clampi(index, 0, maxi(options.size() - 1, 0))
	if clamped == _index:
		return
	_move_to(clamped, 1.0 if clamped > _index else -1.0)
	if emit:
		selected_changed.emit(_index)


## Moves by `delta` places, wrapping round the ends, and emits `selected_changed`.
func step(delta: int) -> void:
	if options.size() < 2:
		return
	_move_to(posmod(_index + delta, options.size()), float(signi(delta)))
	(_left if delta < 0 else _right).value = 1.0
	UIAudio.play(&"select", self)
	selected_changed.emit(_index)


func ui_sound_role() -> StringName:
	return &"option"


func text() -> String:
	return options[_index] if _index < options.size() else ""


func _move_to(index: int, direction: float) -> void:
	_direction = direction
	_previous = text()
	_index = index
	_change.snap(0.0)
	_change.target = 1.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_update_targets()
	var settled := true
	for spring in [_hover, _focus, _change, _left, _right]:
		if UIMotion.reduced:
			spring.snap(spring.target)
		spring.step(delta)
		settled = settled and spring.is_settled()
	queue_redraw()
	if settled:
		set_process(false)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT]:
		set_process(true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		set_process(true)
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			step(-1 if click.position.x < size.x * EDGE_ZONE else 1)
			accept_event()
	elif event.is_action_pressed(&"ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_accept"):
		step(1)
		accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var lit := maxf(_hover.value, _focus.value)
	_fill.bg_color = _tokens.surface_raised.lerp(
		_tokens.surface_raised.lightened(_tokens.tint_hover), _hover.value
	)
	_fill.border_color = _tokens.outline.lerp(_tokens.accent, lit)
	draw_style_box(_fill, rect)
	var inset := float(_tokens.space_lg)
	var side := _pointer_side()
	_draw_chevron(Vector2(inset, size.y * 0.5), -1.0, _left.value, side < 0)
	_draw_chevron(Vector2(size.x - inset, size.y * 0.5), 1.0, _right.value, side > 0)
	var font := get_theme_font(&"font", &"UIOptionSelector")
	var font_size := get_theme_font_size(&"font_size", &"UIOptionSelector")
	var t := _change.value
	_draw_text(font, font_size, _previous, -_direction * t * SLIDE_DISTANCE, 1.0 - t)
	_draw_text(font, font_size, text(), _direction * (1.0 - t) * SLIDE_DISTANCE, t)
	_ring.draw(self, rect, _focus.value)


func _draw_text(font: Font, font_size: int, shown: String, shift: float, alpha: float) -> void:
	if shown == "" or alpha <= 0.01:
		return
	var width := size.x - 4.0 * _tokens.space_lg
	var extent := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var baseline := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var at := Vector2((size.x - extent.x) * 0.5 + shift, baseline)
	draw_string(
		font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, Color(_tokens.ink, alpha)
	)


func _draw_chevron(at: Vector2, side: float, nudge: float, hovered: bool) -> void:
	var colour := _tokens.ink_muted.lerp(
		_tokens.accent_bright, maxf(nudge, 1.0 if hovered else 0.0)
	)
	# Rests pointing outward a little, and a step pushes it further the way it points.
	var tip := at + Vector2(side * (CHEVRON_SIZE * 0.5 + nudge * 4.0), 0.0)
	var arm := Vector2(-side * CHEVRON_SIZE * 0.7, CHEVRON_SIZE)
	var points := PackedVector2Array([tip + arm * Vector2(1.0, -1.0), tip, tip + arm])
	draw_polyline(points, colour, CHEVRON_WIDTH, true)


## -1 when the pointer is over the left chevron zone, 1 on the right, else 0.
func _pointer_side() -> int:
	if not _inside:
		return 0
	var local := get_local_mouse_position()
	if local.x < size.x * EDGE_ZONE:
		return -1
	return 1 if local.x > size.x * (1.0 - EDGE_ZONE) else 0


func _update_targets() -> void:
	_hover.target = 1.0 if _inside else 0.0
	_focus.target = 1.0 if has_focus() and not UIInputMode.pointer else 0.0
	_left.target = 0.0
	_right.target = 0.0


func _on_mouse_entered() -> void:
	_inside = true
	UIAudio.play(&"hover", self)
	grab_focus()
	set_process(true)


func _on_mouse_exited() -> void:
	_inside = false
	set_process(true)
