class_name PlateDraw
extends RefCounted
## A calling card or an emblem drawn once onto any canvas item, for a place that is not worth a
## control of its own (the thumbnail on an unlock's popup card): the same shapes `CardArt` and
## `EmblemArt` are built from (`PlateCompose`), as one command (`HudShapes`).


## The card `id` in `rect`: the card keeps its proportions, fitting the rectangle's width and
## centred in its height (what is taller than the rectangle is cut by it).
static func card(item: CanvasItem, rect: Rect2, id: StringName) -> void:
	var piece := PlateCatalog.shipped().piece(PlateCatalog.CARD, id)
	if piece.is_empty():
		return
	var factor := rect.size.x / PlateCompose.CARD_SIZE.x
	var at := rect.position + Vector2(0.0, (rect.size.y - PlateCompose.CARD_SIZE.y * factor) * 0.5)
	_draw(item, PlateCompose.card(piece), piece, at, factor, rect)


## The emblem `id` in the square of side `rect`'s shorter side, centred in `rect`.
static func emblem(item: CanvasItem, rect: Rect2, id: StringName) -> void:
	var piece := PlateCatalog.shipped().piece(PlateCatalog.EMBLEM, id)
	if piece.is_empty():
		return
	var side := minf(rect.size.x, rect.size.y)
	var at := rect.position + (rect.size - Vector2.ONE * side) * 0.5
	_draw(item, PlateCompose.emblem(piece), piece, at, side / PlateCompose.EMBLEM_SIZE.x, Rect2())


static func _draw(
	item: CanvasItem,
	shapes: Array[Dictionary],
	piece: Dictionary,
	at: Vector2,
	factor: float,
	clip: Rect2
) -> void:
	var palette := StringName(piece.get("palette", ""))
	var cut := PackedVector2Array()
	if clip.has_area():
		cut = PackedVector2Array(
			[
				clip.position,
				Vector2(clip.end.x, clip.position.y),
				clip.end,
				Vector2(clip.position.x, clip.end.y)
			]
		)
	var out := HudShapes.new()
	for shape in shapes:
		var points := PackedVector2Array()
		for point in shape["p"] as PackedVector2Array:
			points.append(point * factor + at)
		var colour := PlatePalettes.colour(palette, shape["r"])
		if cut.is_empty():
			out.polygon(points, colour)
			continue
		for part in Geometry2D.intersect_polygons(points, cut):
			out.polygon(part, colour)
	out.flush(item)
