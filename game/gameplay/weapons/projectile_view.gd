class_name ProjectileView
extends Node3D
## What a flare (or any projectile weapon's shot) in flight looks like: a hot core, a flickering
## soft halo and a short trail of fading sparks. It follows a `ProjectileState`, the
## client's copy of the server's shot, and decides nothing: the server's `projectile_burst` ends it.

## The core is drawn this many times the shot's hit radius, so it reads from the shoulder camera.
const CORE_SCALE := 1.3
const HALO_SCALE := 3.5
const HALO_ALPHA := 0.28
const CORE_COLOUR := Color(1.0, 0.82, 0.55)
const HALO_COLOUR := Color(1.0, 0.45, 0.18)
## The halo's flicker: a product of two sines of the shot's age, so it is the same every run. It
## lights nothing: a light per flare would take a third slot on the meshes a fight already gives
## a flash and a blast (`test_lot_light_cap`).
const FLICKER_DEPTH := 0.3
const FLICKER_RATE_A := 31.0
const FLICKER_RATE_B := 47.0
const TRAIL_EVERY := 2
const TRAIL_SECONDS := 0.5
const TRAIL_RADIUS := 0.05

var state: ProjectileState

var _halo: MeshInstance3D
var _steps := 0


func _ready() -> void:
	var radius := state.def.projectile_radius
	add_child(_ball(radius * CORE_SCALE, CORE_COLOUR, 1.0))
	_halo = _ball(radius * HALO_SCALE, HALO_COLOUR, HALO_ALPHA)
	add_child(_halo)
	follow()


## Moves to where the state is and flickers the halo, for one step.
func follow() -> void:
	position = state.position
	_steps += 1
	var flicker := sin(state.age * FLICKER_RATE_A) * sin(state.age * FLICKER_RATE_B)
	_halo.scale = Vector3.ONE * (1.0 - FLICKER_DEPTH * (flicker * 0.5 + 0.5))
	if _steps % TRAIL_EVERY == 0:
		_drop_trail_dot()


static func _ball(radius: float, colour: Color, alpha: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(colour, alpha)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _drop_trail_dot() -> void:
	var dot := _ball(TRAIL_RADIUS, HALO_COLOUR, 1.0)
	var material := (dot.mesh as SphereMesh).material as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.top_level = true
	add_child(dot)
	dot.global_position = state.position
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, TRAIL_SECONDS)
	tween.tween_callback(dot.queue_free)
