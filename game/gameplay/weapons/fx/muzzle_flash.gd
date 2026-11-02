class_name MuzzleFlash
extends Node3D
## The flash of a shot at a muzzle, drawn in the game's toon style from three flat quads and one
## shader (`flash_star.gdshader`): a big spiky star and a smaller one spun against it, both facing
## the camera, and a teardrop tongue along the barrel. Each shot spins and scales them a little, so
## no two flashes are the same, and they live `frames` rendered frames and `seconds` at least. The
## quads are drawn `camera_lift` toward the camera so the gun and hands do not hide them, and the
## big star sits in a flat disc of glow (the Compatibility renderer has no glow of its own). An
## optional warm light lights the same time; only one flash on the map holds the light at a time, so
## it adds at most one light to the Compatibility renderer's cap of 8 per mesh
## (docs/research/shot-feedback.md).
##
## It hangs on the weapon's muzzle point (`MuzzleFlash.on(marker)`), or free-standing at a position
## for a weapon with no model. It draws nothing and costs nothing between shots. Every number is
## an export, editable in the Godot editor; the size of a weapon's flash is its
## `WeaponDef.flash_size`.

const SHADER := preload("res://gameplay/weapons/fx/flash_star.gdshader")
## The node's name under a muzzle point.
const NODE_NAME := &"MuzzleFlash"
## The group of the flash that holds the light now (one at a time on the whole map).
const LIT_GROUP := &"muzzle_flash_lit"

## A flash is drawn for at least this many rendered frames (1 to 6) and at least `seconds`: the
## frames keep it the same at 30 and 60 fps and in a 10 fps capture, the seconds keep it from
## being gone in 14 ms on a 144 Hz screen. At 60 fps that is 3 frames.
@export_range(1, 6) var frames := 3
## The least time a flash is drawn, in seconds (see `frames`).
@export_range(0.0, 0.2, 0.005) var seconds := 0.06
## Each shot scales the quads by a random factor in this range.
@export var scale_range := Vector2(0.85, 1.2)
## The flash is drawn this big when it starts and this big when it ends (a share of its size):
## it bursts and dies down, which reads as fire where a fixed picture reads as a sticker.
@export var life_scale := Vector2(1.15, 0.65)
## The small star is this fraction of the big one, and the tongue this many times its length.
@export_range(0.0, 1.0) var small_star := 0.6
@export var tongue_length := 1.7
## The quads are drawn this far (metres) toward the camera from the muzzle, and scaled down by the
## same ratio so they look the same size: the gun, the hands and the arm in front of the muzzle
## hid up to nine tenths of a flash drawn in the muzzle's own plane (docs/research/muzzle-flash.md).
@export var camera_lift := 0.7
## The flat disc round the big star, a glow in the toon style: its brightness (0 draws none) and
## the share of the quad the star itself fills.
@export_range(0.0, 1.0) var halo := 0.22
@export_range(0.3, 1.0) var halo_fill := 0.7
@export var rim_colour := Color(1.0, 0.5, 0.1)
@export var core_colour := Color(1.0, 0.96, 0.72)
@export_group("Light")
## A warm light for the same time. At most one flash on the map holds it at a time.
@export var light_enabled := true
@export var light_energy := 2.0
@export var light_range := 3.4
@export var light_colour := Color(1.0, 0.74, 0.42)
## The light sits this far (metres) ahead of the muzzle along the ground and this far above it:
## ahead so it lights what the gun points at, above so it never dips under the floor when the gun
## points down (a light under the ground lights none of it: the browser's first view looks down on
## the soldier and the rifle's flash lit only a few pixels).
@export var light_ahead := 0.15
@export var light_lift := 0.3

## Rendered frames the flash has been up, and the seconds, since it was fired; `age` is `frames + 1`
## or more when it is down.
var age := 0
var elapsed := 0.0
## Where the visuals are for tests: the three quads (big star, small star, tongue) and the light.
var quads: Array[MeshInstance3D] = []
var light: OmniLight3D

var _rng := RandomNumberGenerator.new()
var _size := 0.3
var _spin := 0.0
var _grow := 1.0
var _barrel := Vector3.FORWARD


## The flash that hangs on `marker`, made the first time it is asked for.
static func on(marker: Node3D) -> MuzzleFlash:
	var found := marker.get_node_or_null(NodePath(NODE_NAME)) as MuzzleFlash
	if found == null:
		found = MuzzleFlash.new()
		found.name = NODE_NAME
		marker.add_child(found)
	return found


## True while this flash is drawn.
func is_up() -> bool:
	return visible


func _init() -> void:
	_rng.seed = 1958
	visible = false
	set_process(false)
	# The quads are placed by hand on every drawn frame (`_place`), at the muzzle's drawn place: the
	# engine's physics interpolation would blend them a tick late.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build()


