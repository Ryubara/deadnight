@tool
class_name UIToggle
extends Button
## An on/off switch. The knob rides a slightly under-damped spring, so it settles with a hint of
## overshoot; the track colour follows. Read and set `button_pressed`; listen to `toggled`.

const WIDTH_RATIO := 1.9

var _tokens := UITokens.active()
var _on: UISpring
var _hover: UISpring
var _focus: UISpring
var _ring: UIFocusRing


func _init() -> void:
	_on = UISpring.new()
	_hover = UISpring.new()
	_focus = UISpring.new()
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	# Inside a scroll area a drag that starts here reaches it (`UIScroll`); anywhere else the button
	# stops the pointer, as a button does.
	UIScroll.pass_touch_in_scroll(self)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	theme_type_variation = UIThemeBuilder.TOGGLE_STYLE
	_apply_tokens()


## Reads the active tokens into everything this control caches: spring tuning and size.
func _apply_tokens() -> void:
	_tokens = UITokens.active()
	_on.stiffness = _tokens.spring_stiffness
	_on.damping = _tokens.spring_damping * 0.7
	_hover.stiffness = _tokens.spring_stiffness
	_hover.damping = _tokens.spring_damping
	_focus.stiffness = _tokens.spring_stiffness * 0.7
	_focus.damping = _tokens.spring_damping * 0.8
	_ring = UIFocusRing.new(_tokens, _tokens.control_height)
	custom_minimum_size = Vector2(_tokens.control_height * WIDTH_RATIO, _tokens.control_height)
	queue_redraw()


func _on_tokens_changed(_next: UITokens) -> void:
	_apply_tokens()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	UITokens.active_changed().connect(_on_tokens_changed)
	mouse_entered.connect(_on_mouse_entered)
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
			NOTIFICATION_MOUSE_ENTER,
			NOTIFICATION_MOUSE_EXIT,
			NOTIFICATION_FOCUS_ENTER,
			NOTIFICATION_FOCUS_EXIT
		]
	):
		set_process(true)
	elif what == NOTIFICATION_DRAW and not is_processing():
		_update_targets()
		if not (_on.is_settled() and _hover.is_settled() and _focus.is_settled()):
			set_process(true)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var radius := size.y * 0.5
	var track := StyleBoxFlat.new()
	track.anti_aliasing = true
	track.set_corner_radius_all(int(radius))
	track.set_border_width_all(_tokens.border)
	var off_fill := _tokens.surface_raised.lerp(
		_tokens.surface_raised.lightened(_tokens.tint_hover), _hover.value
	)
	track.bg_color = off_fill.lerp(
		_tokens.accent.lerp(_tokens.accent_bright, _hover.value), _on.value
	)
	track.border_color = _tokens.outline.lerp(_tokens.accent, maxf(_on.value, _hover.value))
	if disabled:
		track.bg_color = _tokens.surface
		track.border_color = _tokens.outline
	draw_style_box(track, rect)
	var knob_radius := radius - float(_tokens.knob_inset) + _hover.value * 2.0
	var travel := size.x - 2.0 * radius
	var knob_at := Vector2(radius + travel * _on.value, radius)
	var knob_colour := _tokens.ink_muted.lerp(_tokens.ink_on_accent, _on.value)
	draw_circle(
		knob_at + Vector2(0.0, 2.0),
		knob_radius,
		Color(_tokens.shadow, 0.35 * (1.0 - _on.value * 0.5))
	)
	draw_circle(knob_at, knob_radius, _tokens.ink_disabled if disabled else knob_colour)
	_ring.draw(self, rect, _focus.value)


func _on_mouse_entered() -> void:
	UIAudio.play(&"hover", self)
	if not disabled:
		grab_focus()


func ui_sound_role() -> StringName:
	return &"toggle"


func _on_toggled(on: bool) -> void:
	UIAudio.play(&"on" if on else &"off", self)
	set_process(true)


func _update_targets() -> void:
	var mode := get_draw_mode()
	_on.target = 1.0 if button_pressed else 0.0
	_hover.target = (
		1.0 if (mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED) and not disabled else 0.0
	)
	_focus.target = 1.0 if has_focus() and not UIInputMode.pointer else 0.0
