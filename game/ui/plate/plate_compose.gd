class_name PlateCompose
extends RefCounted
## Composes a calling card and an emblem from the shared parts (`PlateMotifs`): a card is a ground,
## a slanted band with a row of bulbs, a few stripes and one large motif on its `side`; an emblem is
## a badge of its `shape` with one motif inside. Both come out as shapes in role colours
## (`PlateShapes`) in their own design space, which the art controls scale to wherever they sit.

## The card's design size (a 440 by 120 sheet) and the emblem's (a square).
const CARD_SIZE := Vector2(440.0, 120.0)
const EMBLEM_SIZE := Vector2(100.0, 100.0)
## The motif's side on a card, how far it sits from the card's edge and from its top.
const MOTIF_SIZE := 78.0
const MOTIF_EDGE := 34.0
const MOTIF_TOP := 8.0
## The band along the bottom of a card, where the title is printed.
const BAND_TOP := 90.0
## The bulbs along the top of a card.
const BULB_COUNT := 20
const BULB_RADIUS := 3.4
## The share of an emblem's badge the motif fills.
const EMBLEM_MOTIF := 0.58


## The shapes of a card, back to front. `motif_at` is the share of the card's width its motif is
## centred on, or negative to put it on the piece's own `side`.
static func card(piece: Dictionary, motif_at := -1.0) -> Array[Dictionary]:
	var right := String(piece.get("side", "right")) == "right"
	var at_x := CARD_SIZE.x - MOTIF_EDGE - MOTIF_SIZE if right else MOTIF_EDGE
	if motif_at >= 0.0:
		at_x = motif_at * CARD_SIZE.x - MOTIF_SIZE * 0.5
		right = at_x > CARD_SIZE.x * 0.5
	var out: Array[Dictionary] = [
		PlateShapes.rect(0, 0, CARD_SIZE.x, CARD_SIZE.y, PlateShapes.Role.GROUND),
		PlateShapes.rect(0, BAND_TOP, CARD_SIZE.x, CARD_SIZE.y - BAND_TOP, PlateShapes.Role.BASE),
		PlateShapes.rect(0, BAND_TOP - 4.0, CARD_SIZE.x, 4.0, PlateShapes.Role.LIGHT),
	]
	# Slanted stripes fill the half the motif is not on.
	var from := 24.0 if right else 150.0
	for i in 6:
		var x := from + i * 30.0
		out.append(
			PlateShapes.poly([x + 20, 24, x + 30, 24, x + 8, 80, x - 2, 80], PlateShapes.Role.DARK)
		)
	for i in BULB_COUNT:
		var x := 11.0 + i * (CARD_SIZE.x - 22.0) / float(BULB_COUNT - 1)
		out.append(PlateShapes.circle(Vector2(x, 9.0), BULB_RADIUS, PlateShapes.Role.LIGHT))
	var motif := PlateMotifs.shapes(StringName(piece.get("motif", "")))
	out.append_array(PlateShapes.placed(motif, Vector2(at_x, MOTIF_TOP + 8.0), MOTIF_SIZE / 100.0))
	return out


## Where the title is printed on a card, in the card's design space: the band along the bottom.
static func title_box(_piece: Dictionary) -> Rect2:
	return Rect2(18.0, BAND_TOP, CARD_SIZE.x - 36.0, CARD_SIZE.y - BAND_TOP)


## The shapes of an emblem, back to front.
static func emblem(piece: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match String(piece.get("shape", "disc")):
		"ticket":
			out.append(
				PlateShapes.poly(
					[4, 34, 18, 20, 96, 20, 96, 66, 82, 80, 4, 80], PlateShapes.Role.BASE
				)
			)
			out.append(
				PlateShapes.poly(
					[9, 36, 20, 25, 91, 25, 91, 64, 80, 75, 9, 75], PlateShapes.Role.GROUND
				)
			)
		"hex":
			out.append(PlateShapes.shape(_hexagon(48.0), PlateShapes.Role.BASE))
			out.append(PlateShapes.shape(_hexagon(41.0), PlateShapes.Role.GROUND))
		_:
			out.append(PlateShapes.circle(Vector2(50, 50), 48.0, PlateShapes.Role.BASE))
			out.append(PlateShapes.circle(Vector2(50, 50), 41.0, PlateShapes.Role.GROUND))
	var motif := PlateMotifs.shapes(StringName(piece.get("motif", "")))
	var wide := String(piece.get("shape", "disc")) == "ticket"
	var factor := EMBLEM_MOTIF * (0.8 if wide else 1.0)
	var offset := Vector2(50.0, 50.0) - Vector2.ONE * 50.0 * factor
	out.append_array(PlateShapes.placed(motif, offset, factor))
	return out


static func _hexagon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := TAU * float(i) / 6.0 - PI * 0.5
		points.append(Vector2(50, 50) + Vector2(cos(angle), sin(angle)) * radius)
	return points
