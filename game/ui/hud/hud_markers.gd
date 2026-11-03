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
## What a marker pinned to an edge keeps clear of: the side columns (along the top and the bottom
## edge), and the round card above and the health and ammo cards below (along a side edge).
const SIDE_CLEAR := HudStyle.MARGIN + HudStyle.COLUMN + 48.0
const TOP_CLEAR := 260.0
const BOTTOM_CLEAR := 390.0
const ARROW := 16.0
## The ring of a teammate on the ground.
const DOWNED_RADIUS := 22.0
const DOWNED_WIDTH := 6.0
## Text stays this far inside the screen.
const TEXT_MARGIN := 12.0
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


## The edge point toward `at` from the screen centre, inset so the marker stays whole, and slid
## along that edge out of the corners, where the HUD's cards stand.
func _pin(at: Vector2) -> Vector2:
	var centre := size * 0.5
	var half := centre - Vector2.ONE * EDGE_INSET
	var offset := at - centre
	if offset == Vector2.ZERO:
		return centre
	var across_x := half.x / maxf(absf(offset.x), 0.001)
	var across_y := half.y / maxf(absf(offset.y), 0.001)
	var pinned := centre + offset * minf(across_x, across_y)
	if across_x < across_y:
		pinned.y = clampf(
			pinned.y, minf(TOP_CLEAR, centre.y), maxf(size.y - BOTTOM_CLEAR, centre.y)
		)
	else:
		pinned.x = clampf(pinned.x, minf(SIDE_CLEAR, centre.x), maxf(size.x - SIDE_CLEAR, centre.x))
	return pinned


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
	_fill(
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
	_fill(diamond, tokens.accent_bright)
	var inner := half * 0.45
	draw_rect(Rect2(at - Vector2.ONE * inner * 0.5, Vector2.ONE * inner), tokens.ink_on_accent)
	if spot["pinned"]:
		var direction := (at - size * 0.5).normalized()
		var tip := at + direction * (half + ARROW + 6.0)
		var side := direction.orthogonal() * ARROW * 0.6
		_fill(
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
	if bool(marker.get("downed", false)):
		_draw_downed(font, marker, at)
		return
	var tip := at + Vector2(0.0, -10.0)
	_fill(
		PackedVector2Array([tip + Vector2(0, 14), tip + Vector2(-10, 0), tip + Vector2(10, 0)]),
		tokens.accent
	)
	_text(
		font,
		str(marker.get("label", "")).to_upper(),
		tip + Vector2(0.0, -10.0),
		tokens.accent_bright
	)


## A teammate on the ground: a red marker with their name and the seconds they have left, and a ring
## that fills while somebody holds the revive on them. Bled out, it says so and carries no clock.
func _draw_downed(font: Font, marker: Dictionary, at: Vector2) -> void:
	var dead := bool(marker.get("dead", false))
	var colour := tokens.ink_muted if dead else tokens.danger
	draw_circle(at, DOWNED_RADIUS + 4.0, Color(tokens.shadow, 0.6))
	draw_arc(at, DOWNED_RADIUS, 0.0, TAU, 32, Color(colour, 0.35), DOWNED_WIDTH, true)
	var progress := float(marker.get("revive", 0.0))
	if progress > 0.0:
		draw_arc(
			at,
			DOWNED_RADIUS,
			-PI * 0.5,
			-PI * 0.5 + TAU * clampf(progress, 0.0, 1.0),
			32,
			tokens.accent_bright,
			DOWNED_WIDTH,
			true
		)
	elif not dead:
		draw_arc(at, DOWNED_RADIUS, -PI * 0.5, PI * 1.5, 32, colour, DOWNED_WIDTH * 0.5, true)
	# A cross, the mark of someone who needs a hand.
	var arm := DOWNED_RADIUS * 0.45
	draw_line(at + Vector2(-arm, 0.0), at + Vector2(arm, 0.0), colour, 4.0)
	draw_line(at + Vector2(0.0, -arm), at + Vector2(0.0, arm), colour, 4.0)
	var words := str(marker.get("label", "")).to_upper()
	if dead:
		words += "  DEAD"
	else:
		words += "  %d S" % int(marker.get("bleed", 0))
	_text(font, words, at + Vector2(0.0, -DOWNED_RADIUS - 10.0), colour)


## A flat triangle or quad. Not `draw_colored_polygon`: the markers move with the camera and are
## drawn again every frame, and a polygon makes the Compatibility renderer build a vertex array and
## buffers each time, whose WebGL ids the web page keeps for good (#883). A primitive is batched
## with the rest and makes none.
func _fill(points: PackedVector2Array, colour: Color) -> void:
	var colours := PackedColorArray()
	colours.resize(points.size())
	colours.fill(colour)
	draw_primitive(points, colours, PackedVector2Array())


## Centred text with a dark outline, so it holds on a lit or dark ground.
func _text(font: Font, text: String, baseline_centre: Vector2, colour: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	var at := baseline_centre - Vector2(width * 0.5, 0.0)
	at.x = clampf(at.x, TEXT_MARGIN, maxf(size.x - TEXT_MARGIN - width, TEXT_MARGIN))
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 7, tokens.shadow)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, colour)
