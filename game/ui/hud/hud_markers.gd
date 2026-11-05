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
## Steps of a canvas unit a marker's place is told apart in: a marker follows the world, so the
## state holds a new float place nearly every frame, and the part is drawn when the picture would
## change by a quarter of a unit (a quarter of a pixel at 1080p), not when a float does (#948).
const PLACE_STEPS := 4.0

## Where each marker is drawn on the last frame: {id: {"at": Vector2, "pinned": bool}}.
var placed: Dictionary = {}
## Where each ally's tag (icon, level, name and what follows) was drawn on the last frame, canvas
## units: {id: Rect2}. Every tag stays inside the screen.
var tags: Dictionary = {}
## The parts of a tag with a level, as laid out, for tests and captures (a tag with no level has
## none): {id: {"icon": Rect2, "level": Rect2, "name": Rect2}}.
var tag_parts: Dictionary = {}

## What the last draw was made from (`_key`).
var _drawn_key: Array = []
## What a draw collects: every marker's shapes, their smoothed rings [centre, radius, from, to,
## colour, width] and their words [font, place, text, colour].
var _shapes := HudShapes.new()
var _rings: Array[Array] = []
var _words: Array[Array] = []
## The level icons of a draw [rect, region of the atlas]: all of them before any word.
var _icons: Array[Array] = []


func _ready() -> void:
	resized.connect(queue_redraw)
	texture_filter = LevelIcons.FILTER


func topics() -> Array[StringName]:
	return [HudState.MARKERS]


func refresh() -> void:
	var key := _key()
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


## Everything `_draw` reads, as the picture tells it apart: the screen, where each marker stands in
## quarter units, how far it says it is in whole metres, its words and its state.
func _key() -> Array:
	var key: Array = [size]
	if state == null:
		return key
	var spots := _place_all()
	for marker in state.markers:
		var spot: Dictionary = spots.get(marker["id"], {})
		if spot.is_empty():
			continue
		var at: Vector2 = spot["at"]
		(
			key
			. append(
				[
					marker["id"],
					marker["kind"],
					roundi(at.x * PLACE_STEPS),
					roundi(at.y * PLACE_STEPS),
					spot["pinned"],
					roundi(float(marker.get("distance", 0.0))),
					str(marker.get("label", "")),
					bool(marker.get("downed", false)),
					bool(marker.get("dead", false)),
					int(marker.get("level", 0)),
					int(marker.get("icon", 0)),
					int(marker.get("bleed", 0)),
					roundi(float(marker.get("revive", 0.0)) * 100.0),
				]
			)
		)
	return key


func marker_at(id: StringName) -> Dictionary:
	return _place_all().get(id, {})


