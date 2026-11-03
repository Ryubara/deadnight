@tool
class_name KitStair
extends Node3D
## A straight stair of the small-map kit (`fixtures/stair_straight.tscn`, built by
## tools/blender/build_kit_stairs.py). It has a rail model and a player-only rail blocker on each
## side; the rail goes on the open side only, so the level says which sides are open. Left and
## right are as seen climbing (the foot at +Z, climbing towards -Z): left is -X.

## The rail on the left (-X) side: shown, and its blocker solid.
@export var rail_left := true:
	set(value):
		rail_left = value
		_apply()
## The rail on the right (+X) side.
@export var rail_right := false:
	set(value):
		rail_right = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	_side(&"Left", rail_left)
	_side(&"Right", rail_right)


func _side(side: StringName, on: bool) -> void:
	var model := get_node_or_null(NodePath("Model/Rail%s" % side)) as Node3D
	if model != null:
		model.visible = on
	var blocker := get_node_or_null(NodePath("Rail%sBlocker" % side)) as CSGShape3D
	if blocker != null:
		# Off, the navigation bake and the player both ignore it (navmesh_baker.gd reads use_collision).
		blocker.use_collision = on
