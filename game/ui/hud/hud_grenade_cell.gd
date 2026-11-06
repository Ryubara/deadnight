class_name HudGrenadeCell
extends HudSlotCell
## The grenades' place beside the weapons on the slot strip a finger uses (#1280): the same ticket
## as a weapon's, a grenade drawn on it and the count where a weapon has its number. A press and
## hold on it takes the grenade out and cooks it, the lift throws it; while the pin is out the
## place is lit like the weapon in hand, so the hold can be seen. No grenades left: dim.

## The grenade's body as a share of the shorter side of the picture.
const BODY := 0.25
const SEGMENTS := 48

## The grenades carried.
var count := 0


func _init() -> void:
	super()
	name = "GrenadeCell"


## Shows `grenades` carried, lit while the pin is out (`cooking`).
func show_grenades(grenades: int, cooking: bool) -> void:
	count = grenades
	show_slot(0, &"", cooking, null)


func _number_text(_slot_number: int) -> String:
	return "x%d" % count


## Lit while the pin is out, dim with none left, else as a weapon put away.
func ink_colour() -> Color:
	if held:
		return _tokens.ink_on_accent
	return _tokens.ink if count > 0 else _tokens.ink_disabled


func _add_art(shapes: HudShapes) -> void:
	var ink := ink_colour()
	var span := minf(size.x, size.y)
	var radius := span * BODY
	var centre := Vector2(size.x * 0.58, size.y * 0.64)
	# The body, a short neck and cap above it, the lever curling over its left side (the count has
	# the corner above it), the pin's ring on the right.
	shapes.circle(centre, radius, ink)
	var neck := Rect2(
		centre + Vector2(-radius * 0.28, -radius * 1.2), Vector2(radius * 0.56, radius * 0.4)
	)
	shapes.rect(neck, ink)
	var lever := PackedVector2Array(
		[
			centre + Vector2(-radius * 0.28, -radius * 1.2),
			centre + Vector2(-radius * 1.15, -radius * 0.95),
			centre + Vector2(-radius * 1.2, -radius * 0.2),
		]
	)
	shapes.polyline(lever, ink, maxf(radius * 0.18, 3.0))
	var ring := PackedVector2Array()
	var ring_centre := centre + Vector2(radius * 0.78, -radius * 1.2)
	for step in SEGMENTS + 1:
		var angle := TAU * float(step) / float(SEGMENTS)
		ring.append(ring_centre + Vector2(cos(angle), sin(angle)) * radius * 0.3)
	shapes.polyline(ring, ink, maxf(radius * 0.1, 2.0))
