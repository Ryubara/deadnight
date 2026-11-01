class_name LampPost
extends Node3D
## A lamp post: the pole, the housing, the lens and its light. The light is the lot's to switch
## (`LotLamps`); the lens, the halo round it and the pool of light on the ground follow through
## `set_glow`. The halo and the pool are additive quads (`glow.gdshader`), not lights: the
## Compatibility renderer lights a mesh with at most 8, so the pool is what makes a lamp read on the
## asphalt from across the lot.

## How much of its albedo the bulb keeps when it is dark.
const DARK_ALBEDO := 0.25
## The lens's emission, the halo's and the pool's brightness at full glow.
const BULB_ENERGY := 3.0
const HALO_ENERGY := 0.9
const POOL_ENERGY := 0.5

var _lit_albedo := Color.WHITE
var _material: StandardMaterial3D
var _halo_material: ShaderMaterial
var _pool_material: ShaderMaterial

@onready var _head: CSGBox3D = $Head
@onready var _halo: MeshInstance3D = $Halo
@onready var _pool: MeshInstance3D = $Pool


func _ready() -> void:
	# The scene's materials are shared by every post: each gets its own, or one switch would
	# darken them all.
	_material = (_head.material as StandardMaterial3D).duplicate()
	_head.material = _material
	_lit_albedo = _material.albedo_color
	_halo_material = (_halo.material_override as ShaderMaterial).duplicate()
	_halo.material_override = _halo_material
	_pool_material = (_pool.material_override as ShaderMaterial).duplicate()
	_pool.material_override = _pool_material


## `level` 0 (dark) to 1 (burning): the bulb's glow and colour, its halo and its pool of light.
func set_glow(level: float) -> void:
	_material.emission_energy_multiplier = level * BULB_ENERGY
	_material.albedo_color = _lit_albedo * lerpf(DARK_ALBEDO, 1.0, level)
	_halo_material.set_shader_parameter(&"energy", level * HALO_ENERGY)
	_pool_material.set_shader_parameter(&"energy", level * POOL_ENERGY)
	_halo.visible = level > 0.0
	_pool.visible = level > 0.0
