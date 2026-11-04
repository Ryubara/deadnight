class_name HudShapes
extends RefCounted
## Flat shapes collected and drawn as ONE canvas command (#948). A canvas item's polygon, polyline
## and circle commands are each a draw call of their own in the Compatibility renderer, and each
## breaks the batch of the rects drawn around it; one triangle array with a colour per vertex is one
## call, and the triangles come out in the order they were added, so the shapes stack as the
## separate commands did (a ticket's shadow, paper, edge and stripe in one call instead of four).
## The triangles are the engine's own (`Geometry2D.triangulate_polygon`, the polyline's quads), so
## the picture is the same pixel for pixel.
##
## Usage in a `_draw`: `var shapes := HudShapes.new()`, add shapes in drawing order, then
## `shapes.flush(self)`.

## The sharpest corner a line is mitred at: past it the corner is cut (the offset stops growing).
const MITER_LIMIT := 0.25
## Segments of a circle, as `CanvasItem.draw_circle` cuts it.
const CIRCLE_SEGMENTS := 64

var _points := PackedVector2Array()
var _colours := PackedColorArray()
var _indices := PackedInt32Array()


## Whether nothing was added.
func is_empty() -> bool:
	return _indices.is_empty()


## A filled polygon (convex or not, as `CanvasItem.draw_colored_polygon` takes it).
func polygon(points: PackedVector2Array, colour: Color) -> void:
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		return
	var base := _points.size()
	for point in points:
		_points.append(point)
		_colours.append(colour)
	for index in triangles:
		_indices.append(base + index)


## A filled rectangle, as `CanvasItem.draw_rect` fills it.
func rect(area: Rect2, colour: Color) -> void:
	var base := _points.size()
	_points.append(area.position)
	_points.append(Vector2(area.end.x, area.position.y))
	_points.append(area.end)
	_points.append(Vector2(area.position.x, area.end.y))
	for _i in 4:
		_colours.append(colour)
	for index in [0, 1, 2, 0, 2, 3]:
		_indices.append(base + index)


## A filled circle, as `CanvasItem.draw_circle` fills it (a fan of segments).
func circle(centre: Vector2, radius: float, colour: Color) -> void:
	var base := _points.size()
	_points.append(centre)
	_colours.append(colour)
	for i in CIRCLE_SEGMENTS:
		var angle := TAU * float(i) / float(CIRCLE_SEGMENTS)
		_points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
		_colours.append(colour)
	for i in CIRCLE_SEGMENTS:
		_indices.append(base)
		_indices.append(base + 1 + i)
		_indices.append(base + 1 + (i + 1) % CIRCLE_SEGMENTS)


## A straight line of `width` (a quad), as `CanvasItem.draw_line` draws one.
func line(from: Vector2, to: Vector2, colour: Color, width: float) -> void:
	polyline(PackedVector2Array([from, to]), colour, width)


## A line of `width` through `points`, built as `CanvasItem.draw_polyline` builds it (a quad per
## segment, mitred at the corners so the edges keep half the width from the line). Close a shape by
## repeating its first point at the end: the seam is joined like any other corner.
func polyline(points: PackedVector2Array, colour: Color, width: float) -> void:
	var count := points.size()
	if count < 2:
		return
	var base := _points.size()
	var closed := count > 2 and points[0].is_equal_approx(points[count - 1])
	var first := _normal(points[0], points[1])
	var last := _normal(points[count - 2], points[count - 1])
	var previous := last if closed else first
	for i in count:
		var normal := first
		if i == count - 1:
			normal = first if closed else last
		elif i > 0:
			normal = _normal(points[i], points[i + 1])
		var behind := last if (closed and i == count - 1) else previous
		var tangent := (normal + behind).normalized()
		tangent *= width * 0.5 / maxf(tangent.dot(normal), MITER_LIMIT)
		_points.append(points[i] + tangent)
		_points.append(points[i] - tangent)
		_colours.append(colour)
		_colours.append(colour)
		if i > 0:
			var at := base + 2 * (i - 1)
			for index in [0, 1, 2, 1, 3, 2]:
				_indices.append(at + index)
		previous = normal


func _normal(from: Vector2, to: Vector2) -> Vector2:
	return (to - from).normalized().orthogonal()


## Draws everything added as one command on `item`, then forgets it.
func flush(item: CanvasItem) -> void:
	if _indices.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(
		item.get_canvas_item(), _indices, _points, _colours
	)
	_points = PackedVector2Array()
	_colours = PackedColorArray()
	_indices = PackedInt32Array()
