class_name PlateFrames
extends RefCounted
## Composes a plate frame (#1071) from a few shared parts, as `PlateCompose` does a card: a frame is
## a border run just inside any outline (a player's ticket-shaped box, a roster row, a swatch), in
## the four colours of its palette (`PlatePalettes`) and the `style` its piece names. Seven pieces
## are a handful of styles and a palette each, so another frame is a line of `plate_pieces.json`.
##
## Every style stays inside the outline, so a frame never changes where anything sits; the thickest
## is `THICKNESS` times the stroke width. The result is a list of ops in the outline's own
## coordinates, back to front, which `FrameArt` and `PlateDraw` draw as one command (`HudShapes`):
## `{"k": "line", "p": points, "w": width, "c": colour}` (a closed ring repeats its first point) and
## `{"k": "poly", "p": points, "c": colour}`.

const DOUBLE := &"double"
const RIVETS := &"rivets"
const GLOW := &"glow"
const BULBS := &"bulbs"
const HOLES := &"holes"
const ROPE := &"rope"
const STYLES: Array[StringName] = [DOUBLE, RIVETS, GLOW, BULBS, HOLES, ROPE]

## The stroke width of a frame on a plate `height` units high, never thinner than 2 or fatter than 5
## (a compact box of 32 units gets 2, a roster row of 46 gets 3, your own box of 66 gets 5).
const WIDTH_SHARE := 0.085
const WIDTH_MIN := 2.0
const WIDTH_MAX := 5.0
## The most a frame takes from the edge, in strokes (the halo of the glow, the thick bars).
const THICKNESS := 2.2
## A frame's thin dark edge, in strokes, which separates it from the art behind it.
const EDGE := 0.25
## Corners of a bulb or a rivet: enough to look round at the size they are drawn.
const DOT_CORNERS := 8


static func has(style: StringName) -> bool:
	return STYLES.has(style)


## The stroke width for a plate `height` units high.
static func width_for(height: float) -> float:
	return clampf(floorf(height * WIDTH_SHARE), WIDTH_MIN, WIDTH_MAX)


