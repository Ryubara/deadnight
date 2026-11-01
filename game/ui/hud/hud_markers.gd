class_name HudMarkers
extends HudPart
## World markers drawn over the view: objective diamonds with their distance, shrinking with it, and
## teammates' names that stay readable at any range. The important marker that is off-screen is
## pinned to the screen edge with an arrow; the others only show while on screen. Fills the HUD.
## The client projects each marker to screen space; this part never sees a game object.

## Diamond half-size at point blank and far away, and the distance where it stops shrinking.
const DIAMOND_NEAR := 24.0
const DIAMOND_FAR := 13.0
const FAR_METRES := 60.0
const EDGE_INSET := 90.0
const ARROW := 16.0
const LABEL_SIZE := HudStyle.MIN_TEXT

## Where each marker is drawn on the last frame: {id: {"at": Vector2, "pinned": bool}}.
var placed: Dictionary = {}


func _ready() -> void:
	resized.connect(queue_redraw)


func topics() -> Array[StringName]:
	return [HudState.MARKERS]


func refresh() -> void:
	queue_redraw()


func marker_at(id: StringName) -> Dictionary:
	return _place_all().get(id, {})


func _draw() -> void:
	placed = _place_all()
	var font := tokens.text_font(tokens.embolden_display * 0.3, 1.0)
	for marker in state.markers:
		var spot: Dictionary = placed.get(marker["id"], {})
		if spot.is_empty():
			continue
		if marker["kind"] == &"ally":
			_draw_ally(font, marker, spot["at"])
		else:
			_draw_objective(font, marker, spot)


func _place_all() -> Dictionary:
	var out := {}
	if state == null:
		return out
	for marker in state.markers:
		var norm := Vector2(float(marker["x"]), float(marker["y"]))
		var on_screen := Rect2(0.0, 0.0, 1.0, 1.0).has_point(norm)
		var at := norm * size
		if on_screen:
			out[marker["id"]] = {"at": at, "pinned": false}
		elif bool(marker.get("important", false)):
			out[marker["id"]] = {"at": _pin(at), "pinned": true}
	return out


## The edge point toward `at` from the screen centre, inset so the marker stays whole.
func _pin(at: Vector2) -> Vector2:
	var centre := size * 0.5
	var half := centre - Vector2.ONE * EDGE_INSET
	var offset := at - centre
	if offset == Vector2.ZERO:
		return centre
	var scale_to_edge := minf(
		half.x / maxf(absf(offset.x), 0.001), half.y / maxf(absf(offset.y), 0.001)
	)
	return centre + offset * scale_to_edge


func _draw_objective(font: Font, marker: Dictionary, spot: Dictionary) -> void:
	var at: Vector2 = spot["at"]
	var t := clampf(float(marker["distance"]) / FAR_METRES, 0.0, 1.0)
	var half := lerpf(DIAMOND_NEAR, DIAMOND_FAR, t)
	var diamond := PackedVector2Array(
		[
			at + Vector2(0, -half),
			at + Vector2(half, 0),
			at + Vector2(0, half),
			at + Vector2(-half, 0)
		]
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				diamond[0] + Vector2(3, 3),
				diamond[1] + Vector2(3, 3),
				diamond[2] + Vector2(3, 3),
				diamond[3] + Vector2(3, 3)
			]
		),
		tokens.shadow
	)
	draw_colored_polygon(diamond, tokens.accent_bright)
	var inner := half * 0.45
	draw_rect(Rect2(at - Vector2.ONE * inner * 0.5, Vector2.ONE * inner), tokens.ink_on_accent)
	if spot["pinned"]:
		var direction := (at - size * 0.5).normalized()
		var tip := at + direction * (half + ARROW + 6.0)
		var side := direction.orthogonal() * ARROW * 0.6
		draw_colored_polygon(
			PackedVector2Array(
				[tip, at + direction * (half + 6.0) + side, at + direction * (half + 6.0) - side]
			),
			tokens.accent_bright
		)
	var text := "%d m" % roundi(float(marker["distance"]))
	if str(marker.get("label", "")) != "":
		text = "%s  %s" % [str(marker["label"]).to_upper(), text]
	_text(font, text, at + Vector2(0.0, half + LABEL_SIZE + 8.0), tokens.ink)


func _draw_ally(font: Font, marker: Dictionary, at: Vector2) -> void:
	var tip := at + Vector2(0.0, -10.0)
	draw_colored_polygon(
		PackedVector2Array([tip + Vector2(0, 14), tip + Vector2(-10, 0), tip + Vector2(10, 0)]),
		tokens.accent
	)
	_text(
		font,
		str(marker.get("label", "")).to_upper(),
		tip + Vector2(0.0, -10.0),
		tokens.accent_bright
	)


## Centred text with a dark outline, so it holds on a lit or dark ground.
func _text(font: Font, text: String, baseline_centre: Vector2, colour: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	var at := baseline_centre - Vector2(width * 0.5, 0.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 7, tokens.shadow)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, colour)
