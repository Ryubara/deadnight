class_name ItemIcons
extends RefCounted
## The base icon of every wearable, drawn as shapes on a 100 by 100 plate (no textures, so it is
## sharp at any size and nothing has to be held). The drawing language is the level icons' (#1060,
## docs/research/progression.md): flat colours, an ink outline, a few shapes.
##
##     ItemIcons.draw(self, Rect2(at, Vector2(96, 96)), &"torso", &"jacket", false)
##
## A locked item is the same drawing with its inner detail gone: one flat shape in the outline
## colour with the ink rim, the silhouette of the base icon (the maintainer decided a locked item
## shows `???` for its name and a silhouette for its icon). A wearable has one icon whoever the
## soldier is; a piece the art does not have yet is drawn the same, since the icon is all it
## gives (#1078).

const PLATE := 100.0
## The ink of the outline, and the flat colour of a locked silhouette (`UITokens.outline`).
const INK := Color("1c1730")
const SILHOUETTE := Color("3b3350")
## The line's width on the plate: the level icons' 4.5 at their 128.
const OUTLINE := 3.6
const DETAIL := 2.6
const OVAL_STEPS := 24

const CREAM := Color("efe4cb")
const WHITE := Color("f4f1ea")
const RED := Color("d6392f")
const MAROON := Color("7d2330")
const OLIVE := Color("6b7a3a")
const GREEN := Color("3c8a5a")
const NAVY := Color("2f4b7c")
const DENIM := Color("4f79a8")
const SKY := Color("6cc4e8")
const BROWN := Color("7a4e2d")
const TAN := Color("c8a572")
const GREY := Color("8a8f99")
const CHARCOAL := Color("3a3d46")
const BLACK := Color("24212b")
const GOLD := Color("e0a82e")
const YELLOW := Color("f2c744")
const PINK := Color("e88aa8")
const TEAL := Color("2f8f8f")

## The drawings by "<slot>/<id>": shapes in painter's order. Built on first use.
static var _drawings := {}


## Whether there is a drawing for the part `id` of `slot`.
static func has(slot: StringName, id: StringName) -> bool:
	return not _shapes_of(slot, id).is_empty()


## Draws the icon of `slot`/`id` fitted in `rect` on `canvas`: lit, or as a silhouette.
static func draw(
	canvas: CanvasItem, rect: Rect2, slot: StringName, id: StringName, locked: bool
) -> void:
	_paint(canvas, rect, _shapes_of(slot, id), locked)


## A costume: a figure in its colours (`skin`, `hair`, `main`, `second`, `trim`), or its silhouette.
static func draw_costume(
	canvas: CanvasItem, rect: Rect2, colours: Dictionary, locked: bool
) -> void:
	_paint(canvas, rect, _costume_shapes(colours), locked)


## A costume's own colours as three bands: the "Default" option. `alpha` fades it when there is no
## costume to restore.
static func draw_swatches(canvas: CanvasItem, rect: Rect2, colours: Array, alpha := 1.0) -> void:
	var shapes: Array = []
	for i in colours.size():
		var top := 14.0 + 72.0 * float(i) / colours.size()
		var bottom := 14.0 + 72.0 * float(i + 1) / colours.size()
		var colour: Color = colours[i]
		colour.a = alpha
		shapes.append(_shape([14, top, 86, top, 86, bottom, 14, bottom], colour))
	_paint(canvas, rect, shapes, false, alpha)


static func _paint(
	canvas: CanvasItem, rect: Rect2, shapes: Array, locked: bool, alpha := 1.0
) -> void:
	var side := minf(rect.size.x, rect.size.y)
	var unit := side / PLATE
	var origin := rect.position + (rect.size - Vector2.ONE * side) * 0.5
	var ink := Color(INK, alpha)
	if locked:
		# One flat shape: every outline first, a stroke twice as wide, then every fill over it.
		for shape: Dictionary in shapes:
			if shape.has("fill"):
				_outline(canvas, shape["points"], origin, unit, INK, OUTLINE * 2.0)
		for shape: Dictionary in shapes:
			if shape.has("fill"):
				canvas.draw_colored_polygon(_placed(shape["points"], origin, unit), SILHOUETTE)
		return
	for shape: Dictionary in shapes:
		if shape.has("fill"):
			canvas.draw_colored_polygon(_placed(shape["points"], origin, unit), shape["fill"])
			_outline(canvas, shape["points"], origin, unit, ink, OUTLINE)
		else:
			canvas.draw_polyline(
				_placed(shape["points"], origin, unit),
				shape["line"],
				float(shape["width"]) * unit,
				true
			)


