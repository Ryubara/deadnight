class_name Outline
extends Node
## Outlines a model through walls: every mesh under `target` (a skinned or static one, whatever the
## model; nothing in it is edited) gets the style's materials as its overlay while `enabled`. The
## outline is the silhouette's edge only, a line with no glow, drawn only on the pixels where the
## model is hidden behind something (a depth test against the scene's depth, per pixel); its colour
## and thickness are the `style`'s (`OutlineStyle`), which every mesh that wears it shares. Nothing
## runs and nothing is drawn while it is off: the overlay is taken off the meshes.

## The shipped look (`outline_style_default.tres`), for an outline given no style of its own.
const DEFAULT_STYLE := "res://gameplay/outline/outline_style_default.tres"

## The node to outline; empty means this node's parent.
@export var target: NodePath
## The look; empty uses the shipped one.
@export var style: OutlineStyle:
	set(value):
		if value != style:
			style = value
			_apply()
@export var enabled := false:
	set(value):
		if value != enabled:
			enabled = value
			_apply()

var _root: Node
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	if _root == null:
		_root = get_node_or_null(target) if not target.is_empty() else get_parent()
	refresh()


## Outlines `node` and everything under it from now on, instead of `target`.
func set_root(node: Node) -> void:
	_withdraw()
	_root = node
	refresh()


## Looks for the meshes again (the model changed) and applies the state to them.
func refresh() -> void:
	_withdraw()
	_meshes.clear()
	if _root != null and is_instance_valid(_root):
		for node in _root.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(node as MeshInstance3D)
		if _root is MeshInstance3D:
			_meshes.append(_root as MeshInstance3D)
	_apply()


## The meshes this outline covers.
func meshes() -> Array[MeshInstance3D]:
	return _meshes


## The style in use: the one set, or the shipped one.
func active_style() -> OutlineStyle:
	if style == null:
		style = load(DEFAULT_STYLE) as OutlineStyle
	return style


func _apply() -> void:
	var overlay: Material = active_style().chain() if enabled else null
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = overlay


## Takes the overlay off every covered mesh.
func _withdraw() -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
