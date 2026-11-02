class_name LureView
extends Node3D
## A flare burning where it landed while it calls the dead: a hot core, a flickering halo and a
## column of rising embers, for the `seconds` the server's `lure_started` said, fading out over the
## last of them. It draws what the server decided and decides nothing. No light: the lot's light
## cap leaves room for a flash and a blast only (`test_lot_light_cap`).

## The look (`shot_fx_tuning_default.tres`, "Lure on the ground" and "Lure embers").
var fx := ShotFxTuning.shipped()
var seconds := 8.0

var _age := 0.0
var _halo: MeshInstance3D
var _core_material: StandardMaterial3D
var _halo_material: StandardMaterial3D
var _embers: GPUParticles3D


## Starts burning at `at` for `for_seconds`.
func burn(at: Vector3, for_seconds: float) -> void:
	seconds = for_seconds
	position = at + fx.lure_lift


func _ready() -> void:
	var core := _ball(fx.lure_core_radius, fx.lure_core_colour, 1.0)
	_core_material = (core.mesh as SphereMesh).material as StandardMaterial3D
	add_child(core)
	_halo = _ball(fx.lure_halo_radius, fx.lure_halo_colour, fx.lure_halo_alpha)
	_halo_material = (_halo.mesh as SphereMesh).material as StandardMaterial3D
	add_child(_halo)
	_embers = _make_embers()
	add_child(_embers)
	_embers.emitting = true


func _process(delta: float) -> void:
	_age += delta
	if _age >= seconds:
		queue_free()
		return
	var flicker := sin(_age * fx.lure_flicker_rate_a) * sin(_age * fx.lure_flicker_rate_b)
	_halo.scale = Vector3.ONE * (1.0 - fx.lure_flicker_depth * (flicker * 0.5 + 0.5))
	var fade := clampf((seconds - _age) / fx.lure_fade_seconds, 0.0, 1.0)
	_core_material.albedo_color.a = fade
	_halo_material.albedo_color.a = fade * fx.lure_halo_alpha
	_embers.emitting = fade >= 1.0


func _ball(radius: float, colour: Color, alpha: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(colour, alpha)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _make_embers() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = fx.lure_ember_count
	particles.lifetime = fx.lure_ember_seconds
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = fx.lure_ember_rise * 0.5
	process.initial_velocity_max = fx.lure_ember_rise
	process.gravity = Vector3.ZERO
	process.scale_min = 0.6
	process.scale_max = 1.0
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * fx.lure_ember_size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = fx.lure_core_colour
	quad.material = material
	particles.draw_pass_1 = quad
	return particles