## A colour as a paint chip: a rounded square with a shine, or its silhouette.
static func draw_chip(canvas: CanvasItem, rect: Rect2, colour: Color, locked: bool) -> void:
	var side := minf(rect.size.x, rect.size.y)
	var unit := side / PLATE
	var origin := rect.position + (rect.size - Vector2.ONE * side) * 0.5
	var chip := _placed(_rounded(12.0, 12.0, 76.0, 76.0, 14.0), origin, unit)
	if locked:
		_outline_placed(canvas, chip, INK, OUTLINE * 2.0 * unit)
		canvas.draw_colored_polygon(chip, SILHOUETTE)
		return
	canvas.draw_colored_polygon(chip, colour)
	_outline_placed(canvas, chip, INK, OUTLINE * unit)
	var shine := _placed(
		PackedVector2Array([Vector2(26, 28), Vector2(52, 28), Vector2(26, 54)]), origin, unit
	)
	canvas.draw_colored_polygon(shine, Color(1.0, 1.0, 1.0, 0.22))


## A slashed ring: the plain "None" of a slot that may be empty.
static func draw_none(canvas: CanvasItem, rect: Rect2, colour: Color) -> void:
	var side := minf(rect.size.x, rect.size.y)
	var unit := side / PLATE
	var centre := rect.get_center()
	canvas.draw_arc(centre, 30.0 * unit, 0.0, TAU, 32, colour, 5.0 * unit, true)
	canvas.draw_line(
		centre + Vector2(-21.0, 21.0) * unit,
		centre + Vector2(21.0, -21.0) * unit,
		colour,
		5.0 * unit,
		true
	)


static func _shapes_of(slot: StringName, id: StringName) -> Array:
	var key := "%s/%s" % [slot, id]
	if not _drawings.has(key):
		_drawings[key] = _build(slot, id)
	return _drawings[key]


