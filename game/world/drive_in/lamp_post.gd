class_name LampPost
extends Node3D
## A lamp post: the pole, the bulb's housing and its light. The light is the lot's to switch
## (`LotLamps`); the housing's glow follows through `set_glow`.

## How much of its albedo the bulb keeps when it is dark.
const DARK_ALBEDO := 0.25

var _lit_albedo := Color.WHITE
var _material: StandardMaterial3D

@onready var _head: CSGBox3D = $Head


func _ready() -> void:
	# The scene's material is shared by every post: each gets its own, or one switch would
	# darken them all.
	_material = (_head.material as StandardMaterial3D).duplicate()
	_head.material = _material
	_lit_albedo = _material.albedo_color


## `level` 0 (dark) to 1 (burning): the bulb's glow and colour.
func set_glow(level: float) -> void:
	_material.emission_energy_multiplier = level
	_material.albedo_color = _lit_albedo * lerpf(DARK_ALBEDO, 1.0, level)
