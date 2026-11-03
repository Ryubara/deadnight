class_name WallSilhouette
extends Node3D
## What a wall weapon's plaque shows from any distance: the weapon's silhouette, in place of its
## name (#829). The name and the price are the prompt card's, which appears when a player is in
## reach. The node sits where the plaque's sign used to; the shape is `SilhouetteMesh`.

## The shop id the spot sells (`weapon_rifle`, `grenades`), as in the spot's `shop_id` metadata.
@export var shop_id: StringName = &""
## Whether the plaque stands on end (the cabinet's): the weapon is laid along its long side.
@export var upright := false

var shape: MeshInstance3D


func _ready() -> void:
	shape = MeshInstance3D.new()
	shape.name = "Shape"
	shape.mesh = SilhouetteMesh.mesh_for(shop_id, upright)
	shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shape)


## Whether the shape is the plain stand-in because the weapon's model is not in the game yet.
func is_stand_in() -> bool:
	return SilhouetteMesh.is_stand_in(shop_id, upright)
