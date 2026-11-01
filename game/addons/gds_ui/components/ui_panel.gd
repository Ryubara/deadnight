@tool
class_name UIPanel
extends PanelContainer
## A card with elevation. The marquee variant runs a chase of bulbs around its border.

enum Variant { FLAT, RAISED, MARQUEE }

@export var variant := Variant.RAISED:
	set(value):
		variant = value
		theme_type_variation = UIThemeBuilder.PANEL_STYLES[value]
		_update_processing()
		queue_redraw()

var _tokens := UITokens.active()
var _box := StyleBoxFlat.new()
var _time := 0.0


func _init() -> void:
	_box.anti_aliasing = true
	_apply_tokens()
	theme_type_variation = UIThemeBuilder.PANEL_STYLES[variant]


func _ready() -> void:
	_update_processing()
	if not Engine.is_editor_hint():
		UITokens.active_changed().connect(_on_tokens_changed)
		UIMotion.changed().connect(_on_reduced_changed)


func _apply_tokens() -> void:
	_tokens = UITokens.active()
	_box.set_corner_radius_all(_tokens.radius_lg)
	_box.set_border_width_all(_tokens.border)
	_box.shadow_color = _tokens.shadow
	queue_redraw()


func _on_tokens_changed(_next: UITokens) -> void:
	_apply_tokens()


## The chase stands still under reduced motion, and follows the switch while the panel is shown.
func _on_reduced_changed(_reduced: bool) -> void:
	_update_processing()
	queue_redraw()


func _update_processing() -> void:
	set_process(variant == Variant.MARQUEE and not UIMotion.reduced and not Engine.is_editor_hint())


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_box.bg_color = _tokens.surface if variant == Variant.FLAT else _tokens.surface_raised
	_box.border_color = _tokens.accent if variant == Variant.MARQUEE else _tokens.outline
	_box.shadow_size = _tokens.shadow_flat if variant == Variant.FLAT else _tokens.shadow_raised
	_box.shadow_offset = Vector2(0.0, _box.shadow_size * 0.35)
	draw_style_box(_box, rect)
	if variant == Variant.MARQUEE:
		_draw_bulbs(rect.grow(-float(_tokens.space_md)))


## Bulbs along the rectangle's edge; every third one is lit, and the lit set walks around.
func _draw_bulbs(rect: Rect2) -> void:
	var perimeter := 2.0 * (rect.size.x + rect.size.y)
	var count := maxi(int(perimeter / _tokens.bulb_spacing), 4)
	var period := maxi(_tokens.chase_period, 1)
	var phase := int(_time * _tokens.chase_speed * period)
	for i in count:
		var at := _perimeter_point(rect, perimeter * float(i) / float(count))
		var lit := (i + phase) % period == 0
		var colour := _tokens.accent_bright if lit else _tokens.outline
		if lit:
			draw_circle(at, _tokens.bulb_radius * 2.4, Color(_tokens.accent, 0.18))
		draw_circle(at, _tokens.bulb_radius, colour)


static func _perimeter_point(rect: Rect2, distance: float) -> Vector2:
	var d := distance
	if d < rect.size.x:
		return rect.position + Vector2(d, 0.0)
	d -= rect.size.x
	if d < rect.size.y:
		return rect.position + Vector2(rect.size.x, d)
	d -= rect.size.y
	if d < rect.size.x:
		return rect.position + Vector2(rect.size.x - d, rect.size.y)
	d -= rect.size.x
	return rect.position + Vector2(0.0, rect.size.y - d)
