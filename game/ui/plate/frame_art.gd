class_name FrameArt
extends Control
## A plate frame (#1071) drawn round a plate: the border `PlateFrames` composes for the piece
## `frame_id`, run just inside `outline` (a player's ticket-shaped box) or, with none, the control's
## own rectangle (a roster row, a lobby seat). It sits over the plate and takes no input; it changes
## no layout, since the border stays inside the outline. Built when the frame, the outline or the
## size changes and drawn as one command (`HudShapes`); nothing is made per frame.

## The frame on show (`&""` for none: nothing is drawn).
var frame_id: StringName = &"":
	set(value):
		if frame_id != value:
			frame_id = value
			_dirty = true
			queue_redraw()
## The shape the border follows, in the control's coordinates; empty for the whole rectangle.
var outline := PackedVector2Array():
	set(value):
		outline = value
		_dirty = true
		queue_redraw()
## How far the border sits outside the control's rectangle on each side, per axis, when it has no
## outline of its own: a plate whose container insets its children (a roster row with room kept
## clear) or whose picture must not be covered (a card's title) takes the frame outside it.
var grow := Vector2.ZERO:
	set(value):
		grow = value
		_dirty = true
		queue_redraw()
## The stroke width, or zero for the one that suits the control's height (`PlateFrames.width_for`).
var width := 0.0:
	set(value):
		width = value
		_dirty = true
		queue_redraw()
## A colour filled inside the outline first, under the border (a swatch on the equip screen, which
## shows a bare plate for no frame).
var ground := Color(0, 0, 0, 0):
	set(value):
		ground = value
		queue_redraw()
## Dim the frame (a downed player's).
var dim := 0.0:
	set(value):
		dim = value
		queue_redraw()

var _catalog := PlateCatalog.shipped()
var _ops: Array[Dictionary] = []
var _shape := PackedVector2Array()
var _dirty := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(
		func() -> void:
			_dirty = true
			queue_redraw()
	)


## A control that shows `id` on a plate `plate_size` units big, for a place that is not worth a
## layout (the equip screen's swatch).
static func make(id: StringName, plate_size: Vector2) -> FrameArt:
	var art := FrameArt.new()
	art.custom_minimum_size = plate_size
	art.size = plate_size
	art.frame_id = id
	return art


## How many ops the frame is drawn from, for tests (0 for none).
func op_count() -> int:
	_build()
	return _ops.size()


## The border's thickness from the edge of the plate inwards, for tests.
func depth() -> float:
	return _stroke() * PlateFrames.THICKNESS


func _stroke() -> float:
	return width if width > 0.0 else PlateFrames.width_for(size.y + grow.y * 2.0)


func _build() -> void:
	if not _dirty:
		return
	_dirty = false
	_ops.clear()
	_shape = (
		outline
		if outline.size() >= 3
		else PlateFrames.rect_outline(Rect2(-grow, size + grow * 2.0))
	)
	var piece := _catalog.piece(PlateCatalog.FRAME, frame_id)
	if piece.is_empty() or size.x < 1.0 or size.y < 1.0:
		return
	_ops = PlateFrames.build(
		StringName(piece.get("style", "")), StringName(piece.get("palette", "")), _shape, _stroke()
	)


func _draw() -> void:
	_build()
	if _ops.is_empty() and ground.a <= 0.0:
		return
	PlateDraw.flush_frame(self, _ops, _shape, ground, dim)
