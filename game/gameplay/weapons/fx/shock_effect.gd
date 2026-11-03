class_name ShockEffect
extends Node3D
## The picture of the shock perk's burst (`shock_burst`, docs/design/perks.md): a flat quad on the
## ground round the player with the shock shader (`shock_arc.gdshader`), a flash of the muzzle-flash
## star at the player's middle and the shake of the local player's view is the caller's. It lives
## `SECONDS`, steps itself by the frame time and frees itself. The shader's material is kept in a
## static, so its program is not freed with the last effect and built again at the next shock (the
## first-use hitch lesson, docs/research/first-use-hitches.md): the warm-up draws one of each.

const SHADER := preload("res://gameplay/weapons/fx/shock_arc.gdshader")
const SECONDS := 0.7
## The quad reaches this much past the shock's radius (the ring runs to 0.98 of its half width).
const MARGIN := 1.03
## The quad hangs this far over the ground, so it never z-fights the asphalt.
const LIFT := 0.06
## The bolts take a new shape this many times a second.
const CRACKLE_HZ := 14.0

static var _shared: ShaderMaterial

## The seconds the effect has been up.
var age := 0.0

var _material: ShaderMaterial
var _quad: MeshInstance3D
var _seed := 0.0


## The one material every shock uses (its shader stays loaded for the whole night).
static func shared_material() -> ShaderMaterial:
	if _shared == null:
		_shared = ShaderMaterial.new()
		_shared.shader = SHADER
	return _shared


## Draws a shock of `radius` metres at `at`; `variation` makes the bolts different from the last.
func play(at: Vector3, radius: float, variation: int = 0) -> void:
	position = at + Vector3(0.0, LIFT, 0.0)
	_seed = float(variation % 97)
	var mesh := QuadMesh.new()
	mesh.orientation = PlaneMesh.FACE_Y
	mesh.size = Vector2.ONE * radius * 2.0 * MARGIN
	_material = shared_material().duplicate() as ShaderMaterial
	_quad = MeshInstance3D.new()
	_quad.name = "Ground"
	_quad.mesh = mesh
	_quad.material_override = _material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	_apply()


func _process(delta: float) -> void:
	advance(delta)


## Moves the effect on by `delta` seconds.
func advance(delta: float) -> void:
	age += delta
	if age >= SECONDS:
		queue_free()
		return
	_apply()


## Stops the effect at `at_progress` (0 to 1) and keeps it there: the warm-up draws it still, so a
## slow frame that builds the shader's programs does not end it before it is drawn.
func freeze(at_progress: float) -> void:
	set_process(false)
	age = clampf(at_progress, 0.0, 0.99) * SECONDS
	_apply()


## How far through its life the effect is, 0 to 1.
func progress() -> float:
	return clampf(age / SECONDS, 0.0, 1.0)


func _apply() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"progress", progress())
	_material.set_shader_parameter(&"seed", _seed + floorf(age * CRACKLE_HZ) * 3.0)