## Flashes at the node's own place: `size` metres across (a weapon's `flash_size`), the barrel
## pointing along `barrel` in the world. A size of 0 draws nothing.
func fire(size: float, barrel: Vector3) -> void:
	if size <= 0.0 or not is_inside_tree():
		return
	_size = size
	_barrel = barrel.normalized() if barrel.length() > 0.001 else Vector3.FORWARD
	_spin = _rng.randf() * TAU
	_grow = _rng.randf_range(scale_range.x, scale_range.y)
	age = 0
	elapsed = 0.0
	visible = true
	_place()
	_hold_light(true)
	set_process(true)


## Seeds the random spin and size of the flashes, so a test or a capture draws the same ones.
func seed_random(value: int) -> void:
	_rng.seed = value


func _process(delta: float) -> void:
	age += 1
	elapsed += delta
	if age > frames and elapsed >= seconds:
		visible = false
		set_process(false)
		_hold_light(false)
		return
	_place()


## How far through its life the flash is now, 0 at the shot to 1 at its end: the later of the two
## ways it has lived (frames and seconds), so it dies down over all of them.
func progress() -> float:
	return clampf(minf(float(age) / float(frames + 1), elapsed / maxf(seconds, 0.001)), 0.0, 1.0)


func _exit_tree() -> void:
	_hold_light(false)


func _build() -> void:
	for i in 3:
		var quad := MeshInstance3D.new()
		quad.mesh = QuadMesh.new()
		quad.material_override = _make_material(i)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.top_level = true
		add_child(quad)
		quads.append(quad)
	light = OmniLight3D.new()
	light.visible = false
	light.shadow_enabled = false
	light.light_color = light_colour
	add_child(light)


## The material of quad `index`: 0 the big star (with the halo), 1 the small star, 2 the tongue.
func _make_material(index: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"shape", 1.0 if index == 2 else 0.0)
	material.set_shader_parameter(&"rim_colour", rim_colour)
	material.set_shader_parameter(&"core_colour", core_colour)
	if index == 0 and halo > 0.0:
		material.set_shader_parameter(&"halo", halo)
		material.set_shader_parameter(&"star_fill", halo_fill)
	return material


## Turns the quads to the camera and the barrel, at the muzzle's drawn place and `camera_lift`
## toward the camera.
func _place() -> void:
	# Where the muzzle is drawn this frame: its own place, moved by how far the engine's physics
	# interpolation has carried the weapon (the body is drawn between ticks) from where it was set.
	var muzzle := global_position
	var anchor := get_parent() as Node3D
	if anchor != null:
		muzzle += anchor.get_global_transform_interpolated().origin - anchor.global_position
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var back := Vector3.BACK
	var distance := 4.0
	if camera != null:
		var to_camera := camera.global_position - muzzle
		distance = to_camera.length()
		if distance > 0.05:
			back = to_camera / distance
	var lift := minf(camera_lift, distance * 0.4)
	# Nearer the camera, so smaller by the same ratio: it looks the size it would at the muzzle.
	var fit := (distance - lift) / maxf(distance, 0.001)
	var at := muzzle + back * lift
	var face := Basis.looking_at(-back, Vector3.UP)
	var spin := Basis(Vector3.BACK, _spin)
	var burst := lerpf(life_scale.x, life_scale.y, progress())
	var big := _size * _grow * fit * burst
	var star := big / halo_fill if halo > 0.0 else big
	quads[0].global_transform = Transform3D((face * spin).scaled_local(Vector3.ONE * star), at)
	var small := Basis(Vector3.BACK, -_spin * 1.7 + 0.5)
	quads[1].global_transform = Transform3D(
		(face * small).scaled_local(Vector3.ONE * big * small_star), at
	)
	# The tongue lies along the barrel as the camera sees it; its tail sits on the muzzle.
	var along := _barrel - back * _barrel.dot(back)
	if along.length() < 0.05:
		quads[2].visible = false
	else:
		quads[2].visible = true
		along = along.normalized()
		var up := back.cross(along)
		var length := big * tongue_length
		var tongue := Basis(along * length, up * big * 0.55, back)
		quads[2].global_transform = Transform3D(tongue, at + along * length * 0.1)
	if light != null:
		light.light_energy = light_energy
		light.omni_range = light_range
		light.light_color = light_colour
		var level := Vector3(_barrel.x, 0.0, _barrel.z)
		level = level.normalized() if level.length() > 0.01 else Vector3.ZERO
		light.global_position = muzzle + level * light_ahead + Vector3.UP * light_lift


## Takes or gives up the one flash light.
func _hold_light(on: bool) -> void:
	if light == null:
		return
	if on and light_enabled and is_inside_tree():
		get_tree().call_group(LIT_GROUP, &"_drop_light")
		add_to_group(LIT_GROUP)
		light.visible = true
	else:
		_drop_light()


## Puts the light out (another flash took it, or this one is over).
func _drop_light() -> void:
	light.visible = false
	remove_from_group(LIT_GROUP)
