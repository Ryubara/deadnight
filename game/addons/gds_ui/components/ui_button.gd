@tool
class_name UIButton
extends Button
## A button that is drawn, not styled: springs carry hover lift, press squash and the focus ring.
##
## The theme variation supplies type and margins; the fill, shadow and ring are drawn on a child
## layer behind the button (a script `_draw` runs after the native one, so it would cover the text).

enum Variant { PRIMARY, SECONDARY, GHOST }
## Forces one state, for static captures of every state side by side.
enum Preview { NONE, NORMAL, HOVER, PRESSED, FOCUS, DISABLED }

@export var variant := Variant.PRIMARY:
	set(value):
		variant = value
		theme_type_variation = UIThemeBuilder.BUTTON_STYLES[value]
		_back.queue_redraw()
@export var preview_state := Preview.NONE:
	set(value):
		preview_state = value
		disabled = value == Preview.DISABLED
		_back.queue_redraw()

var _tokens := UITokens.active()
var _hover: UISpring
var _press: UISpring
var _focus: UISpring
var _off: UISpring
var _fill := StyleBoxFlat.new()
var _ring: UIFocusRing
var _back := Control.new()


func _init() -> void:
	_hover = UISpring.new()
	_press = UISpring.new()
	_focus = UISpring.new()
	_off = UISpring.new()
	_fill.anti_aliasing = true
	_apply_tokens()
	focus_mode = Control.FOCUS_ALL
	# Inside a scroll area a drag that starts here reaches it (`UIScroll`); anywhere else the button
	# stops the pointer, as a button does.
	UIScroll.pass_touch_in_scroll(self)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	theme_type_variation = UIThemeBuilder.BUTTON_STYLES[variant]
	_back.show_behind_parent = true
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back.draw.connect(_draw_back)
	add_child(_back, false, Node.INTERNAL_MODE_FRONT)


func _ready() -> void:
	resized.connect(_update_pivot)
	_update_pivot()
	if Engine.is_editor_hint():
		return
	UITokens.active_changed().connect(_on_tokens_changed)
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(UIAudio.play.bind(&"focus", self))
	pressed.connect(UIAudio.play.bind(&"press", self))
	snap_to_targets()


func _process(delta: float) -> void:
	_update_targets()
	var settled := true
	for spring in [_hover, _press, _focus, _off]:
		spring.step(delta)
		settled = settled and spring.is_settled()
	_apply_scale()
	_back.queue_redraw()
	if settled:
		set_process(false)


## Sets the scale the springs ask for: grown by the hover, squashed by the press. A grown button
## stays inside the nearest ancestor that clips it (a ScrollContainer, or any control with
## `clip_contents`): the part that sticks out is not drawn, and a button that fills its slot edge
## to edge lost its sides when hovered (#628). The theme gives scrolling areas room at their sides
## for the whole growth (`UITokens.hover_room`); this is the guarantee where nothing has, and each
## axis grows by what room there is, so a button on the last row of a scroll area still widens.
func _apply_scale() -> void:
	var factor := 1.0 + _hover.value * _tokens.hover_scale - _press.value * _tokens.press_squash
	var scale_now := Vector2.ONE * factor
	if factor > 1.0:
		var room := _room_factor()
		scale_now = Vector2(minf(factor, room.x), minf(factor, room.y))
	scale = scale_now


## The largest scale on each axis that keeps the button, grown about its centre, inside the nearest
## ancestor that clips it: 1 plus twice the free room at the tighter side, over the button's own
## size. Without such an ancestor it is unbounded.
func _room_factor() -> Vector2:
	var parent := get_parent() as CanvasItem
	var clip := _clipper()
	if parent == null or clip == null or size.x <= 0.0 or size.y <= 0.0:
		return Vector2.INF
	var into := clip.get_global_transform().affine_inverse() * parent.get_global_transform()
	var slot := into * Rect2(position, size)
	var free := (
		Vector2(
			minf(slot.position.x, clip.size.x - slot.end.x),
			minf(slot.position.y, clip.size.y - slot.end.y)
		)
		. max(Vector2.ZERO)
	)
	return Vector2.ONE + 2.0 * free / slot.size


func _clipper() -> Control:
	var up := get_parent()
	while up != null:
		if up is Control and ((up as Control).clip_contents or up is ScrollContainer):
			return up as Control
		up = up.get_parent()
	return null