func _draw() -> void:
	placed = _place_all()
	var font := tokens.text_font(tokens.embolden_display * 0.3, 1.0)
	# All the markers' shapes are one command, then the smoothed rings, then all their words (the
	# outlines, then the letters: two commands, not two a marker): a marker's words can go over
	# another marker's shape that stands under them (#948).
	_shapes = HudShapes.new()
	_rings.clear()
	_words.clear()
	_icons.clear()
	tags.clear()
	tag_parts.clear()
	for marker in state.markers:
		var spot: Dictionary = placed.get(marker["id"], {})
		if spot.is_empty():
			continue
		if marker["kind"] == &"ally":
			_draw_ally(font, marker, spot["at"])
		else:
			_draw_objective(font, marker, spot)
	_shapes.flush(self)
	for ring: Array in _rings:
		draw_arc(ring[0], ring[1], ring[2], ring[3], 32, ring[4], ring[5], true)
	if not _icons.is_empty():
		var atlas := LevelIcons.atlas()
		for icon: Array in _icons:
			draw_texture_rect_region(atlas, icon[0], icon[1])
	for word: Array in _words:
		draw_string_outline(
			word[0], word[1], word[2], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 7, tokens.shadow
		)
	for word: Array in _words:
		draw_string(word[0], word[1], word[2], HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, word[3])


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
	_shapes.polygon(
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
	_shapes.polygon(diamond, tokens.accent_bright)
	var inner := half * 0.45
	_shapes.rect(Rect2(at - Vector2.ONE * inner * 0.5, Vector2.ONE * inner), tokens.ink_on_accent)
	if spot["pinned"]:
		var direction := (at - size * 0.5).normalized()
		var tip := at + direction * (half + ARROW + 6.0)
		var side := direction.orthogonal() * ARROW * 0.6
		_shapes.polygon(
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
	_shapes.polygon(
		PackedVector2Array([tip + Vector2(0, 14), tip + Vector2(-10, 0), tip + Vector2(10, 0)]),
		tokens.accent
	)
	_tag(font, marker, tip + Vector2(0.0, -10.0), tokens.accent_bright, "")


## A teammate on the ground: a red marker with their name and the seconds they have left, and a ring
## that fills while somebody holds the revive on them. Bled out, it says so and carries no clock.
func _draw_downed(font: Font, marker: Dictionary, at: Vector2) -> void:
	var dead := bool(marker.get("dead", false))
	var colour := tokens.ink_muted if dead else tokens.danger
	_shapes.circle(at, DOWNED_RADIUS + 4.0, Color(tokens.shadow, 0.6))
	_rings.append([at, DOWNED_RADIUS, 0.0, TAU, Color(colour, 0.35), DOWNED_WIDTH])
	var progress := float(marker.get("revive", 0.0))
	if progress > 0.0:
		_rings.append(
			[
				at,
				DOWNED_RADIUS,
				-PI * 0.5,
				-PI * 0.5 + TAU * clampf(progress, 0.0, 1.0),
				tokens.accent_bright,
				DOWNED_WIDTH
			]
		)
	elif not dead:
		_rings.append([at, DOWNED_RADIUS, -PI * 0.5, PI * 1.5, colour, DOWNED_WIDTH * 0.5])
	# A cross, the mark of someone who needs a hand.
	var arm := DOWNED_RADIUS * 0.45
	_shapes.line(at + Vector2(-arm, 0.0), at + Vector2(arm, 0.0), colour, 4.0)
	_shapes.line(at + Vector2(0.0, -arm), at + Vector2(0.0, arm), colour, 4.0)
	var tail := "  DEAD" if dead else "  %d S" % int(marker.get("bleed", 0))
	_tag(font, marker, at + Vector2(0.0, -DOWNED_RADIUS - 10.0), colour, tail)


## A teammate's tag, centred on `baseline_centre`: the icon, the level right beside it and then the
## name, in the order and with the gaps of `LevelTag`, when the marker has a level (0 for none: a
## bot, or the viewer turned levels off), else the name alone as it always was, centred the same
## way; `tail` follows the name (the clock of a body on the ground). The whole tag is kept inside
## the screen like any other text, and its place is told in `tags` and `tag_parts`.
func _tag(
	font: Font, marker: Dictionary, baseline_centre: Vector2, colour: Color, tail: String
) -> void:
	var who := str(marker.get("label", "")).to_upper()
	var level := int(marker.get("level", 0))
	if level < 1:
		_text(font, who + tail, baseline_centre, colour)
		tags[marker["id"]] = _words_rect(font, who + tail, baseline_centre)
		return
	var level_text := str(level)
	var name_width := _width(font, who + tail)
	var level_width := _width(font, level_text)
	var total := LevelTag.taken(level_width) + name_width
	var left := clampf(
		baseline_centre.x - total * 0.5,
		TEXT_MARGIN,
		maxf(size.x - TEXT_MARGIN - total, TEXT_MARGIN)
	)
	# The icon's body is centred on the digits' ink, as the font draws them on this baseline.
	var icon_level := int(marker.get("icon", level))
	var icon_top := LevelTag.icon_top(
		LevelTag.digits_centre(font, LABEL_SIZE, baseline_centre.y), icon_level
	)
	var icon := Rect2(left, icon_top, LevelTag.ICON, LevelTag.ICON)
	_icons.append([icon, LevelIcons.region(icon_level)])
	var level_at := icon.end.x + LevelTag.ICON_GAP
	var name_at := level_at + level_width + LevelTag.NAME_GAP
	_words.append([font, Vector2(level_at, baseline_centre.y), level_text, tokens.ink])
	_words.append([font, Vector2(name_at, baseline_centre.y), who + tail, colour])
	var top := minf(icon_top, baseline_centre.y - LABEL_SIZE)
	tags[marker["id"]] = Rect2(left, top, total, maxf(LevelTag.ICON, LABEL_SIZE))
	tag_parts[marker["id"]] = {
		"icon": icon,
		"level": Rect2(level_at, baseline_centre.y - LABEL_SIZE, level_width, LABEL_SIZE),
		"name": Rect2(name_at, baseline_centre.y - LABEL_SIZE, name_width, LABEL_SIZE),
	}


func _width(font: Font, text: String) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x


## Where `_text` puts `text`: the box of its letters.
func _words_rect(font: Font, text: String, baseline_centre: Vector2) -> Rect2:
	var width := _width(font, text)
	var left := clampf(
		baseline_centre.x - width * 0.5,
		TEXT_MARGIN,
		maxf(size.x - TEXT_MARGIN - width, TEXT_MARGIN)
	)
	return Rect2(left, baseline_centre.y - LABEL_SIZE, width, LABEL_SIZE)


## Centred text with a dark outline, so it holds on a lit or dark ground: kept for the end of the
## draw.
func _text(font: Font, text: String, baseline_centre: Vector2, colour: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	var at := baseline_centre - Vector2(width * 0.5, 0.0)
	at.x = clampf(at.x, TEXT_MARGIN, maxf(size.x - TEXT_MARGIN - width, TEXT_MARGIN))
	_words.append([font, at, text, colour])
