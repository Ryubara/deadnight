class_name GrenadeView
extends Node3D
## What a grenade in flight looks like: a placeholder olive shell with a spoon and a blinking
## lamp that blinks faster as the fuse runs out, so a player can time a cook.
##
## The seam for the real model: set `model` to the artist's scene and it is shown instead of the
## placeholder; the blink lamp stays. The view only follows a `GrenadeState` (the client's copy
## of the server's grenade); it decides nothing.

const SHELL_RADIUS := 0.09
const SHELL_COLOUR := Color(0.28, 0.33, 0.18)
const SPOON_COLOUR := Color(0.55, 0.55, 0.5)
const LAMP_COLOUR := Color(1.0, 0.2, 0.12)
const LAMP_ENERGY := 2.5
const LAMP_RANGE := 3.0
## Seconds between blinks at the start of the fuse and at the end.
const BLINK_SLOW := 0.5
const BLINK_FAST := 0.07
const TRAIL_EVERY := 2
const TRAIL_SECONDS := 0.9
const TRAIL_COLOUR := Color(1.0, 0.85, 0.4)

## The artist's grenade, when there is one. Null shows the placeholder.
@export var model: PackedScene
## Draws the grenade this many times its size (a test range is seen from far away).
@export var visual_scale: float = 1.0
## Leaves a fading trail of dots behind the grenade, to read the arc and the bounces.
@export var trail: bool = false

var state: GrenadeState
## Set when the state was just replaced by the server's: the next step of this view is skipped.
var settled := false

var _lamp_mesh: MeshInstance3D
var _lamp_material: StandardMaterial3D
var _light: OmniLight3D
var _blink_clock := 0.0
var _trail_steps := 0


func _ready() -> void:
	scale = Vector3.ONE * visual_scale
	if model != null:
		add_child(model.instantiate())
	else:
		add_placeholder(self)
	_build_lamp()


## Follows the state for one step of `delta`.
func follow(delta: float) -> void:
	position = state.position
	_trail_steps += 1
	if trail and _trail_steps % TRAIL_EVERY == 0 and not state.at_rest:
		_drop_trail_dot()
	var progress := 1.0 - clampf(state.fuse_left / state.def.fuse, 0.0, 1.0)
	var period := lerpf(BLINK_SLOW, BLINK_FAST, progress * progress)
	_blink_clock += delta
	var on := fposmod(_blink_clock, period) < period * 0.5
	_lamp_material.albedo_color = LAMP_COLOUR if on else LAMP_COLOUR.darkened(0.8)
	_light.visible = on
	if not state.at_rest and not state.grounded:
		rotation += state.velocity.normalized().cross(Vector3.UP) * delta * 6.0


## Adds the placeholder shell and spoon to `parent` (the Soldier's hand shows the same one).
static func add_placeholder(parent: Node3D) -> void:
	var shell := SphereMesh.new()
	shell.radius = SHELL_RADIUS
	shell.height = SHELL_RADIUS * 2.0
	shell.material = _material(SHELL_COLOUR)
	var body := MeshInstance3D.new()
	body.mesh = shell
	parent.add_child(body)
	var spoon := BoxMesh.new()
	spoon.size = Vector3(0.025, 0.11, 0.045)
	spoon.material = _material(SPOON_COLOUR)
	var lever := MeshInstance3D.new()
	lever.mesh = spoon
	lever.position = Vector3(0.0, SHELL_RADIUS * 0.9, 0.0)
	parent.add_child(lever)


func _build_lamp() -> void:
	var bulb := SphereMesh.new()
	bulb.radius = 0.035
	bulb.height = 0.07
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_material.albedo_color = LAMP_COLOUR
	bulb.material = _lamp_material
	_lamp_mesh = MeshInstance3D.new()
	_lamp_mesh.mesh = bulb
	_lamp_mesh.position = Vector3(0.0, 0.0, SHELL_RADIUS)
	add_child(_lamp_mesh)
	_light = OmniLight3D.new()
	_light.light_color = LAMP_COLOUR
	_light.light_energy = LAMP_ENERGY
	_light.omni_range = LAMP_RANGE
	_light.position = _lamp_mesh.position
	add_child(_light)


static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.7
	return material


func _drop_trail_dot() -> void:
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = TRAIL_COLOUR
	dot.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = dot
	instance.top_level = true
	add_child(instance)
	instance.global_position = state.position
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, TRAIL_SECONDS)
	tween.tween_callback(instance.queue_free)
