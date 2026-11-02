class_name LotScreen
extends LightFollower
## The movie screen. Its face is `screen.gdshader`, a soft projected picture that drifts slowly;
## this node feeds it the circuit's level and a slow flicker of the projector's light, and the
## ground below the screen takes a faint spill of the same flicker.

## The face to paint (a CSG panel of the lot).
@export var panel_path: NodePath
## The spill on the ground below the screen (an additive quad, `glow.gdshader`).
@export var spill_path: NodePath

var _face: ShaderMaterial
var _spill: ShaderMaterial


func _ready() -> void:
	var panel := get_node_or_null(panel_path) as CSGShape3D
	if panel != null:
		_face = ShaderMaterial.new()
		_face.shader = load("res://world/drive_in/screen.gdshader")
		panel.set("material", _face)
	var spill := get_node_or_null(spill_path) as MeshInstance3D
	if spill != null:
		_spill = (spill.material_override as ShaderMaterial).duplicate()
		spill.material_override = _spill
	super._ready()


## The projector's light: a slow swell and ebb with a quick tremble on top. Roughly 0.6 to 1.2, a
## function of `at` alone.
static func flicker(at: float) -> float:
	var slow := sin(at * 0.55) * 0.5 + sin(at * 1.3 + 1.7) * 0.3
	var quick := sin(at * 11.0) * 0.03 + sin(at * 23.0 + 0.4) * 0.02
	return 0.88 + slow * 0.18 + quick


func _apply() -> void:
	var f := flicker(phase)
	if _face != null:
		_face.set_shader_parameter(&"energy", level * f * LightTuning.current().screen_face_energy)
		_face.set_shader_parameter(&"phase", phase)
	if _spill != null:
		_spill.set_shader_parameter(
			&"energy", level * f * LightTuning.current().screen_spill_energy
		)