static func _placed(points: PackedVector2Array, origin: Vector2, unit: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(origin + point * unit)
	return out


static func _outline(
	canvas: CanvasItem,
	points: PackedVector2Array,
	origin: Vector2,
	unit: float,
	colour: Color,
	width: float
) -> void:
	_outline_placed(canvas, _placed(points, origin, unit), colour, width * unit)


static func _outline_placed(
	canvas: CanvasItem, placed: PackedVector2Array, colour: Color, width: float
) -> void:
	var closed := placed.duplicate()
	closed.append(placed[0])
	canvas.draw_polyline(closed, colour, width, true)


# --- the drawings --------------------------------------------------------------------------------


static func _build(slot: StringName, id: StringName) -> Array:
	match slot:
		&"headwear":
			return _headwear(id)
		&"torso":
			return _torso(id)
		&"legs":
			return _legs(id)
		&"feet":
			return _feet(id)
		&"eyewear":
			return _eyewear(id)
		&"neck":
			return _neck(id)
	return []


static func _costume_shapes(colours: Dictionary) -> Array:
	var main: Color = colours.get("main", CREAM)
	var second: Color = colours.get("second", CHARCOAL)
	var trim: Color = colours.get("trim", GOLD)
	var skin: Color = colours.get("skin", TAN)
	var hair: Color = colours.get("hair", BROWN)
	return [
		_shape([32, 62, 68, 62, 72, 94, 54, 94, 50, 74, 46, 94, 28, 94], second),
		_shape(
			[34, 32, 66, 32, 88, 46, 80, 60, 70, 54, 70, 68, 30, 68, 30, 54, 20, 60, 12, 46], main
		),
		_shape([30, 62, 70, 62, 70, 68, 30, 68], trim),
		_shape([40, 32, 50, 44, 60, 32], trim),
		_shape(_oval(50, 18, 11, 12), skin),
		_shape(_oval(50, 15, 12, 11, PI, TAU), hair),
	]


static func _headwear(id: StringName) -> Array:
	match id:
		&"ballcap":
			return [
				_shape(_oval(50, 60, 30, 30, PI, TAU), RED),
				_shape([22, 60, 80, 60, 94, 68, 62, 72, 30, 68], RED.darkened(0.2)),
				_shape(_oval(50, 31, 4, 4), RED.lightened(0.2)),
			]
		&"papercap":
			return [
				_shape([12, 66, 88, 66, 72, 34, 28, 34], WHITE),
				_shape([12, 66, 88, 66, 86, 74, 14, 74], CREAM.darkened(0.12)),
				_line([28, 34, 50, 66, 72, 34], GREY),
			]
		&"pillbox":
			return [
				_shape([22, 70, 78, 70, 72, 36, 28, 36], MAROON),
				_shape(_rounded(22.0, 58.0, 56.0, 12.0, 4.0), GOLD),
				_shape([34, 76, 66, 76, 64, 84, 36, 84], BLACK),
			]
		&"helmet":
			return [
				_shape(_oval(50, 62, 34, 34, PI, TAU), OLIVE),
				_shape(_oval(50, 66, 44, 8), OLIVE.darkened(0.25)),
				_line([50, 28, 50, 60], OLIVE.lightened(0.25)),
			]
		&"ranger":
			return [
				_shape([32, 64, 36, 30, 64, 30, 68, 64], BROWN),
				_shape(_oval(50, 66, 44, 10), BROWN.darkened(0.15)),
				_shape([33, 56, 67, 56, 68, 64, 32, 64], TAN),
			]
		&"visor":
			return [
				_shape([16, 54, 84, 54, 80, 66, 20, 66], CHARCOAL),
				_shape([22, 62, 78, 62, 68, 84, 32, 84], GREEN.lightened(0.1)),
				_line([30, 70, 70, 70], WHITE),
			]
		&"creature":
			return [
				_shape(_oval(50, 52, 30, 36), GREEN),
				_shape(_oval(38, 46, 7, 9), YELLOW),
				_shape(_oval(62, 46, 7, 9), YELLOW),
				_shape([34, 68, 66, 68, 58, 78, 50, 70, 42, 78], BLACK),
			]
	return []


## A short-sleeved shirt's body, or a tank top's with straps.
static func _shirt(body: Color, strap: bool) -> Array:
	if strap:
		return [
			_shape([32, 14, 42, 14, 46, 28, 54, 28, 58, 14, 68, 14, 72, 86, 28, 86], body),
		]
	return [
		_shape(
			[34, 16, 66, 16, 90, 34, 80, 50, 72, 44, 72, 86, 28, 86, 28, 44, 20, 50, 10, 34], body
		)
	]


static func _torso(id: StringName) -> Array:
	match id:
		&"shirt":
			var shapes := _shirt(CREAM, false)
			shapes.append(_shape([40, 16, 50, 28, 60, 16], CREAM.darkened(0.25)))
			return shapes
		&"vest":
			return [
				_shape([30, 14, 42, 14, 50, 40, 58, 14, 70, 14, 76, 86, 24, 86], OLIVE),
				_shape([30, 62, 44, 62, 44, 74, 30, 74], OLIVE.darkened(0.25)),
				_shape([56, 62, 70, 62, 70, 74, 56, 74], OLIVE.darkened(0.25)),
				_line([50, 40, 50, 86], OLIVE.darkened(0.4)),
			]
		&"rolled":
			var shapes := _shirt(DENIM, false)
			shapes.append(_shape([10, 34, 20, 40, 18, 52, 10, 44], CREAM))
			shapes.append(_shape([90, 34, 80, 40, 82, 52, 90, 44], CREAM))
			shapes.append(_shape([40, 16, 50, 30, 60, 16], CREAM))
			return shapes
		&"jacket":
			return [
				_shape(
					[
						34,
						14,
						66,
						14,
						88,
						30,
						90,
						80,
						74,
						80,
						72,
						46,
						72,
						88,
						28,
						88,
						28,
						46,
						26,
						80,
						10,
						80,
						12,
						30
					],
					CHARCOAL
				),
				_shape([38, 14, 50, 44, 62, 14, 66, 14, 50, 52, 34, 14], BLACK),
				_line([50, 44, 50, 88], GREY),
			]
		&"tank":
			return _shirt(PINK.darkened(0.1), true)
		&"letterman":
			return [
				_shape(
					[
						34,
						14,
						66,
						14,
						88,
						30,
						90,
						80,
						74,
						80,
						72,
						46,
						72,
						88,
						28,
						88,
						28,
						46,
						26,
						80,
						10,
						80,
						12,
						30
					],
					RED
				),
				_shape([66, 14, 88, 30, 90, 80, 74, 80, 72, 46], CREAM),
				_shape([34, 14, 12, 30, 10, 80, 26, 80, 28, 46], CREAM),
				_shape(_oval(40, 50, 7, 8), CREAM),
				_line([50, 28, 50, 88], MAROON),
			]
		&"usher":
			return [
				_shape(
					[
						34,
						14,
						66,
						14,
						88,
						30,
						90,
						80,
						74,
						80,
						72,
						46,
						72,
						88,
						28,
						88,
						28,
						46,
						26,
						80,
						10,
						80,
						12,
						30
					],
					MAROON
				),
				_shape([30, 14, 46, 14, 40, 22, 30, 22], GOLD),
				_shape([54, 14, 70, 14, 70, 22, 60, 22], GOLD),
				_shape(_oval(42, 48, 3.5, 3.5), GOLD),
				_shape(_oval(42, 66, 3.5, 3.5), GOLD),
				_shape(_oval(58, 48, 3.5, 3.5), GOLD),
				_shape(_oval(58, 66, 3.5, 3.5), GOLD),
			]
		&"coveralls":
			return [
				_shape(
					[
						34,
						14,
						66,
						14,
						88,
						30,
						90,
						70,
						76,
						70,
						72,
						46,
						72,
						90,
						56,
						90,
						50,
						62,
						44,
						90,
						28,
						90,
						28,
						46,
						24,
						70,
						10,
						70,
						12,
						30
					],
					TEAL
				),
				_line([50, 20, 50, 62], GREY),
				_shape([34, 46, 46, 46, 46, 58, 34, 58], TEAL.darkened(0.25)),
			]
		&"creature":
			var shapes := _shirt(WHITE, false)
			shapes.append(_shape(_oval(50, 54, 14, 16), GREEN))
			shapes.append(_shape(_oval(45, 50, 3, 4), YELLOW))
			shapes.append(_shape(_oval(55, 50, 3, 4), YELLOW))
			return shapes
		&"varsity":
			return [
				_shape(
					[
						34,
						14,
						66,
						14,
						88,
						30,
						90,
						80,
						74,
						80,
						72,
						46,
						72,
						88,
						28,
						88,
						28,
						46,
						26,
						80,
						10,
						80,
						12,
						30
					],
					GOLD
				),
				_shape([66, 14, 88, 30, 90, 80, 74, 80, 72, 46], BROWN),
				_shape([34, 14, 12, 30, 10, 80, 26, 80, 28, 46], BROWN),
				_shape(_oval(40, 50, 7, 8), BROWN),
				_line([50, 28, 50, 88], BROWN),
			]
	return []


static func _legs(id: StringName) -> Array:
	match id:
		&"trousers":
			return [
				_shape(
					[28, 12, 72, 12, 78, 90, 55, 90, 50, 40, 45, 90, 22, 90], BROWN.lightened(0.1)
				),
				_shape([28, 12, 72, 12, 72, 22, 28, 22], BROWN.darkened(0.25)),
			]
		&"cuffed":
			return [
				_shape([28, 12, 72, 12, 78, 90, 55, 90, 50, 40, 45, 90, 22, 90], DENIM),
				_shape([28, 12, 72, 12, 72, 22, 28, 22], NAVY),
				_shape([22, 76, 45, 76, 45, 90, 22, 90], CREAM),
				_shape([55, 76, 78, 76, 78, 90, 55, 90], CREAM),
			]
		&"shorts":
			return [
				_shape([26, 20, 74, 20, 80, 62, 55, 62, 50, 44, 45, 62, 20, 62], TAN),
				_shape([26, 20, 74, 20, 74, 30, 26, 30], BROWN),
			]
		&"striped":
			return [
				_shape(
					[28, 12, 72, 12, 78, 90, 55, 90, 50, 40, 45, 90, 22, 90], NAVY.lightened(0.25)
				),
				_line([34, 22, 30, 88], WHITE),
				_line([66, 22, 70, 88], WHITE),
				_shape([28, 12, 72, 12, 72, 22, 28, 22], CHARCOAL),
			]
		&"overalls":
			return [
				_shape([28, 30, 72, 30, 78, 90, 55, 90, 50, 52, 45, 90, 22, 90], DENIM),
				_shape([36, 10, 64, 10, 64, 40, 36, 40], DENIM.darkened(0.1)),
				_line([36, 10, 34, 30], NAVY, 4.0),
				_line([64, 10, 66, 30], NAVY, 4.0),
				_shape(_oval(40, 36, 3, 3), GOLD),
				_shape(_oval(60, 36, 3, 3), GOLD),
			]
		&"swing":
			return [
				_shape(
					[36, 16, 64, 16, 92, 80, 80, 86, 66, 80, 50, 88, 34, 80, 20, 86, 8, 80], PINK
				),
				_shape([36, 16, 64, 16, 64, 26, 36, 26], MAROON),
				_line([44, 28, 30, 78], WHITE),
				_line([56, 28, 70, 78], WHITE),
			]
	return []


static func _feet(id: StringName) -> Array:
	match id:
		&"sneakers":
			return [
				_shape([10, 70, 12, 42, 34, 40, 48, 54, 74, 58, 90, 70, 90, 80, 10, 80], WHITE),
				_shape([10, 74, 90, 74, 90, 84, 10, 84], RED),
				_line([30, 48, 40, 54], GREY),
				_line([36, 44, 46, 52], GREY),
			]
		&"shoes":
			return [
				_shape(
					[12, 66, 14, 44, 36, 42, 48, 56, 76, 60, 90, 70, 90, 78, 12, 78],
					NAVY.lightened(0.2)
				),
				_shape([12, 78, 90, 78, 90, 84, 12, 84], CHARCOAL),
				_shape([12, 70, 24, 70, 24, 84, 12, 84], CHARCOAL),
			]
		&"boots":
			return [
				_shape([24, 12, 54, 12, 56, 56, 86, 66, 90, 82, 22, 82], BROWN),
				_shape([22, 78, 90, 78, 90, 86, 22, 86], BLACK),
				_shape([24, 12, 54, 12, 54, 22, 24, 22], TAN),
			]
		&"saddle":
			return [
				_shape([12, 66, 14, 44, 36, 42, 48, 56, 76, 60, 90, 70, 90, 78, 12, 78], WHITE),
				_shape([34, 56, 58, 56, 66, 70, 34, 70], BROWN),
				_shape([12, 78, 90, 78, 90, 84, 12, 84], BROWN.darkened(0.3)),
			]
		&"skates":
			return [
				_shape([10, 62, 12, 36, 34, 34, 48, 48, 74, 52, 90, 62, 90, 72, 10, 72], PINK),
				_shape([10, 72, 90, 72, 90, 76, 10, 76], CHARCOAL),
				_shape(_oval(22, 84, 7, 7), YELLOW),
				_shape(_oval(40, 84, 7, 7), YELLOW),
				_shape(_oval(64, 84, 7, 7), YELLOW),
				_shape(_oval(82, 84, 7, 7), YELLOW),
			]
		&"rubber":
			return [
				_shape([24, 10, 54, 10, 56, 56, 86, 66, 90, 82, 22, 82], YELLOW),
				_shape([22, 78, 90, 78, 90, 86, 22, 86], CHARCOAL),
				_line([30, 22, 30, 62], WHITE),
			]
	return []


static func _eyewear(id: StringName) -> Array:
	match id:
		&"glasses":
			return [
				_shape(_ring(30, 50, 17, 13), SKY.lightened(0.4)),
				_shape(_ring(70, 50, 17, 13), SKY.lightened(0.4)),
				_line([47, 48, 53, 48], BLACK, 4.0),
				_line([13, 48, 6, 44], BLACK, 4.0),
				_line([87, 48, 94, 44], BLACK, 4.0),
			]
		&"sunglasses":
			return [
				_shape([10, 38, 46, 38, 44, 62, 24, 64, 12, 54], CHARCOAL),
				_shape([54, 38, 90, 38, 88, 54, 76, 64, 56, 62], CHARCOAL),
				_line([46, 42, 54, 42], GREY, 4.0),
				_line([16, 44, 28, 44], WHITE, 3.0),
				_line([60, 44, 72, 44], WHITE, 3.0),
			]
		&"goggles":
			return [
				_shape([4, 44, 14, 44, 14, 58, 4, 58], BROWN),
				_shape([86, 44, 96, 44, 96, 58, 86, 58], BROWN),
				_shape(_ring(32, 51, 19, 19), SKY),
				_shape(_ring(68, 51, 19, 19), SKY),
				_shape([46, 46, 54, 46, 54, 56, 46, 56], BROWN),
			]
		&"cinema":
			return [
				_shape(_rounded(8.0, 34.0, 84.0, 36.0, 4.0), CREAM),
				_shape(_rounded(16.0, 40.0, 28.0, 24.0, 2.0), RED),
				_shape(_rounded(56.0, 40.0, 28.0, 24.0, 2.0), SKY),
			]
	return []


static func _neck(id: StringName) -> Array:
	match id:
		&"scarf":
			return [
				_shape([14, 26, 86, 26, 88, 46, 60, 52, 40, 52, 12, 46], RED),
				_shape([56, 48, 76, 48, 80, 88, 60, 88], RED.darkened(0.15)),
				_line([60, 62, 78, 62], WHITE),
				_line([60, 74, 79, 74], WHITE),
			]
		&"bowtie":
			return [
				_shape([50, 50, 10, 30, 10, 70], TEAL),
				_shape([50, 50, 90, 30, 90, 70], TEAL),
				_shape(_rounded(42.0, 40.0, 16.0, 20.0, 4.0), RED),
			]
		&"lanyard":
			return [
				_line([24, 12, 50, 58], NAVY, 5.0),
				_line([76, 12, 50, 58], NAVY, 5.0),
				_shape(_rounded(36.0, 56.0, 28.0, 34.0, 4.0), WHITE),
				_shape(_rounded(41.0, 62.0, 18.0, 12.0, 2.0), SKY),
			]
		&"bolo":
			return [
				_line([22, 14, 50, 62], BROWN, 5.0),
				_line([78, 14, 50, 62], BROWN, 5.0),
				_shape(_oval(50, 62, 12, 12), GOLD),
				_shape([46, 74, 54, 74, 56, 94, 44, 94], BLACK),
			]
		&"film":
			var shapes := [_shape([12, 24, 88, 24, 90, 46, 62, 52, 38, 52, 10, 46], CHARCOAL)]
			shapes.append(_shape([52, 48, 78, 48, 82, 90, 56, 90], CHARCOAL))
			for x in [20, 34, 48, 62, 76]:
				shapes.append(_shape(_rounded(float(x), 32.0, 7.0, 8.0, 1.5), WHITE))
			return shapes
	return []


# --- shape helpers -------------------------------------------------------------------------------


static func _shape(points: Variant, fill: Color) -> Dictionary:
	return {"points": _vectors(points), "fill": fill}


static func _line(points: Variant, colour: Color, width := DETAIL) -> Dictionary:
	return {"points": _vectors(points), "line": colour, "width": width}


## Points from either a flat list of numbers (x, y, x, y...) or ready vectors.
static func _vectors(points: Variant) -> PackedVector2Array:
	if points is PackedVector2Array:
		return points
	var out := PackedVector2Array()
	if (points as Array).is_empty() or points[0] is Vector2:
		for point: Vector2 in points:
			out.append(point)
		return out
	for i in range(0, points.size() - 1, 2):
		out.append(Vector2(float(points[i]), float(points[i + 1])))
	return out


static func _oval(cx: float, cy: float, rx: float, ry: float, from := 0.0, to := TAU) -> Array:
	var out: Array = []
	for step in OVAL_STEPS + 1:
		var angle := lerpf(from, to, float(step) / OVAL_STEPS)
		out.append(Vector2(cx + cos(angle) * rx, cy + sin(angle) * ry))
	return out


## A lens: an oval, drawn as a closed shape.
static func _ring(cx: float, cy: float, rx: float, ry: float) -> Array:
	return _oval(cx, cy, rx, ry)


static func _rounded(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [
		[x + w - r, y + r, -PI * 0.5],
		[x + w - r, y + h - r, 0.0],
		[x + r, y + h - r, PI * 0.5],
		[x + r, y + r, PI],
	]
	for corner: Array in corners:
		for step in 5:
			var angle: float = corner[2] + (PI * 0.5) * float(step) / 4.0
			out.append(Vector2(corner[0] + cos(angle) * r, corner[1] + sin(angle) * r))
	return out
