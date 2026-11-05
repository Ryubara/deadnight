@tool
class_name UICheckBox
extends Button
## A tick box with its label. The box fills on a spring and the tick draws itself in a stroke;
## hover lifts the fill, and the focus ring lands on the whole row. Read and set `button_pressed`;
## listen to `toggled`. The label is the button's own `text`, drawn in the theme's face.

## Pins the look for the demo sheet and captures: what a real hover or keyboard focus shows.
enum Preview { NONE, HOVER, FOCUS }

## The box is this many times the body text size.
const BOX_RATIO := 1.25
## The tick's three points, as shares of the box side from its centre.
const TICK_START := Vector2(-0.26, 0.02)
const TICK_BEND := Vector2(-0.06, 0.24)
const TICK_END := Vector2(0.28, -0.2)
const TICK_WIDTH := 3.5

@export var preview_state := Preview.NONE:
	set(value):
		preview_state = value
		set_process(true)

var _tokens := UITokens.active()
var _on: UISpring
var _hover: UISpring
var _focus: UISpring
var _ring: UIFocusRing
var _inside := false


## The side of the box a set of tokens gives: the theme reserves room for it on the left.
static func box_size(tokens: UITokens) -> int:
	return int(tokens.size_body * BOX_RATIO)


func _init() -> void:
	_on = UISpring.new()
	_hover = UISpring.new()
	_focus = UISpring.new()
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	# Inside a scroll area a drag that starts here reaches it (`UIScroll`); anywhere else the button
	# stops the pointer, as a button does.
	UIScroll.pass_touch_in_scroll(self)
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	theme_type_variation = UIThemeBuilder.CHECK_STYLE
	_apply_tokens()


## Reads the active tokens into everything this control caches: spring tuning, ring and size.
func _apply_tokens() -> void:
	_tokens = UITokens.active()
	_on.stiffness = _tokens.spring_stiffness
	_on.damping = _tokens.spring_damping * 0.7
	_hover.stiffness = _tokens.spring_stiffness
	_hover.damping = _tokens.spring_damping
	_focus.stiffness = _tokens.spring_stiffness * 0.7
	_focus.damping = _tokens.spring_damping * 0.8
	_ring = UIFocusRing.new(_tokens, _tokens.radius_md)
	custom_minimum_size.y = _tokens.control_height
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
	toggled.connect(_on_toggled)
	_update_targets()
	for spring in [_on, _hover, _focus]:
		spring.snap(spring.target)


func _process(delta: float) -> void:
	_update_targets()
	var settled := true
	for spring in [_on, _hover, _focus]:
		if UIMotion.reduced:
			spring.snap(spring.target)
		spring.step(delta)
		settled = settled and spring.is_settled()
	queue_redraw()
	if settled:
		set_process(false)


func _notification(what: int) -> void:
	if (
		what
		in [
			NOTIFICATION_FOCUS_ENTER,
			NOTIFICATION_FOCUS_EXIT,
			NOTIFICATION_MOUSE_ENTER,
			NOTIFICATION_MOUSE_EXIT,
			NOTIFICATION_DISABLED,
			NOTIFICATION_ENABLED
		]
	):
		set_process(true)
	elif what == NOTIFICATION_DRAW and not is_processing():
		_update_targets()
		if not (_on.is_settled() and _hover.is_settled() and _focus.is_settled()):
			set_process(true)


func _draw() -> void:
	var side := float(box_size(_tokens))
	var box := Rect2(Vector2(_tokens.space_sm, (size.y - side) * 0.5), Vector2.ONE * side)
	var fill := StyleBoxFlat.new()
	fill.anti_aliasing = true
	fill.set_corner_radius_all(_tokens.radius_sm)
	fill.set_border_width_all(_tokens.border)
	var off_fill := _tokens.surface_raised.lerp(
		_tokens.surface_raised.lightened(_tokens.tint_hover), _hover.value
	)
	var on_t := clampf(_on.value, 0.0, 1.0)
	fill.bg_color = off_fill.lerp(_tokens.accent.lerp(_tokens.accent_bright, _hover.value), on_t)
	fill.border_color = _tokens.outline.lerp(_tokens.accent, maxf(on_t, _hover.value))
	if disabled:
		fill.bg_color = _tokens.surface
		fill.border_color = _tokens.outline
	draw_style_box(fill, box)
	_draw_tick(box, on_t)
	_ring.draw(self, Rect2(Vector2.ZERO, size), _focus.value)


## Strokes the tick from its start to `amount` of its length (0 to 1).
func _draw_tick(box: Rect2, amount: float) -> void:
	if amount <= 0.01:
		return
	var centre := box.get_center()
	var points := [
		centre + TICK_START * box.size.x,
		centre + TICK_BEND * box.size.x,
		centre + TICK_END * box.size.x,
	]
	var first := (points[1] as Vector2).distance_to(points[0])
	var second := (points[2] as Vector2).distance_to(points[1])
	var reach := amount * (first + second)
	var path := PackedVector2Array([points[0]])
	if reach <= first:
		path.append((points[0] as Vector2).lerp(points[1], reach / first))
	else:
		path.append(points[1])
		path.append((points[1] as Vector2).lerp(points[2], (reach - first) / second))
	var colour := _tokens.ink_disabled if disabled else _tokens.ink_on_accent
	draw_polyline(path, colour, TICK_WIDTH, true)


func _on_mouse_entered() -> void:
	_inside = true
	UIAudio.play(&"hover", self)
	if not disabled:
		grab_focus()
	set_process(true)


func _on_mouse_exited() -> void:
	_inside = false
	set_process(true)


func ui_sound_role() -> StringName:
	return &"toggle"


func _on_toggled(on: bool) -> void:
	UIAudio.play(&"on" if on else &"off", self)
	set_process(true)


func _update_targets() -> void:
	_on.target = 1.0 if button_pressed else 0.0
	var lit := _inside or preview_state == Preview.HOVER
	_hover.target = 1.0 if lit and not disabled else 0.0
	var ringed := (has_focus() and not UIInputMode.pointer) or preview_state == Preview.FOCUS
	_focus.target = 1.0 if ringed else 0.0
