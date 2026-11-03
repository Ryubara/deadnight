class_name LampPost
extends Node3D
## A lamp post: the pole, the housing, the lens and its light. The light is the lot's to switch
## (`LotLamps`); the lens, the halo round it and the pool of light on the ground follow through
## `set_glow`. The halo and the pool are additive quads (`glow.gdshader`), not lights: the
## Compatibility renderer lights a mesh with at most 8, so the pool is what makes a lamp read on the
## asphalt from across the lot.

## The half-size of the pool card in the scene, metres.
const POOL_HALF := 7.5
## The half angle of the aimed light's cone, degrees.
const AWAY_CONE := 30.0

## A post that stands near a wall (the back lot's, issue #851): the horizontal direction away from
## the wall (or the corner), or zero for a post in the open. Compatibility draws no shadow, so an
## omni light and a ground pool reach through a wall into the next room; such a post aims its light
## away from the wall as a spot whose cone never crosses the vertical plane of its apex (it keeps
## the omni's slot), and its pool is smaller and moved away so that it stops short of the wall.
@export var away := Vector3.ZERO
## The half-size of the pool when `away` is set, metres (the scene's card is `POOL_HALF`).
@export_range(1.0, 7.5, 0.05, "suffix:m") var pool_half := 4.0
## How far the aimed light is tilted from straight down, degrees (the generator works it out: the
## cone of half angle `AWAY_CONE` tilted `t` stays out of a wall's side when
## sin(t) * cos(angle between the aim and the wall's normal) >= sin(AWAY_CONE), so a post in a
## corner leans further than one by a single wall).
@export_range(0.0, 85.0, 0.5, "suffix:deg") var aim_tilt := 32.0

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
	if not away.is_zero_approx():
		_aim_away()


## `level` 0 (dark) to 1 (burning): the bulb's glow and colour, its halo and its pool of light.
func set_glow(level: float) -> void:
	var tuning := LightTuning.current()
	_material.emission_energy_multiplier = level * tuning.bulb_energy
	_material.albedo_color = _lit_albedo * lerpf(tuning.bulb_dark_albedo, 1.0, level)
	_halo_material.set_shader_parameter(&"energy", level * tuning.bulb_halo_energy)
	_pool_material.set_shader_parameter(&"energy", level * tuning.bulb_pool_energy)
	_halo.visible = level > 0.0
	_pool.visible = level > 0.0


## Turns the light into a spot aimed down and away from the wall, and pulls the pool back from it.
func _aim_away() -> void:
	var direction := Vector3(away.x, 0.0, away.z).normalized()
	var omni := $Light as OmniLight3D
	var spot := SpotLight3D.new()
	spot.light_color = omni.light_color
	spot.light_energy = omni.light_energy
	spot.spot_range = omni.omni_range
	spot.spot_attenuation = 0.8
	spot.spot_angle = AWAY_CONE
	spot.transform = omni.transform
	var tilt := deg_to_rad(aim_tilt)
	var axis := direction * sin(tilt) + Vector3.DOWN * cos(tilt)
	spot.transform.basis = Basis.looking_at(axis, Vector3.UP)
	remove_child(omni)
	omni.queue_free()
	spot.name = &"Light"
	add_child(spot)
	spot.add_to_group(&"powered_light")
	_pool.scale = Vector3.ONE * (pool_half / POOL_HALF)
	_pool.position += direction * pool_half * 0.5
