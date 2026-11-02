class_name LotNeonSign
extends LightFollower
## A neon sign over a door: a dark board, a lit frame, the word, a halo, and a lamp of its own
## (`Light`, in the `powered_light` group, so it hangs on the circuit of the `Lamps` group the sign
## is placed in). The tubes follow the lamp's level with a buzz: now and then one drops out for an
## instant, a function of the phase alone.

@export var text := "OPEN"
@export var neon_color := Color(1.0, 0.25, 0.5)

var _frame: StandardMaterial3D
var _halo: ShaderMaterial
var _text: Label3D


func _ready() -> void:
	light_path = ^"Light"
	_text = $Text as Label3D
	_text.text = text
	_frame = ($Frame/Top as MeshInstance3D).material_override.duplicate() as StandardMaterial3D
	for tube: MeshInstance3D in $Frame.get_children():
		tube.material_override = _frame
	_frame.albedo_color = neon_color
	_frame.emission = neon_color
	_halo = ($Halo as MeshInstance3D).material_override.duplicate() as ShaderMaterial
	($Halo as MeshInstance3D).material_override = _halo
	_halo.set_shader_parameter(&"tint", neon_color)
	($Light as OmniLight3D).light_color = neon_color
	super._ready()


## The tubes' steadiness, 1 most of the time and a brief dip every few seconds. A function of `at`.
static func buzz(at: float) -> float:
	var dip := sin(at * 2.3) * sin(at * 3.7 + 1.0)
	return 0.55 if dip > 0.93 else 1.0 - 0.05 * sin(at * 40.0)


func _apply() -> void:
	var f := level * buzz(phase)
	_frame.emission_energy_multiplier = f * LightTuning.current().neon_tube_energy
	_frame.albedo_color = neon_color * lerpf(0.2, 1.0, level)
	_text.modulate = neon_color.lerp(Color.WHITE, 0.35) * (0.15 + 0.85 * f)
	_halo.set_shader_parameter(&"energy", f * LightTuning.current().neon_halo_energy)
	($Halo as MeshInstance3D).visible = level > 0.0
