class_name MuzzleFlash
extends Node3D
## The flash of a shot at a muzzle, drawn in the game's toon style from three flat quads and one
## shader (`flash_star.gdshader`): a big spiky star and a smaller one spun against it, both facing
## the camera, and a teardrop tongue along the barrel. Each shot spins and scales them a little, so
## no two flashes are the same, and they live `frames` rendered frames. An optional warm light
## lights the same frames; only one flash on the map holds the light at a time, so it adds at most
## one light to the Compatibility renderer's cap of 8 per mesh (docs/research/shot-feedback.md).
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

## How many rendered frames a flash stays (1 to 3: it is a flash, not a fire).
@export_range(1, 3) var frames := 2
## Each shot scales the quads by a random factor in this range.
@export var scale_range := Vector2(0.8, 1.25)
## The small star is this fraction of the big one, and the tongue this many times its length.
@export_range(0.0, 1.0) var small_star := 0.6
@export var tongue_length := 1.7
@export var rim_colour := Color(1.0, 0.5, 0.1)
@export var core_colour := Color(1.0, 0.93, 0.62)
@export_group("Light")
## A warm light for the same frames. At most one flash on the map holds it at a time.
@export var light_enabled := true
@export var light_energy := 1.3
@export var light_range := 2.6

## Rendered frames the flash has been up, or `frames + 1` when it is down.
var age := 0
## Where the visuals are for tests: the three quads (big star, small star, tongue) and the light.
var quads: Array[MeshInstance3D] = []
var light: OmniLight3D

var _rng := RandomNumberGenerator.new()
var _size := 0.3
var _spin := 0.0
var _grow := 1.0
var _barrel := Vector3.FORWARD
var _star_material: ShaderMaterial
var _tongue_material: ShaderMaterial


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
	visible = true
	_place()
	_hold_light(true)
	set_process(true)


## Seeds the random spin and size of the flashes, so a test or a capture draws the same ones.
func seed_random(value: int) -> void:
	_rng.seed = value


func _process(_delta: float) -> void:
	age += 1
	if age > frames:
		visible = false
		set_process(false)
		_hold_light(false)
		return
	_place()


func _exit_tree() -> void:
	_hold_light(false)


func _build() -> void:
	_star_material = _make_material(0.0)
	_tongue_material = _make_material(1.0)
	for i in 3:
		var quad := MeshInstance3D.new()
		quad.mesh = QuadMesh.new()
		quad.material_override = _tongue_material if i == 2 else _star_material
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.top_level = true
		add_child(quad)
		quads.append(quad)
	light = OmniLight3D.new()
	light.visible = false
	light.shadow_enabled = false
	add_child(light)


func _make_material(shape: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"shape", shape)
	material.set_shader_parameter(&"rim_colour", rim_colour)
	material.set_shader_parameter(&"core_colour", core_colour)
	return material


## Turns the quads to the camera and the barrel, at the node's place.
func _place() -> void:
	var at := global_position
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var back := (camera.global_position - at).normalized() if camera != null else Vector3.BACK
	if back.length() < 0.5:
		back = Vector3.BACK
	var face := Basis.looking_at(-back, Vector3.UP)
	var spin := Basis(Vector3.BACK, _spin)
	var big := _size * _grow
	quads[0].global_transform = Transform3D((face * spin).scaled_local(Vector3.ONE * big), at)
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
