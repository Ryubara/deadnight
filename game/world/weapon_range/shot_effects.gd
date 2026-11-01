class_name ShotEffects
extends Node3D
## The instant, client-side look of a shot: tracer, muzzle flash, impact spark, damage number. All
## of it is predicted from the shooter's own view and needs no answer from the server.

const TRACER_COLOUR := Color(1.0, 0.86, 0.45)
const TRACER_RADIUS := 0.02
const TRACER_SECONDS := 0.3
const FLASH_SECONDS := 0.2
const FLASH_ENERGY := 3.0
const NUMBER_SECONDS := 1.0
const NUMBER_RISE := 0.8
const HEAD_COLOUR := Color(1.0, 0.45, 0.35)
const BODY_COLOUR := Color(1.0, 1.0, 1.0)


func tracer(from: Vector3, to: Vector3, radius: float = TRACER_RADIUS) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
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
