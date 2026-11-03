class_name PlayBounds
extends RefCounted
## The ground a map is played on, read from its scene: the footprint (seen from above) of every
## solid piece the map is built of, its floors, aprons, fences and walls, and nothing else. A
## player whose feet are over none of them stands on the far slab drawn for the horizon
## (`Outskirts`), or over nothing at all, and has left the playable space; the night puts that
## player back at the start (`NightServer`, `NightTuning.out_of_bounds_seconds`).
##
## Read from the scene, not written by hand, so a wall that moves or a floor that grows moves the
## bounds with it. The piece named `OUTSKIRTS` is the horizon, never part of the map. It decides
## nothing about walls: a player is out only when no piece of the map is under them.

## The horizon slab of the lot's scene: solid so the camera and the menu have a floor to draw, but
## no place to play.
const OUTSKIRTS := &"Outskirts"
## Side of one cell of the index (metres): a point looks only at the pieces that touch its cell.
const CELL := 4.0
## How far (metres) under the lowest piece a player can be before they are out whatever is above:
## the floor of a map with no slab under it is nothing but a fall.
const DEPTH := 6.0

var _pieces: Array[Rect2] = []
var _cells: Dictionary[Vector2i, PackedInt32Array] = {}
var _lowest := 0.0


## The bounds of the map in `root` (its pieces must be in the tree). A map with no solid piece has
## no bounds: nobody is ever out.
static func of(root: Node3D) -> PlayBounds:
	var bounds := PlayBounds.new()
	var found := false
	for node in root.find_children("*", "CSGShape3D", true, false):
		var shape := node as CSGShape3D
		if not shape.use_collision or shape.name == OUTSKIRTS or shape.get_parent() is CSGShape3D:
			continue
		var size := _size_of(shape)
		if size == Vector3.ZERO:
			continue
		var box := shape.global_transform * AABB(-size * 0.5, size)
		bounds._add(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
		bounds._lowest = box.position.y if not found else minf(bounds._lowest, box.position.y)
		found = true
	return bounds


## Whether there is a map to keep players on.
func is_empty() -> bool:
	return _pieces.is_empty()


## How many solid pieces make the map's ground.
func piece_count() -> int:
	return _pieces.size()


## Whether `point` (the player's feet) is outside the playable space.
func is_out(point: Vector3) -> bool:
	if _pieces.is_empty():
		return false
	if point.y < _lowest - DEPTH:
		return true
	var cell := _cell_of(point.x, point.z)
	for index in _cells.get(cell, PackedInt32Array()):
		var piece := _pieces[index]
		if (
			point.x >= piece.position.x
			and point.x <= piece.end.x
			and point.z >= piece.position.y
			and point.z <= piece.end.y
		):
			return false
	return true


func _add(piece: Rect2) -> void:
	var index := _pieces.size()
	_pieces.append(piece)
	var first := _cell_of(piece.position.x, piece.position.y)
	var last := _cell_of(piece.end.x, piece.end.y)
	for cx in range(first.x, last.x + 1):
		for cz in range(first.y, last.y + 1):
			var cell := Vector2i(cx, cz)
			var held: PackedInt32Array = _cells.get(cell, PackedInt32Array())
			held.append(index)
			_cells[cell] = held


static func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))


## The box a solid piece fills: every one in the greybox is a box or a cylinder.
static func _size_of(shape: CSGShape3D) -> Vector3:
	if shape is CSGBox3D:
		return (shape as CSGBox3D).size
	if shape is CSGCylinder3D:
		var cylinder := shape as CSGCylinder3D
		return Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
	return Vector3.ZERO
