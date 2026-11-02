class_name MenuScale
extends RefCounted
## The menu's size rules for small screens. The project stretches a 1920 x 1080 design to any
## window; on a phone held sideways (shorter side under `PHONE_SHORT_SIDE` px) that makes one unit
## 0.36 px at 844 x 390 and the type unreadable. The phone factor doubles the units' size, so the
## design is 540 high there: one unit 0.72 px, a caption of 22 units 15.8 px, a body of 26 units
## 18.7 px, a tap target of 64 units 46 px (the written minimums are 14, 18 and 44).

const PHONE_SHORT_SIDE := 500
const PHONE_FACTOR := 2.0
## The design size the project stretches from.
const DESIGN := Vector2(1920.0, 1080.0)


static func is_phone(window_size: Vector2i) -> bool:
	return mini(window_size.x, window_size.y) < PHONE_SHORT_SIDE


## The `content_scale_factor` for a window: the player's UI scale, times the phone factor.
static func factor(window_size: Vector2i, ui_scale: float) -> float:
	return ui_scale * (PHONE_FACTOR if is_phone(window_size) else 1.0)


## Real pixels in one design unit at this window and factor (the base stretch, `expand` aspect).
static func pixels_per_unit(window_size: Vector2i, scale_factor: float) -> float:
	var base := minf(float(window_size.x) / DESIGN.x, float(window_size.y) / DESIGN.y)
	return base * scale_factor