## The ops of a frame of `style` in `palette` run just inside `outline` (a closed polygon, no
## repeated point), `width` thick. A style nobody has draws the plain double border.
static func build(
	style: StringName, palette: StringName, outline: PackedVector2Array, width: float
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if outline.size() < 3 or width <= 0.0:
		return out
	match style:
		RIVETS:
			_rivets(out, palette, outline, width)
		GLOW:
			_glow(out, palette, outline, width)
		BULBS:
			_bulbs(out, palette, outline, width)
		HOLES:
			_holes(out, palette, outline, width)
		ROPE:
			_rope(out, palette, outline, width)
		_:
			_double(out, palette, outline, width)
	return out


## The rectangle of a size as an outline.
static func rect_outline(area: Rect2) -> PackedVector2Array:
	return PackedVector2Array(
		[
			area.position,
			Vector2(area.end.x, area.position.y),
			area.end,
			Vector2(area.position.x, area.end.y)
		]
	)


static func _colour(palette: StringName, role: PlateShapes.Role, alpha := 1.0) -> Color:
	var found := PlatePalettes.colour(palette, role)
	return Color(found, alpha)


## Chrome and the velvet rope: a bar, then a fine line of light inside it.
static func _double(
	out: Array[Dictionary], palette: StringName, outline: PackedVector2Array, width: float
) -> void:
	_edge(out, palette, outline, width)
	var start := width * EDGE
	_band(out, outline, start, width, _colour(palette, PlateShapes.Role.BASE))
	var fine := maxf(1.0, width * 0.35)
	_band(out, outline, start + width + 1.0, fine, _colour(palette, PlateShapes.Role.LIGHT))


## Brass: a thick bar with a row of rivets along its middle.
static func _rivets(
	out: Array[Dictionary], palette: StringName, outline: PackedVector2Array, width: float
) -> void:
	_edge(out, palette, outline, width)
	var start := width * EDGE
	var bar := width * 1.7
	_band(out, outline, start, bar, _colour(palette, PlateShapes.Role.BASE))
	var middle := _inset(outline, start + bar * 0.5)
	var shade := _colour(palette, PlateShapes.Role.DARK)
	var rivet := _colour(palette, PlateShapes.Role.LIGHT)
	for at in _spaced(middle, width * 3.4):
		out.append({"k": "poly", "p": _dot(at["at"], width * 0.46), "c": shade})
		out.append({"k": "poly", "p": _dot(at["at"], width * 0.34), "c": rivet})


## Neon and the searchlight: a soft halo, a brighter band and a hot core.
static func _glow(
	out: Array[Dictionary], palette: StringName, outline: PackedVector2Array, width: float
) -> void:
	var base := PlateShapes.Role.BASE
	_band(out, outline, 0.0, width * 2.2, _colour(palette, base, 0.16))
	_band(out, outline, 0.0, width * 1.5, _colour(palette, base, 0.32))
	_band(out, outline, width * 0.25, width * 1.0, _colour(palette, base))
	_band(out, outline, width * 0.5, width * 0.5, _colour(palette, PlateShapes.Role.LIGHT))


## Gold: a dark bar of marquee bulbs.
static func _bulbs(
	out: Array[Dictionary], palette: StringName, outline: PackedVector2Array, width: float
) -> void:
	_edge(out, palette, outline, width)
	var start := width * EDGE
	var bar := width * 1.7
	_band(out, outline, start, bar, _colour(palette, PlateShapes.Role.GROUND))
	var middle := _inset(outline, start + bar * 0.5)
	var bulb := _colour(palette, PlateShapes.Role.LIGHT)
	for at in _spaced(middle, width * 2.6):
		out.append({"k": "poly", "p": _dot(at["at"], width * 0.5), "c": bulb})


## The filmstrip: a dark strip with the sprockets of a reel cut along it.
static func _holes(
	out: Array[Dictionary], palette: StringName, outline: PackedVector2Array, width: float
) -> void:
	_edge(out, palette, outline, width)
	var start := width * EDGE
	var bar := width * 1.8
	_band(out, outline, start, bar, _colour(palette, PlateShapes.Role.DARK))
	var middle := _inset(outline, start + bar * 0.5)
	var hole := _colour(palette, PlateShapes.Role.LIGHT)
	for at in _spaced(middle, width * 2.4):
		var along: Vector2 = at["along"] * width * 0.6
		out.append(
			{
				"k": "line",
				"p": PackedVector2Array([at["at"] - along, at["at"] + along]),
				"w": width * 0.7,
				"c": hole
			}
		)


## The velvet rope: a thick cord with the twist of its strands cut across it.
static func _rope(
	out: Array[Dictionary], palette: StringName, outline: PackedVector2Array, width: float
) -> void:
	_edge(out, palette, outline, width)
	var start := width * EDGE
	var bar := width * 1.8
	_band(out, outline, start, bar, _colour(palette, PlateShapes.Role.BASE))
	var middle := _inset(outline, start + bar * 0.5)
	var strand := _colour(palette, PlateShapes.Role.DARK)
	for at in _spaced(middle, width * 1.5):
		var across: Vector2 = (at["along"] as Vector2).rotated(PI * 0.3) * bar * 0.42
		out.append(
			{
				"k": "line",
				"p": PackedVector2Array([at["at"] - across, at["at"] + across]),
				"w": width * 0.4,
				"c": strand
			}
		)


## The thin dark edge round the outermost of the frame.
static func _edge(
	out: Array[Dictionary], palette: StringName, outline: PackedVector2Array, width: float
) -> void:
	_band(out, outline, 0.0, width * EDGE * 2.0, _colour(palette, PlateShapes.Role.DARK))


## A closed ring that covers `depth` to `depth + thickness` units inside the outline.
static func _band(
	out: Array[Dictionary],
	outline: PackedVector2Array,
	depth: float,
	thickness: float,
	colour: Color
) -> void:
	var ring := _inset(outline, depth + thickness * 0.5)
	ring.append(ring[0])
	out.append({"k": "line", "p": ring, "w": thickness, "c": colour})


## The outline moved `depth` inwards (what it was when it has no room for that).
static func _inset(outline: PackedVector2Array, depth: float) -> PackedVector2Array:
	var found := Geometry2D.offset_polygon(outline, -depth, Geometry2D.JOIN_MITER)
	if found.is_empty():
		return outline
	var best := found[0]
	for each in found:
		if each.size() > best.size():
			best = each
	return best


## Points round a closed ring, `step` apart: `[{at, along}]` with the direction of the line there.
static func _spaced(ring: PackedVector2Array, step: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var carried := step * 0.5
	for i in ring.size():
		var from := ring[i]
		var to := ring[(i + 1) % ring.size()]
		var length := from.distance_to(to)
		if length < 0.001:
			continue
		var along := (to - from) / length
		var at := carried
		while at < length:
			found.append({"at": from + along * at, "along": along})
			at += step
		carried = at - length
	return found


static func _dot(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in DOT_CORNERS:
		var angle := TAU * float(i) / float(DOT_CORNERS)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points
