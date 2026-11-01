class_name CircuitSwitch
extends Node3D
## A breaker post that switches one of the generator's circuits (`Switches/*`, written by
## tools/world/build_greybox.py). Its front is local +Z, where a player stands. The node carries the
## circuit it switches (`metadata/circuit`) and, when it lights an area behind a purchase door, that
## door's shop id (`metadata/door`).
##
## It decides nothing: `NightServer` answers the use with `RulesAction.set_circuit`, and the post
## shows the circuit the rules report (`set_on`): the lever's tip up and a green lamp for on, the
## tip down and a dull red lamp for off. The lamp is an emissive surface, not a light, so it never
## counts as a lamp of the lot's circuits (`LotLamps`).

const LEVER_ON := deg_to_rad(-40.0)
const LEVER_OFF := deg_to_rad(40.0)
const LAMP_ON := Color(0.35, 1.0, 0.45)
const LAMP_OFF := Color(0.55, 0.08, 0.06)
## How much of the lamp's colour glows when it is off.
const GLOW_OFF := 0.5
const GLOW_ON := 2.0
## The halo round the lamp, so a post reads from across the lot: bright green on, a dull red off.
const HALO_ON := 1.1
const HALO_OFF := 0.45

## The circuit this post switches (`metadata/circuit`).
var circuit_id: StringName = &""
## The shop door of the area it lights, or empty when it lights none (the field).
var door_id: StringName = &""

var _on := false
var _material: StandardMaterial3D
var _halo: ShaderMaterial

@onready var _lever: Node3D = $Lever
@onready var _lamp: MeshInstance3D = $Lamp
@onready var _halo_node: MeshInstance3D = $Halo


func _ready() -> void:
	circuit_id = StringName(get_meta(&"circuit", ""))
	door_id = StringName(get_meta(&"door", ""))
	# The scene's material is shared by every post: each lamp gets its own.
	_material = (_lamp.material_override as StandardMaterial3D).duplicate()
	_lamp.material_override = _material
	_halo = (_halo_node.material_override as ShaderMaterial).duplicate()
	_halo_node.material_override = _halo
	set_on(false)


func is_on() -> bool:
	return _on


## Shows the circuit as on or off.
func set_on(on: bool) -> void:
	_on = on
	_lever.rotation.x = LEVER_ON if on else LEVER_OFF
	_material.albedo_color = LAMP_ON if on else LAMP_OFF
	_material.emission = LAMP_ON if on else LAMP_OFF
	_material.emission_energy_multiplier = GLOW_ON if on else GLOW_OFF
	_halo.set_shader_parameter(&"tint", LAMP_ON if on else LAMP_OFF)
	_halo.set_shader_parameter(&"energy", HALO_ON if on else HALO_OFF)


## Where a player stands to use it: `distance` metres out from its front.
func standing_point(distance: float) -> Vector3:
	return global_position + front() * distance


## The way its front faces, flat and unit length.
func front() -> Vector3:
	var direction := global_basis.z
	direction.y = 0.0
	return direction.normalized()