func _notification(what: int) -> void:
	# Any of these can change a target; _process stops itself once every spring has settled.
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
		if not _all_at_target():
			set_process(true)


## Reads the active tokens into everything this button caches: spring tuning, shapes and colours.
func _apply_tokens() -> void:
	_tokens = UITokens.active()
	_hover.stiffness = _tokens.spring_stiffness
	_hover.damping = _tokens.spring_damping
	_press.stiffness = _tokens.spring_stiffness * 1.4
	_press.damping = _tokens.spring_damping
	_focus.stiffness = _tokens.spring_stiffness * 0.7
	_focus.damping = _tokens.spring_damping * 0.8
	_off.stiffness = _tokens.spring_stiffness
	_off.damping = _tokens.spring_damping
	_fill.set_corner_radius_all(_tokens.radius_md)
	_ring = UIFocusRing.new(_tokens, _tokens.radius_md)
	_fill.shadow_color = _tokens.shadow
	_back.queue_redraw()


func _on_tokens_changed(_next: UITokens) -> void:
	_apply_tokens()
	set_process(true)


func _draw_back() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_paint_fill()
	_back.draw_style_box(_fill, rect)
	_ring.draw(_back, rect, _focus.value)


func ui_sound_role() -> StringName:
	return &"button_" + ["primary", "secondary", "ghost"][variant]


func _on_mouse_entered() -> void:
	UIAudio.play(&"hover", self)
	if not disabled:
		grab_focus()


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _is_focus_shown() -> bool:
	if preview_state != Preview.NONE:
		return preview_state == Preview.FOCUS
	return has_focus() and not UIInputMode.pointer


func _update_targets() -> void:
	var mode := get_draw_mode()
	var hovered := mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED
	var held := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
	match preview_state:
		Preview.HOVER:
			hovered = true
		Preview.PRESSED:
			hovered = true
			held = true
		Preview.FOCUS:
			hovered = false
	_hover.target = 1.0 if (hovered or _is_focus_shown()) and not disabled else 0.0
	_press.target = 1.0 if held and not disabled else 0.0
	_focus.target = 1.0 if _is_focus_shown() else 0.0
	_off.target = 1.0 if disabled else 0.0


func _all_at_target() -> bool:
	return _hover.is_settled() and _press.is_settled() and _focus.is_settled() and _off.is_settled()


## Jumps every spring to where its state says it ends up, so the next frame is the settled look
## (a static capture, a test; `_ready` uses it too).
func snap_to_targets() -> void:
	_update_targets()
	for spring in [_hover, _press, _focus, _off]:
		spring.snap(spring.target)
	_apply_scale()


## Colours the fill box for the current spring values.
func _paint_fill() -> void:
	var rest: Color
	var lit: Color
	var edge := Color.TRANSPARENT
	var edge_lit := Color.TRANSPARENT
	match variant:
		Variant.PRIMARY:
			rest = _tokens.accent
			lit = _tokens.accent_bright
		Variant.SECONDARY:
			rest = _tokens.surface_raised
			lit = _tokens.surface_raised.lightened(_tokens.tint_hover)
			edge = _tokens.outline
			edge_lit = _tokens.accent
		_:
			rest = Color(_tokens.surface_raised, 0.0)
			lit = Color(_tokens.surface_raised, _tokens.ghost_hover_alpha)
			edge_lit = _tokens.outline
	var fill := rest.lerp(lit, _hover.value)
	fill = fill.lerp(fill.darkened(_tokens.tint_press), _press.value)
	var border := edge.lerp(edge_lit, _hover.value)
	var off_fill := Color(_tokens.surface, _tokens.disabled_alpha)
	_fill.bg_color = fill.lerp(off_fill, _off.value)
	_fill.border_color = border.lerp(_tokens.outline, _off.value)
	_fill.set_border_width_all(_tokens.border)
	var lift := lerpf(float(_tokens.shadow_raised), float(_tokens.shadow_hover), _hover.value)
	lift = lerpf(lift, float(_tokens.shadow_flat), maxf(_press.value, _off.value))
	if variant == Variant.GHOST:
		lift *= _hover.value
	_fill.shadow_size = int(lift)
	_fill.shadow_offset = Vector2(0.0, lift * 0.35)
