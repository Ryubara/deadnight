class_name ElementFx
extends Node3D
## What a re-cut weapon's element looks like on a client: a ring of light round a blast, the
## crackle of an arc from one zombie to the next, and the fire a burning flare leaves on the ground.
## It draws what the server decided (`element_burst`, `element_arc`, `fire_patch_started`) in the
## colour of the element (`ElementDef.tint`) and decides nothing. Unshaded, no light and no shader
## of its own (the lot's light cap leaves room for a flash and a blast only), so nothing is built
## the first time one is drawn that a warm-up does not already hold.

enum Kind { BLAST, ARC, FIRE }

## A blast's shell swells to its radius and fades in this long.
const BLAST_SECONDS := 0.32
## An arc crackles for this long, redrawn this many times a second.
const ARC_SECONDS := 0.18
const ARC_REDRAW_HZ := 30.0
## An arc is drawn in this many straight pieces, each pushed this far off the straight line.
const ARC_PIECES := 5
const ARC_JITTER := 0.14
## The fire patch: how thick the disc is, how fast its flames flicker, and how long it fades.
const FIRE_THICKNESS := 0.04
const FIRE_FLICKER_HZ := 9.0
const FIRE_FADE_SECONDS := 1.0
const FIRE_EMBERS := 24
const FIRE_EMBER_SECONDS := 0.9
const FIRE_EMBER_RISE := 1.6
const FIRE_EMBER_SIZE := 0.16

var kind: Kind = Kind.BLAST
var tint := Color.WHITE
var seconds := 0.0

var _age := 0.0
var _radius := 1.0
var _shell: MeshInstance3D
var _material: StandardMaterial3D
var _lines: MeshInstance3D
var _mesh: ImmediateMesh
var _from := Vector3.ZERO
var _ends: Array[Vector3] = []
var _seed := 0
var _embers: GPUParticles3D
var _core: MeshInstance3D
var _core_material: StandardMaterial3D


## A blast of `radius` bursting at `at`.
static func blast(at: Vector3, radius: float, colour: Color) -> ElementFx:
	var fx := ElementFx.new()
	fx.kind = Kind.BLAST
	fx.tint = colour
	fx.seconds = BLAST_SECONDS
	fx._radius = radius
	fx.position = at
	return fx


## An arc from `from` to each point of `ends`, `variation` making the crackle differ from the last.
static func arc(
	from: Vector3, ends: Array[Vector3], colour: Color, variation: int = 0
) -> ElementFx:
	var fx := ElementFx.new()
	fx.kind = Kind.ARC
	fx.tint = colour
	fx.seconds = ARC_SECONDS
	fx._from = from
	fx._ends = ends
	fx._seed = variation
	return fx


## A patch of fire of `radius` at `at` that burns for `for_seconds`.
static func fire(at: Vector3, radius: float, for_seconds: float, colour: Color) -> ElementFx:
	var fx := ElementFx.new()
	fx.kind = Kind.FIRE
	fx.tint = colour
	fx.seconds = for_seconds
	fx._radius = radius
	fx.position = at
	return fx


func _ready() -> void:
	match kind:
		Kind.BLAST:
			_make_shell(SphereMesh.new())
			_make_core()
		Kind.ARC:
			_make_arc()
		Kind.FIRE:
			_make_fire()
	_apply()


func _process(delta: float) -> void:
	advance(delta)


## Moves the effect on by `delta` seconds; it frees itself when its time is up.
func advance(delta: float) -> void:
	_age += delta
	if _age >= seconds:
		queue_free()
		return
	_apply()


## Stops the effect at `at_progress` (0 to 1) and keeps it there: the warm-up draws it still.
func freeze(at_progress: float) -> void:
	set_process(false)
	_age = clampf(at_progress, 0.0, 0.99) * seconds
	_apply()


## How far through its life the effect is, 0 to 1.
func progress() -> float:
	return clampf(_age / maxf(seconds, 0.001), 0.0, 1.0)


