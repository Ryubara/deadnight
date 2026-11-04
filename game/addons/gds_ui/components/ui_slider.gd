@tool
class_name UISlider
extends HSlider
## A horizontal slider drawn from tokens. The engine's HSlider supplies the value, step, mouse and
## keyboard handling; the theme gives it an invisible grabber of the right size so its hit-testing
## matches what is drawn here. The thumb grows on hover and press, the fill follows the value on a
## spring, and the focus ring lands on the thumb.

var _tokens := UITokens.active()
var _shown: UISpring
var _hover: UISpring
var _press: UISpring
var _focus: UISpring
var _ring: UIFocusRing
var _inside := false
var _held := false


func _init() -> void:
	_shown = UISpring.new()
	_hover = UISpring.new()
	_press = UISpring.new()
	_focus = UISpring.new()
	focus_mode = Control.FOCUS_ALL
	scrollable = false
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	theme_type_variation = UIThemeBuilder.SLIDER_STYLE
	_apply_tokens()


## Reads the active tokens into everything this control caches: spring tuning and size. The thumb's
## hit area is an icon in the theme, which the router rebuilds from the same tokens.
func _apply_tokens() -> void:
	_tokens = UITokens.active()
	_shown.stiffness = _tokens.spring_stiffness * 2.0
	_shown.damping = _tokens.spring_damping * 1.4
	_hover.stiffness = _tokens.spring_stiffness
	_hover.damping = _tokens.spring_damping
	_press.stiffness = _tokens.spring_stiffness * 1.4
	_press.damping = _tokens.spring_damping
	_focus.stiffness = _tokens.spring_stiffness * 0.7
	_focus.damping = _tokens.spring_damping * 0.8
	_ring = UIFocusRing.new(_tokens, _tokens.control_height)
	custom_minimum_size = Vector2(0.0, _tokens.control_height)
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
	value_changed.connect(_on_value_changed)
	_update_targets()
	for spring in [_shown, _hover, _press, _focus]:
		spring.snap(spring.target)


func _process(delta: float) -> void:
	_update_targets()
	var settled := true
	for spring in [_shown, _hover, _press, _focus]:
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
		if not _all_settled():
			set_process(true)


func _gui_input(event: InputEvent) -> void:
	# The native handler still runs after this; we only note the press for the thumb's squash.
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	):
		_held = (event as InputEventMouseButton).pressed
		set_process(true)


func _draw() -> void:
	var thumb := float(_thumb_width())
	var track_h := float(_tokens.track_height)
	var mid := size.y * 0.5
	var travel := maxf(size.x - thumb, 1.0)
	var x := thumb * 0.5 + travel * _shown.value
	var track_rect := Rect2(0.0, mid - track_h * 0.5, size.x, track_h)
	draw_style_box(_pill(_tokens.surface_raised, _tokens.outline, _tokens.border), track_rect)
	track_rect.size.x = maxf(x, track_h)
	var fill := _tokens.accent.lerp(_tokens.accent_bright, _hover.value)
	draw_style_box(_pill(fill, fill, 0), track_rect)
	var radius := (
		thumb * 0.5 - float(_tokens.knob_inset) * 0.5 + _hover.value * 2.0 - _press.value * 2.0
	)
	var centre := Vector2(x, mid)
	draw_circle(centre + Vector2(0.0, 2.0), radius, Color(_tokens.shadow, 0.5))
	draw_circle(centre, radius, _tokens.ink.lerp(_tokens.accent_bright, _press.value))
	draw_circle(centre, radius * 0.38, _tokens.accent)
	_ring.draw(self, Rect2(centre - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), _focus.value)


func _pill(fill: Color, edge: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.anti_aliasing = true
	box.set_corner_radius_all(_tokens.track_height)
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border_width)
	return box


func _thumb_width() -> int:
	return get_theme_icon(&"grabber").get_width()


func _on_mouse_entered() -> void:
	_inside = true
	UIAudio.play(&"hover", self)
	grab_focus()
	set_process(true)


func _on_mouse_exited() -> void:
	_inside = false
	set_process(true)


func ui_sound_role() -> StringName:
	return &"slider"


func _on_value_changed(_value: float) -> void:
	UIAudio.play(&"tick", self)
	set_process(true)


func _ratio() -> float:
	return 0.0 if max_value <= min_value else (value - min_value) / (max_value - min_value)


func _update_targets() -> void:
	_shown.target = _ratio()
	_hover.target = 1.0 if _inside and editable else 0.0
	_press.target = 1.0 if _held and editable else 0.0
	_focus.target = 1.0 if has_focus() and not UIInputMode.pointer else 0.0


func _all_settled() -> bool:
	return (
		_shown.is_settled() and _hover.is_settled() and _press.is_settled() and _focus.is_settled()
	)
