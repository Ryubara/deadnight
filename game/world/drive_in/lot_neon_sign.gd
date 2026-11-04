class_name LotNeonSign
extends LightFollower
## A neon sign over a door: a dark board, a lit frame, the word, a halo, and a lamp of its own
## (`Light`, in the `powered_light` group, so it hangs on the circuit of the `Lamps` group the
## sign is placed in). The lamp is a spot facing out from the wall, so it lights nothing behind
## the sign's plane (an omni lit the room through the wall, issue #832). The tubes follow the
## lamp's level with a buzz: now and then one drops out for an instant, a function of the phase
## alone.

## How far behind the sign's face its wall may be.
const WALL_REACH := 0.6

@export var text := "OPEN"
@export var neon_color := Color(1.0, 0.25, 0.5)
## The halo shows from the sign's face only (a sign on a free-standing board has no glow behind it).
@export var halo_front_only := false
## The lamp's cone, in degrees. The light-cap count takes a cone by the box of its widest end
## (`LightReach`), so a sign over a quiet corner keeps its cone narrow.
@export_range(10.0, 89.0, 1.0, "suffix:°") var light_angle := 85.0
## The lamp lights the ground for the rules too (the dead slow down off lit ground), not only the
## picture.
@export var lights_ground := false

var _frame: StandardMaterial3D
var _halo: ShaderMaterial
var _text: Label3D


func _ready() -> void:
	light_path = ^"Light"
	_text = $Text as Label3D
	_text.text = text
	_frame = ($Frame/Top as MeshInstance3D).material_override.duplicate() as StandardMaterial3D
	_merge_the_tubes()
	_frame.albedo_color = neon_color
	_frame.emission = neon_color
	_halo = ($Halo as MeshInstance3D).material_override.duplicate() as ShaderMaterial
	($Halo as MeshInstance3D).material_override = _halo
	_halo.set_shader_parameter(&"tint", neon_color)
	_halo.set_shader_parameter(&"front_only", halo_front_only)
	_keep_the_halo_on_the_wall()
	($Light as Light3D).light_color = neon_color
	($Light as SpotLight3D).spot_angle = light_angle
	($Light as Light3D).set_meta(&"decor", not lights_ground)
	super._ready()


## The four tubes of the frame are drawn as one mesh (one draw call, not four: #728's budget).
func _merge_the_tubes() -> void:
	var frame := $Frame as Node3D
	var surface := SurfaceTool.new()
	var tubes := frame.get_children()
	for tube: MeshInstance3D in tubes:
		surface.append_from(tube.mesh, 0, tube.transform)
		frame.remove_child(tube)
		tube.free()
	var merged := MeshInstance3D.new()
	merged.name = "Tubes"
	merged.mesh = surface.commit()
	merged.material_override = _frame
	merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame.add_child(merged)


## The halo is a flat card on the wall's face: it stops at the top of the wall it hangs on, so it
## does not show in the air over the roof from behind (`GlowClip`). The sign's face is its +Z.
func _keep_the_halo_on_the_wall() -> void:
	var halo := $Halo as Node3D
	var planes := GlowClip.top_of_wall_behind(
		halo.global_position, -global_basis.z, WALL_REACH, GlowClip.walls(owner)
	)
	GlowClip.apply(_halo, planes)


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
