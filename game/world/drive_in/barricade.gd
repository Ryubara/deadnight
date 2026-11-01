class_name Barricade
extends Node3D
## The boards across one breach of the field's fence (`Field/Breach*`, written by
## tools/world/build_greybox.py). The node sits in the middle of the gap on the fence line, turned
## so its local +Z points into the field: a zombie outside stands at a negative depth, a player
## putting a board back at a positive one.
##
## The boards are `Board` children, bottom to top. They are drawn and solid for players while they
## are up, and never part of the navigation mesh (they are not CSG): the dead's way in is the gap,
## and what holds them is the zombie simulation's gate, not physics. The shots go through them: they
## sit on a physics layer of their own that only players' bodies collide with.
##
## `NightWorld.bind` sets the count from the rules' events; nothing else changes it.

## The physics layer (as a mask bit) of boards: players collide with it, shots and grenades do not.
## `player.tscn` has it in its mask.
const BOARD_LAYER := 2

## The breach's id, the one the rules' tuning lists (`metadata/barricade_id`).
var barricade_id: StringName = &""

var _boards: Array[StaticBody3D] = []
var _up: int = 0


func _ready() -> void:
	barricade_id = StringName(get_meta(&"barricade_id", ""))
	for child in get_children():
		if child is StaticBody3D:
			_boards.append(child)
	_up = _boards.size()


## The most boards it holds.
func capacity() -> int:
	return _boards.size()


## Boards up now.
func boards() -> int:
	return _up


## Puts the lowest `count` boards up and the rest down, clamped to what it holds.
func set_boards(count: int) -> void:
	_up = clampi(count, 0, _boards.size())
	for i in _boards.size():
		var up := i < _up
		_boards[i].visible = up
		_boards[i].collision_layer = BOARD_LAYER if up else 0


## Where the boards stand, on the ground in the middle of the gap.
func centre() -> Vector3:
	return global_position


## The way into the field, flat and unit length.
func inward() -> Vector3:
	var direction := global_basis.z
	direction.y = 0.0
	return direction.normalized()


## How far `point` is past the boards into the field, in metres: negative outside the fence.
func depth_of(point: Vector3) -> float:
	var offset := point - global_position
	offset.y = 0.0
	return offset.dot(inward())


## A place on the field side to stand at to put boards back, `distance` metres in.
func standing_point(distance: float) -> Vector3:
	return global_position + inward() * distance
