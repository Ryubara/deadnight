class_name ProjectileView
extends Node3D
## What a flare (or any projectile weapon's shot) in flight looks like: a hot core, a flickering
## soft halo and a short trail of fading sparks. It follows a `ProjectileState`, the
## client's copy of the server's shot, and decides nothing: the server's `projectile_burst` ends it.

## The look (`shot_fx_tuning_default.tres`, "Flare in flight"): the core's and halo's size, the
## halo's flicker (a product of two sines of the shot's age, so it is the same every run; it lights
## nothing, a light per flare would take a third slot on the meshes a fight already gives a flash
## and a blast, `test_lot_light_cap`) and the trail.
var fx := ShotFxTuning.shipped()
var state: ProjectileState

var _halo: MeshInstance3D
var _halo_colour: Color
var _steps := 0


func _ready() -> void:
	var radius := state.def.projectile_radius
	var core := fx.flare_core_colour
	_halo_colour = fx.flare_halo_colour
	# A weapon with colours of its own (the ray gun's blue bolt) draws them instead of the flare's.
	if state.def.has_bolt_colours():
		core = state.def.bolt_core_colour
		_halo_colour = state.def.bolt_halo_colour
	add_child(_ball(radius * fx.flare_core_scale, core, 1.0))
	_halo = _ball(radius * fx.flare_halo_scale, _halo_colour, fx.flare_halo_alpha)
	add_child(_halo)
	follow()


## Moves to where the state is and flickers the halo, for one step.
func follow() -> void:
	position = state.position
	_steps += 1
	var flicker := (
		sin(state.age * fx.flare_flicker_rate_a) * sin(state.age * fx.flare_flicker_rate_b)
	)
	_halo.scale = Vector3.ONE * (1.0 - fx.flare_flicker_depth * (flicker * 0.5 + 0.5))
	if _steps % fx.flare_trail_every == 0:
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
	var dot := _ball(fx.flare_trail_radius, _halo_colour, 1.0)
	var material := (dot.mesh as SphereMesh).material as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.top_level = true
	add_child(dot)
	dot.global_position = state.position
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, fx.flare_trail_seconds)
	tween.tween_callback(dot.queue_free)
