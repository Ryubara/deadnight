class_name CardArt
extends Control
## A calling card drawn at whatever size it is given: the 440 by 120 sheet of `PlateCompose.card`
## scaled to the control, cut to `clip` when the card sits behind something with a shape of its
## own (a player's box), with its printed title when `titled`, and a `veil` of one colour over the
## art. The shapes are built when the card or the size changes
## and drawn as one command (`HudShapes`); nothing is made per frame.

## The share of the card's height the title's type takes.
const TITLE_SIZE := 0.2

## The card on show (`&""` for none: nothing is drawn).
var card_id: StringName = &"":
	set(value):
		if card_id != value:
			card_id = value
			_dirty = true
			queue_redraw()
## Print the title on the card.
var titled := false:
	set(value):
		titled = value
		queue_redraw()
## Laid over the art: a colour at some opacity (a box keeps its seat's colour showing through).
var veil := Color(0, 0, 0, 0):
	set(value):
		veil = value
		queue_redraw()
## The outline the card is cut to, in the control's coordinates; empty for the whole rectangle.
var clip := PackedVector2Array():
	set(value):
		clip = value
		_dirty = true
		queue_redraw()
## The share of the card's width the picture is centred on, or negative for the piece's own side.
var motif_at := -1.0:
	set(value):
		motif_at = value
		_dirty = true
		queue_redraw()
## Keep the card's proportions and fit its height, at the left of the control (a roster row, far
## wider than a card is): the card is a chip of the row, not stretched across it.
var by_height := false:
	set(value):
		by_height = value
		_dirty = true
		queue_redraw()
## Draw only the card's outline in the flat colour of a locked piece (`ItemIcons.SILHOUETTE`): a
## hidden calling card not yet earned, which shows its shape and nothing it would give away.
var silhouette := false:
	set(value):
		if silhouette != value:
			silhouette = value
			_dirty = true
			queue_redraw()
## Dim the card (a downed player's).
var dim := 0.0:
	set(value):
		dim = value
		queue_redraw()

var _catalog := PlateCatalog.shipped()
var _built: Array[Dictionary] = []
var _built_size := Vector2.ZERO
var _dirty := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func() -> void: _dirty = true)


## How many shapes the card is drawn from, for tests (0 for no card).
func shape_count() -> int:
	_build()
	return _built.size()


func _build() -> void:
	if not _dirty and _built_size == size:
		return
	_built.clear()
	_dirty = false
	_built_size = size
	var piece := _catalog.piece(PlateCatalog.CARD, card_id)
	if piece.is_empty() or size.x < 1.0 or size.y < 1.0:
		return
	var factor := size / PlateCompose.CARD_SIZE
	if by_height:
		factor = Vector2.ONE * size.y / PlateCompose.CARD_SIZE.y
	var palette := StringName(piece.get("palette", ""))
	for item in PlateCompose.card(piece, motif_at):
		var points := PackedVector2Array()
		for point in item["p"] as PackedVector2Array:
			points.append(point * factor)
		var colour := PlatePalettes.colour(palette, item["r"])
		colour = ItemIcons.SILHOUETTE if silhouette else colour.lerp(Color.BLACK, dim)
		if clip.is_empty():
			_built.append({"p": points, "c": colour})
			continue
		for part in Geometry2D.intersect_polygons(points, clip):
			_built.append({"p": part, "c": colour})


func _draw() -> void:
	_build()
	if _built.is_empty():
		return
	var shapes := HudShapes.new()
	for item in _built:
		var colour: Color = item["c"]
		if veil.a > 0.0:
			colour = colour.lerp(Color(veil, 1.0), veil.a)
		shapes.polygon(item["p"], colour)
	shapes.flush(self)
	if silhouette:
		PlateDraw.question_mark(self, Rect2(Vector2.ZERO, size))
	elif titled:
		_draw_title()


func _draw_title() -> void:
	var piece := _catalog.piece(PlateCatalog.CARD, card_id)
	var box := PlateCompose.title_box(piece)
	var factor := size / PlateCompose.CARD_SIZE
	var font := get_theme_font(&"font", &"Label")
	var text := String(piece["title"]).to_upper()
	var width := box.size.x * factor.x
	var px := HudStyle.fit_size(font, text, maxi(int(size.y * TITLE_SIZE), 8), width, 8)
	# The type is centred in the band by its capitals.
	var middle := (box.position.y + box.size.y * 0.5) * factor.y
	var baseline := middle + (font.get_ascent(px) - font.get_descent(px)) * 0.5
	var ink := PlatePalettes.colour(StringName(piece["palette"]), PlateShapes.Role.DARK)
	draw_string(
		font,
		Vector2(box.position.x * factor.x, baseline),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		width,
		px,
		ink
	)
