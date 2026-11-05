class_name PlateDraw
extends RefCounted
## A calling card, an emblem or a frame drawn once onto any canvas item, for a place that is not
## worth a control of its own (the thumbnail on an unlock's popup card): the same shapes `CardArt`,
## `EmblemArt` and `FrameArt` are built from (`PlateCompose`, `PlateFrames`), as one command
## (`HudShapes`).


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


## A `?` over a silhouette (a hidden piece not yet earned), centred in `rect`, a shade lighter than
## the silhouette's colour so it reads and gives nothing away.
static func question_mark(item: CanvasItem, rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var px := maxi(int(minf(rect.size.x, rect.size.y) * 0.62), 8)
	var ink := ItemIcons.SILHOUETTE.lightened(0.3)
	var baseline := rect.get_center().y + (font.get_ascent(px) - font.get_descent(px)) * 0.5
	item.draw_string(
		font,
		Vector2(rect.position.x, baseline),
		"?",
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		px,
		ink
	)


## The frame `id` on a plate that fills `rect`, over `ground` (a swatch of the plate).
static func frame(
	item: CanvasItem, rect: Rect2, id: StringName, ground := Color(0, 0, 0, 0)
) -> void:
	var piece := PlateCatalog.shipped().piece(PlateCatalog.FRAME, id)
	if piece.is_empty():
		return
	var shape := PlateFrames.rect_outline(rect)
	var ops := PlateFrames.build(
		StringName(piece.get("style", "")),
		StringName(piece.get("palette", "")),
		shape,
		PlateFrames.width_for(rect.size.y)
	)
	flush_frame(item, ops, shape, ground, 0.0)


## Draws the ops of a frame (`PlateFrames.build`) as one command, over `ground` inside `shape` when
## it has any colour, darkened by `dim`.
static func flush_frame(
	item: CanvasItem, ops: Array[Dictionary], shape: PackedVector2Array, ground: Color, dim: float
) -> void:
	var out := HudShapes.new()
	if ground.a > 0.0:
		out.polygon(shape, ground)
	for op in ops:
		var colour: Color = (op["c"] as Color).lerp(Color(0, 0, 0, op["c"].a), dim)
		if op["k"] == "line":
			out.polyline(op["p"], colour, op["w"])
		else:
			out.polygon(op["p"], colour)
	out.flush(item)


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
