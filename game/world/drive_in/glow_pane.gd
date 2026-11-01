class_name GlowPane
extends LightFollower
## A lit window: an additive pane in the opening that brightens what is behind it, with a lamp's
## warmth and a faint tremble (a function of the phase). It burns with the lamp it follows.

## The pane's brightness at level 1.
const PANE_ENERGY := 0.55

@export var colour := Color(1.0, 0.7, 0.35)

var _material: StandardMaterial3D


func _ready() -> void:
	var pane := $Pane as MeshInstance3D
	_material = (pane.material_override as StandardMaterial3D).duplicate()
	pane.material_override = _material
	super._ready()


func _apply() -> void:
	var tremble := 1.0 + 0.06 * sin(phase * 9.0) * sin(phase * 2.3)
	_material.albedo_color = colour * (level * tremble * PANE_ENERGY)
	($Pane as MeshInstance3D).visible = level > 0.0
