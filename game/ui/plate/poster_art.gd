class_name PosterArt
extends Control
## A poster set's poster at whatever size it is given: `PosterCompose.shapes` scaled to the control
## (one command, `HudShapes`), the title printed on it when `titled`, and a cover over each panel
## the player has not uncovered yet (dark, with its number, so the picture is guessed at). The
## shapes are built when the set or the size changes; uncovering a panel only redraws the covers.

## The cover over a panel not yet uncovered, and the colour of its number's ink.
const COVER := Color("0b0916")
const COVER_ALPHA := 0.94
const GRID_COLOUR := Color("0b0916")
## The number on a cover: its size as a share of the panel's height.
const NUMBER_SIZE := 0.42

## The set on show (null: nothing is drawn).
var poster: PosterSet:
	set(value):
		poster = value
		_dirty = true
		queue_redraw()
## The panels uncovered (0 to 5).
var uncovered: Array[int] = []:
	set(value):
		uncovered = value
		queue_redraw()
## Print the title and number the covers: off for a thumbnail too small to read.
var titled := true:
	set(value):
		titled = value
		queue_redraw()

var _built: Array[Dictionary] = []
var _built_size := Vector2.ZERO
var _dirty := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


## A control that shows `set` `width` units across, the poster's proportions.
static func make(
	poster_set: PosterSet, width: float, panels: Array[int], print_title := true
) -> PosterArt:
	var art := PosterArt.new()
	art.custom_minimum_size = Vector2(width, width * PosterCompose.SIZE.y / PosterCompose.SIZE.x)
	art.size = art.custom_minimum_size
	art.titled = print_title
	art.poster = poster_set
	art.uncovered = panels
	return art


## How many shapes the poster is drawn from, for tests (0 for none).
func shape_count() -> int:
	_build()
	return _built.size()


## How many units of this control one unit of the design space is.
func factor() -> float:
	return size.x / PosterCompose.SIZE.x


func _build() -> void:
	if not _dirty and _built_size == size:
		return
	_built.clear()
	_dirty = false
	_built_size = size
	if poster == null or size.x < 1.0:
		return
	var unit := factor()
	for item in PosterCompose.shapes(poster):
		var points := PackedVector2Array()
		for point in item["p"] as PackedVector2Array:
			points.append(point * unit)
		_built.append({"p": points, "c": PlatePalettes.colour(poster.palette, item["r"])})


func _draw() -> void:
	_build()
	if _built.is_empty():
		return
	var shapes := HudShapes.new()
	for item in _built:
		shapes.polygon(item["p"], item["c"])
	shapes.flush(self)
	var unit := factor()
	var font := get_theme_font(&"font", &"Label")
	if titled:
		_print_title(font, unit)
	for index in PosterSet.PANELS:
		if not uncovered.has(index):
			_cover(index, font, unit)
	if uncovered.size() < PosterSet.PANELS:
		_draw_grid(unit)


func _print_title(text_font: Font, unit: float) -> void:
	var width := (PosterCompose.SIZE.x - 36.0) * unit
	for line: Dictionary in PosterCompose.print_lines(poster):
		var font: Font = UITokens.active().font_display if line["display"] else text_font
		var text: String = line["text"]
		var wanted := maxi(int(float(line["size"]) * unit), 6)
		var px := HudStyle.fit_size(font, text, wanted, width, 6)
		var ink := PlatePalettes.colour(poster.palette, line["role"])
		var span := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var at := Vector2((size.x - span) * 0.5, float(line["baseline"]) * unit)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)


func _cover(index: int, font: Font, unit: float) -> void:
	var rect := PosterCompose.panel_rect(index)
	rect = Rect2(rect.position * unit, rect.size * unit)
	draw_rect(rect, Color(COVER, COVER_ALPHA))
	if not titled:
		return
	var px := maxi(int(rect.size.y * NUMBER_SIZE), 8)
	var text := str(index + 1)
	var span := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var ink := Color(PlatePalettes.colour(poster.palette, PlateShapes.Role.LIGHT), 0.42)
	var at := (
		rect.position
		+ Vector2(
			(rect.size.x - span.x) * 0.5,
			(rect.size.y + font.get_ascent(px) - font.get_descent(px)) * 0.5
		)
	)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)


## The lines between the panels, over the picture and the covers.
func _draw_grid(unit: float) -> void:
	var thickness := maxf(unit * 2.0, 1.0)
	var w := size.x
	var h := size.y
	draw_rect(Rect2(w * 0.5 - thickness * 0.5, 0.0, thickness, h), GRID_COLOUR)
	for row in range(1, PosterSet.ROWS):
		var y := h * float(row) / float(PosterSet.ROWS)
		draw_rect(Rect2(0.0, y - thickness * 0.5, w, thickness), GRID_COLOUR)
