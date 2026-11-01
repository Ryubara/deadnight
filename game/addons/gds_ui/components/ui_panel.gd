@tool
class_name UIPanel
extends PanelContainer
## A card with elevation. The marquee variant runs a chase of bulbs around its border.

enum Variant { FLAT, RAISED, MARQUEE }

const BULB_SPACING := 34.0
const BULB_RADIUS := 4.5
const CHASE_SPEED := 2.2
const CHASE_PERIOD := 3

@export var variant := Variant.RAISED:
	set(value):
		variant = value
		theme_type_variation = UIThemeBuilder.PANEL_STYLES[value]
		set_process(value == Variant.MARQUEE and not UIMotion.reduced)
		queue_redraw()

var _tokens := UITokens.active()
var _box := StyleBoxFlat.new()
var _time := 0.0


func _init() -> void:
	_box.anti_aliasing = true
	_box.set_corner_radius_all(_tokens.radius_lg)
	_box.set_border_width_all(_tokens.border)
	_box.shadow_color = _tokens.shadow
	theme_type_variation = UIThemeBuilder.PANEL_STYLES[variant]


func _ready() -> void:
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
	var count := maxi(int(perimeter / BULB_SPACING), 4)
	var phase := int(_time * CHASE_SPEED * CHASE_PERIOD)
	for i in count:
		var at := _perimeter_point(rect, perimeter * float(i) / float(count))
		var lit := (i + phase) % CHASE_PERIOD == 0
		var colour := _tokens.accent_bright if lit else _tokens.outline
		if lit:
			draw_circle(at, BULB_RADIUS * 2.4, Color(_tokens.accent, 0.18))
		draw_circle(at, BULB_RADIUS, colour)


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
