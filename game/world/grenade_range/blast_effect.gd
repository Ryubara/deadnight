class_name BlastEffect
extends Node3D
## The look of a blast, client only: a fireball and a ring that grow to the blast radius, a flash
## of light, a scorch mark on the floor and a few gibs. None of it changes anything the server
## decided. Effects last long enough to land on a 10 fps capture (a frame is 0.1 s).

const FIREBALL_COLOUR := Color(1.0, 0.62, 0.22)
const RING_COLOUR := Color(1.0, 0.85, 0.5, 0.35)
const SCORCH_COLOUR := Color(0.03, 0.03, 0.03, 0.85)
const GIB_COLOUR := Color(0.42, 0.12, 0.1)
const FIREBALL_SECONDS := 0.7
const RING_SECONDS := 0.5
const FLASH_ENERGY := 12.0
const SCORCH_SECONDS := 6.0
const GIB_SECONDS := 1.4
const GIB_GRAVITY := 14.0

var _gibs: Array[Dictionary] = []


## Plays a blast at `point` with the grenade's radii.
func play(point: Vector3, def: GrenadeDef) -> void:
	position = point
	_fireball(def.core_radius)
	_ring(def.blast_radius)
	_flash(def.blast_radius)
	_scorch(point, def.core_radius)


## A little burst of gibs from where a zombie stood, thrown along `impulse`.
func gibs(at: Vector3, impulse: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _i in 6:
		var mesh := BoxMesh.new()
		var size := rng.randf_range(0.07, 0.16)
		mesh.size = Vector3(size, size, size)
		mesh.material = _flat(GIB_COLOUR)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = to_local(at)
		add_child(instance)
		var kick := Vector3(
			rng.randf_range(-1, 1), rng.randf_range(0.5, 1.8), rng.randf_range(-1, 1)
		)
		_gibs.append({"node": instance, "velocity": impulse * 0.5 + kick * 3.0, "age": 0.0})


func _process(delta: float) -> void:
	for gib in _gibs:
		gib["age"] += delta
		gib["velocity"] += Vector3.DOWN * GIB_GRAVITY * delta
		var node: Node3D = gib["node"]
		node.position += (gib["velocity"] as Vector3) * delta
		if gib["age"] > GIB_SECONDS:
			node.visible = false


func _fireball(radius: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.material = _glow(FIREBALL_COLOUR)
	var instance := MeshInstance3D.new()
	instance.mesh = sphere
	instance.scale = Vector3.ONE * 0.2
	add_child(instance)
	var tween := create_tween().set_parallel(true)
	(
		tween
		. tween_property(instance, "scale", Vector3.ONE * radius * 0.8, FIREBALL_SECONDS)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(sphere.material, "albedo_color:a", 0.0, FIREBALL_SECONDS)


func _ring(radius: float) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.material = _glow(RING_COLOUR)
	var instance := MeshInstance3D.new()
	instance.mesh = torus
	instance.position.y = -0.2
	instance.scale = Vector3(0.3, 0.3, 0.3)
	add_child(instance)
	var tween := create_tween().set_parallel(true)
	(
		tween
		. tween_property(instance, "scale", Vector3(radius, radius, radius), RING_SECONDS)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(torus.material, "albedo_color:a", 0.0, RING_SECONDS)


func _flash(radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = FIREBALL_COLOUR
	light.light_energy = FLASH_ENERGY
	light.omni_range = radius * 1.6
	add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, FIREBALL_SECONDS)


func _scorch(point: Vector3, radius: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(radius, radius)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = _flat(SCORCH_COLOUR)
	(quad.material as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.position = Vector3(0.0, 0.02 - point.y, 0.0)
	add_child(instance)
	var tween := create_tween()
	tween.tween_interval(SCORCH_SECONDS)
	tween.tween_property(quad.material, "albedo_color:a", 0.0, 1.0)


func _glow(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	return material


func _flat(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	return material
