class_name GrenadeTrail
extends MultiMeshInstance3D
## The fading dots a flying grenade leaves behind, as one `MultiMesh`: a ring of `CAP` dots drawn
## in one call with one shared low-poly sphere and one shared material, the fade carried by each
## dot's own colour alpha. Nothing is made per dot (it was a 4,224-triangle sphere, a material, a
## node and a tween each, about 30 a second; Deadnight #936). A dot past the cap takes over the
## oldest one's place, and a dot that has faded is not drawn.
##
## The dots age by the time `advance` is given (the view's step), not by a clock of their own, so
## a fixed-step run fades them the same way every time, and the node does no work between steps
## once the last dot is gone.

const COLOUR := Color(1.0, 0.85, 0.4)
const SECONDS := 0.9
const RADIUS := 0.05
## 12 x 6 segments (168 triangles) keeps a round outline at the closest a trail is seen, where the
## default 64 x 32 was 4,224 triangles a dot.
const RADIAL_SEGMENTS := 12
const RINGS := 6
## Dots live at once at most: 30 a second for `SECONDS` is 27.
const CAP := 32
## A multimesh instance is a 3 x 4 transform and a colour, 16 floats.
const FLOATS := 16
## Culling box, centred on the world origin: the dots are placed in world space.
const REACH := 400.0

## The one mesh and the one material of every trail in the process. A material that is freed takes
## its shader with it, so they are kept here for the process's life (and drawn once by the night's
## warm-up).
static var _mesh: SphereMesh
static var _material: StandardMaterial3D

var _buffer := PackedFloat32Array()
## Seconds each slot has lived, or -1.0 for a slot with no dot.
var _ages := PackedFloat32Array()
var _next := 0
var _live := 0


static func shared_mesh() -> SphereMesh:
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = RADIUS
		_mesh.height = RADIUS * 2.0
		_mesh.radial_segments = RADIAL_SEGMENTS
		_mesh.rings = RINGS
		_mesh.material = shared_material()
	return _mesh


static func shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.vertex_color_use_as_albedo = true
		_material.albedo_color = COLOUR
	return _material


func _init() -> void:
	# The dots sit in world space whatever the grenade's own scale and turn are.
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -REACH, Vector3.ONE * REACH * 2.0)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var dots := MultiMesh.new()
	dots.transform_format = MultiMesh.TRANSFORM_3D
	dots.use_colors = true
	dots.mesh = shared_mesh()
	dots.instance_count = CAP
	multimesh = dots
	_buffer.resize(CAP * FLOATS)
	_ages.resize(CAP)
	_ages.fill(-1.0)
	_hide_all()
	visible = false


## How many dots are alive.
func live_count() -> int:
	return _live


## The alpha of each live dot, by slot (for tests: a multimesh cannot be read back headless).
func alphas() -> Array[float]:
	var found: Array[float] = []
	for slot in CAP:
		if _ages[slot] >= 0.0:
			found.append(_buffer[slot * FLOATS + 15])
	return found


## Leaves a dot at `at` (world space), the oldest one's place when the ring is full.
func drop(at: Vector3) -> void:
	if _ages[_next] >= 0.0:
		_live -= 1
	_ages[_next] = 0.0
	_live += 1
	_write(_next, at, 1.0)
	_next = (_next + 1) % CAP
	multimesh.buffer = _buffer
	visible = true


## Ages every dot by `delta` seconds and fades it; a dot that is out of time goes.
func advance(delta: float) -> void:
	if _live == 0:
		return
	for slot in CAP:
		var age := _ages[slot]
		if age < 0.0:
			continue
		age += delta
		var base := slot * FLOATS
		if age >= SECONDS:
			_ages[slot] = -1.0
			_live -= 1
			_clear(slot)
		else:
			_ages[slot] = age
			_buffer[base + 15] = 1.0 - age / SECONDS
	multimesh.buffer = _buffer
	visible = _live > 0


func _write(slot: int, at: Vector3, alpha: float) -> void:
	var base := slot * FLOATS
	# Rows of the 3 x 4 transform: the basis (here the identity) and the origin as the last column.
	_buffer[base + 0] = 1.0
	_buffer[base + 1] = 0.0
	_buffer[base + 2] = 0.0
	_buffer[base + 3] = at.x
	_buffer[base + 4] = 0.0
	_buffer[base + 5] = 1.0
	_buffer[base + 6] = 0.0
	_buffer[base + 7] = at.y
	_buffer[base + 8] = 0.0
	_buffer[base + 9] = 0.0
	_buffer[base + 10] = 1.0
	_buffer[base + 11] = at.z
	_buffer[base + 12] = 1.0
	_buffer[base + 13] = 1.0
	_buffer[base + 14] = 1.0
	_buffer[base + 15] = alpha


## An empty slot: no size, so it draws nothing.
func _clear(slot: int) -> void:
	var base := slot * FLOATS
	for i in FLOATS:
		_buffer[base + i] = 0.0


func _hide_all() -> void:
	_buffer.fill(0.0)
	multimesh.buffer = _buffer
