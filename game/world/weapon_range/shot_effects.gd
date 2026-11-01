class_name ShotEffects
extends Node3D
## The instant, client-side look of a shot: muzzle flash, impact spark and puff, damage number, and
## a tracer only for a weapon that asks for one (`WeaponDef.tracer`). All of it is predicted from
## the shooter's own view and needs no answer from the server.

const TRACER_COLOUR := Color(1.0, 0.86, 0.45)
const TRACER_RADIUS := 0.02
const TRACER_SECONDS := 0.3
const FLASH_SECONDS := 0.2
const FLASH_ENERGY := 3.0
const NUMBER_SECONDS := 1.0
const NUMBER_RISE := 0.8
const HEAD_COLOUR := Color(1.0, 0.45, 0.35)
const BODY_COLOUR := Color(1.0, 1.0, 1.0)
const PUFF_COLOUR := Color(0.78, 0.74, 0.66, 0.55)
const PUFF_RADIUS := 0.1
const PUFF_GROWTH := 2.6
const PUFF_SECONDS := 0.35
## A shot that ended within this many metres of its range hit something.
const RANGE_SLACK := 0.1

## Streaks drawn so far, for tests.
var tracers_drawn := 0


func _init() -> void:
	# Tweens on the drawn frame move these, not the physics tick: the engine's physics
	# interpolation (docs/research/physics-interpolation.md) would blend them a tick late.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## The look of one shot of `def` from `muzzle` that ended at each of `ends` (one per pellet): the
## muzzle flash, then at every end that stopped short of the weapon's range an impact (a spark and a
## puff of dust). A streak only when the weapon asks for one. A projectile weapon draws nothing
## here: its body flies and bursts.
func shot(def: WeaponDef, muzzle: Vector3, ends: Array) -> void:
	muzzle_flash(muzzle)
	if def.is_projectile():
		return
	for end: Vector3 in ends:
		if def.tracer:
			tracer(muzzle, end)
		if not def.is_melee() and muzzle.distance_to(end) < def.max_range - RANGE_SLACK:
			impact(end)


## A spark and a puff of dust where a shot landed.
func impact(at: Vector3) -> void:
	spark(at)
	puff(at)


## Dust that swells and fades.
func puff(at: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = PUFF_COLOUR
	var mesh := SphereMesh.new()
	mesh.radius = PUFF_RADIUS
	mesh.height = PUFF_RADIUS * 2.0
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	add_child(instance)
	var tween := create_tween().set_parallel()
	tween.tween_property(instance, "scale", Vector3.ONE * PUFF_GROWTH, PUFF_SECONDS)
	tween.tween_property(material, "albedo_color:a", 0.0, PUFF_SECONDS)
	tween.chain().tween_callback(instance.queue_free)


func tracer(from: Vector3, to: Vector3, radius: float = TRACER_RADIUS) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	tracers_drawn += 1
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6
	mesh.material = _glow(TRACER_COLOUR)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	instance.look_at_from_position((from + to) / 2.0, to, up)
	instance.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	_free_after(instance, TRACER_SECONDS)


func muzzle_flash(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_energy = FLASH_ENERGY
	light.omni_range = 5.0
	light.light_color = TRACER_COLOUR
	light.position = at
	add_child(light)
	_free_after(light, FLASH_SECONDS)
	_burst(at, 0.12)


func spark(at: Vector3) -> void:
	_burst(at, 0.1)


func number(at: Vector3, text: String, headshot: bool) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 56
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = HEAD_COLOUR if headshot else BODY_COLOUR
	label.outline_size = 12
	label.position = at
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", at.y + NUMBER_RISE, NUMBER_SECONDS)
	tween.tween_callback(label.queue_free)


func _burst(at: Vector3, radius: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = _glow(TRACER_COLOUR)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	add_child(instance)
	_free_after(instance, FLASH_SECONDS)


func _glow(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	return material


func _free_after(node: Node, seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(node.queue_free)
