@tool
class_name UILineEdit
extends LineEdit
## A one-line text field drawn from tokens. The engine's LineEdit supplies typing, selection and the
## caret; the theme gives it its fill, border, face and caret colour. A keyboard or gamepad focus
## lands a ring round the field on a spring, and a click shows the accent border alone.

## Pins the look for the demo sheet and captures: what a real hover or keyboard focus shows.
enum Preview { NONE, HOVER, FOCUS }

@export var preview_state := Preview.NONE:
	set(value):
		preview_state = value
		set_process(true)

var _tokens := UITokens.active()
var _hover: UISpring
var _focus: UISpring
var _ring: UIFocusRing
var _inside := false
## Whether the field took focus from the keyboard or a gamepad: typing is not a reason to ring it.
var _keys_focus := false


func _init() -> void:
	_hover = UISpring.new()
	_focus = UISpring.new()
	focus_mode = Control.FOCUS_ALL
	theme_type_variation = UIThemeBuilder.LINE_EDIT_STYLE
	_apply_tokens()


## Reads the active tokens into everything this control caches: spring tuning, ring and size.
func _apply_tokens() -> void:
	_tokens = UITokens.active()
	_hover.stiffness = _tokens.spring_stiffness
	_hover.damping = _tokens.spring_damping
	_focus.stiffness = _tokens.spring_stiffness * 0.7
	_focus.damping = _tokens.spring_damping * 0.8
	_ring = UIFocusRing.new(_tokens, _tokens.radius_md)
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
	focus_entered.connect(_on_focus_entered)
	_update_targets()
	for spring in [_hover, _focus]:
		spring.snap(spring.target)


func _process(delta: float) -> void:
	_update_targets()
	var settled := true
	for spring in [_hover, _focus]:
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
	elif what == NOTIFICATION_DRAW and not is_processing():
		_update_targets()
		if not (_hover.is_settled() and _focus.is_settled()):
			set_process(true)


func _draw() -> void:
	# The engine has drawn the fill and the border; the hover tint and the ring go over them.
	if _hover.value > 0.01:
		var tint := StyleBoxFlat.new()
		tint.anti_aliasing = true
		tint.draw_center = false
		tint.set_corner_radius_all(_tokens.radius_md)
		tint.set_border_width_all(_tokens.border)
		tint.border_color = Color(_tokens.accent, _hover.value * 0.6)
		draw_style_box(tint, Rect2(Vector2.ZERO, size))
	_ring.draw(self, Rect2(Vector2.ZERO, size), _focus.value)


func ui_sound_role() -> StringName:
	return &"field"


func _on_focus_entered() -> void:
	_keys_focus = not UIInputMode.pointer
	UIAudio.play(&"focus", self)


func _on_mouse_entered() -> void:
	_inside = true
	UIAudio.play(&"hover", self)
	set_process(true)


func _on_mouse_exited() -> void:
	_inside = false
	set_process(true)


func _update_targets() -> void:
	var lit := (_inside or preview_state == Preview.HOVER) and editable
	_hover.target = 1.0 if lit else 0.0
	var ringed := (has_focus() and _keys_focus) or preview_state == Preview.FOCUS
	_focus.target = 1.0 if ringed else 0.0