func _apply() -> void:
	match kind:
		Kind.BLAST:
			_apply_blast()
		Kind.ARC:
			_draw_arc()
		Kind.FIRE:
			_apply_fire()


func _unshaded(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = colour
	return material


func _make_shell(mesh: PrimitiveMesh) -> void:
	_material = _unshaded(tint)
	mesh.material = _material
	_shell = MeshInstance3D.new()
	_shell.mesh = mesh
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)


func _make_core() -> void:
	var ball := SphereMesh.new()
	ball.radius = _radius * 0.35
	ball.height = _radius * 0.7
	ball.radial_segments = 12
	ball.rings = 6
	_core_material = _unshaded(tint.lightened(0.6))
	ball.material = _core_material
	_core = MeshInstance3D.new()
	_core.mesh = ball
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)


func _apply_blast() -> void:
	var t := progress()
	var swell := 1.0 - pow(1.0 - t, 3.0)
	var mesh := _shell.mesh as SphereMesh
	mesh.radius = _radius
	mesh.height = _radius * 2.0
	_shell.scale = Vector3.ONE * maxf(swell, 0.05)
	_material.albedo_color = Color(tint, 0.8 * (1.0 - t) * (1.0 - t))
	# The core: a hot white-ish ball a third as wide, gone in the first half of the burst.
	_core.scale = Vector3.ONE * (0.3 + 0.7 * swell)
	_core_material.albedo_color = Color(tint.lightened(0.6), clampf(1.0 - t * 2.0, 0.0, 1.0))


func _make_arc() -> void:
	_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	_lines.material_override = _unshaded(tint)
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)


## Redraws the arcs: a crackling line from the point to each end, its shape new every redraw.
func _draw_arc() -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	var redraw := floori(_age * ARC_REDRAW_HZ)
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in _ends.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([_seed, redraw, index])
		var previous := _from
		for piece in range(1, ARC_PIECES + 1):
			var along := float(piece) / float(ARC_PIECES)
			var next := _from.lerp(_ends[index], along)
			if piece < ARC_PIECES:
				next += (
					Vector3(
						rng.randf_range(-1.0, 1.0),
						rng.randf_range(-1.0, 1.0),
						rng.randf_range(-1.0, 1.0)
					)
					* ARC_JITTER
				)
			_mesh.surface_add_vertex(previous)
			_mesh.surface_add_vertex(next)
			previous = next
	_mesh.surface_end()
	var fade := 1.0 - progress()
	(_lines.material_override as StandardMaterial3D).albedo_color = Color(tint, fade)


func _make_fire() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = _radius
	disc.bottom_radius = _radius
	disc.height = FIRE_THICKNESS
	disc.radial_segments = 24
	disc.rings = 1
	_make_shell(disc)
	_shell.position.y = FIRE_THICKNESS
	_embers = _make_embers()
	add_child(_embers)
	_embers.emitting = true


func _apply_fire() -> void:
	var fade := clampf((seconds - _age) / FIRE_FADE_SECONDS, 0.0, 1.0)
	var flicker := sin(_age * FIRE_FLICKER_HZ) * sin(_age * FIRE_FLICKER_HZ * 1.7)
	var strength := 0.34 + 0.12 * (flicker * 0.5 + 0.5)
	_material.albedo_color = Color(tint, strength * fade)
	_shell.scale = Vector3(
		1.0 - 0.04 * (flicker * 0.5 + 0.5), 1.0, 1.0 - 0.04 * (flicker * 0.5 + 0.5)
	)
	_embers.emitting = fade >= 1.0


func _make_embers() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = FIRE_EMBERS
	particles.lifetime = FIRE_EMBER_SECONDS
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 20.0
	process.initial_velocity_min = FIRE_EMBER_RISE * 0.5
	process.initial_velocity_max = FIRE_EMBER_RISE
	process.gravity = Vector3.ZERO
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	process.emission_sphere_radius = _radius * 0.9
	process.scale_min = 0.6
	process.scale_max = 1.0
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * FIRE_EMBER_SIZE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = tint.lightened(0.25)
	quad.material = material
	particles.draw_pass_1 = quad
	return particles
