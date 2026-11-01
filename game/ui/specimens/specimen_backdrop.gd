class_name SpecimenBackdrop
extends Control
## The mock main menu's night: a dark sky with a seeded scatter of stars, the glow of a distant
## screen, and a lot of parked car silhouettes along the bottom. Colours come from the UI tokens.

const STAR_COUNT := 140
const SEED := 1958
const HORIZON := 0.84
const CAR_COUNT := 11

var _tokens := UITokens.active()


func _draw() -> void:
	var size_px := get_rect().size
	var horizon := size_px.y * HORIZON
	# Sky: darkest at the top, lifting toward the horizon.
	var steps := 48
	for i in steps:
		var t := float(i) / float(steps - 1)
		var band := Rect2(0.0, horizon * float(i) / steps, size_px.x, horizon / steps + 1.0)
		draw_rect(band, _tokens.bg.lerp(_tokens.bg_glow, t * t))
	# The screen's glow, low on the right.
	var glow_centre := Vector2(size_px.x * 0.78, horizon)
	for ring in 14:
		var r := 120.0 + ring * 58.0
		var a := 0.05 * (1.0 - float(ring) / 14.0)
		draw_circle(glow_centre, r, Color(_tokens.accent, a))
	# Stars.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in STAR_COUNT:
		var p := Vector2(rng.randf() * size_px.x, rng.randf() * horizon * 0.8)
		var a := rng.randf_range(0.15, 0.7)
		draw_circle(p, rng.randf_range(0.8, 1.8), Color(_tokens.ink, a))
	# Ground and cars.
	draw_rect(Rect2(0.0, horizon, size_px.x, size_px.y - horizon), Color(0.02, 0.018, 0.03))
	var x := -40.0
	for i in CAR_COUNT:
		var w := rng.randf_range(150.0, 210.0)
		_draw_car(Vector2(x, horizon + 6.0), w, rng.randf_range(34.0, 52.0))
		x += w + rng.randf_range(30.0, 90.0)
	# Vignette.
	for i in 10:
		var inset := float(i) * 26.0
		draw_rect(
			Rect2(inset, inset, size_px.x - inset * 2.0, size_px.y - inset * 2.0),
			Color(0, 0, 0, 0.05),
			false,
			28.0
		)


func _draw_car(origin: Vector2, w: float, h: float) -> void:
	var body := Color(0.035, 0.03, 0.05)
	draw_rect(Rect2(origin.x, origin.y - h * 0.5, w, h * 0.5), body)
	var cabin := PackedVector2Array(
		[
			Vector2(origin.x + w * 0.22, origin.y - h * 0.5),
			Vector2(origin.x + w * 0.32, origin.y - h),
			Vector2(origin.x + w * 0.68, origin.y - h),
			Vector2(origin.x + w * 0.80, origin.y - h * 0.5),
		]
	)
	draw_colored_polygon(cabin, body)
