class_name EmblemArt
extends Control
## An emblem, the small badge worn beside a name: `PlateCompose.emblem` scaled to a square of the
## control's shorter side. Built when the emblem or the size changes and drawn as one command.

## How much bigger the rim is than the badge.
const RIM_SCALE := 1.16

## The emblem on show (`&""` for none: nothing is drawn).
var emblem_id: StringName = &"":
	set(value):
		if emblem_id != value:
			emblem_id = value
			_dirty = true
			queue_redraw()
## A rim drawn round the badge, so it keeps its edge over a picture (a card behind it); alpha 0 for
## none.
var rim := Color(0, 0, 0, 0):
	set(value):
		rim = value
		_dirty = true
		queue_redraw()
## Dim the emblem (a downed player's).
var dim := 0.0:
	set(value):
		dim = value
		_dirty = true
		queue_redraw()

var _catalog := PlateCatalog.shipped()
var _built: Array[Dictionary] = []
var _dirty := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(
		func() -> void:
			_dirty = true
			queue_redraw()
	)


## A control that shows `id`, `side` units on each side.
static func make(id: StringName, side: float) -> EmblemArt:
	var art := EmblemArt.new()
	art.custom_minimum_size = Vector2.ONE * side
	art.size = art.custom_minimum_size
	art.emblem_id = id
	return art


## How many shapes the emblem is drawn from, for tests (0 for none).
func shape_count() -> int:
	_build()
	return _built.size()


func _build() -> void:
	if not _dirty:
		return
	_built.clear()
	_dirty = false
	var piece := _catalog.piece(PlateCatalog.EMBLEM, emblem_id)
	var side := minf(size.x, size.y)
	if piece.is_empty() or side < 1.0:
		return
	var factor := Vector2.ONE * side / PlateCompose.EMBLEM_SIZE.x
	var palette := StringName(piece.get("palette", ""))
	var shapes := PlateCompose.emblem(piece)
	var centre := Vector2.ONE * PlateCompose.EMBLEM_SIZE.x * 0.5
	if rim.a > 0.0:
		var edge := PackedVector2Array()
		for point in shapes[0]["p"] as PackedVector2Array:
			edge.append(centre + (point - centre) * RIM_SCALE)
		var rimmed := PackedVector2Array()
		for point in edge:
			rimmed.append(point * factor + (size - Vector2.ONE * side) * 0.5)
		_built.append({"p": rimmed, "c": rim})
	for item in shapes:
		var points := PackedVector2Array()
		for point in item["p"] as PackedVector2Array:
			points.append(point * factor + (size - Vector2.ONE * side) * 0.5)
		var colour := PlatePalettes.colour(palette, item["r"]).lerp(Color.BLACK, dim)
		_built.append({"p": points, "c": colour})


func _draw() -> void:
	_build()
	if _built.is_empty():
		return
	var shapes := HudShapes.new()
	for item in _built:
		shapes.polygon(item["p"], item["c"])
	shapes.flush(self)
