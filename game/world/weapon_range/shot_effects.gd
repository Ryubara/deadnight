class_name ShotEffects
extends Node3D
## The instant, client-side look of a shot: muzzle flash, impact spark and puff, damage number, and
## a tracer only for a weapon that asks for one (`WeaponDef.tracer`). All of it is predicted from
## the shooter's own view and needs no answer from the server.
##
## Nothing here is made or freed while a night is played. Each kind of effect has a small pool of
## nodes, made the first time they are wanted (the night's warm-up asks for every kind) and then
## lent out: a finished effect is hidden and waits for the next. The meshes and materials are
## shared or belong to one pooled node for good, so no shader is built again after a shot (a shader
## goes with the last material that uses it) and no shot or kill allocates, frees or builds
## anything. Animation is by `_process`, from the effect's age, not by tweens and timers.

enum Kind { FLASH, BURST, PUFF, TRACER, NUMBER }

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
## How many of each effect can be alive at once; past it the oldest of its kind is taken over.
const FLASH_POOL := 8
const BURST_POOL := 24
const PUFF_POOL := 16
const TRACER_POOL := 8
const NUMBER_POOL := 16

## Streaks drawn so far, for tests.
var tracers_drawn := 0

## Idle effects by kind, ready to lend.
var _idle: Array[Array] = [[], [], [], [], []]
var _made: Array[int] = [0, 0, 0, 0, 0]
var _live: Array[Live] = []
var _unit_sphere: SphereMesh
var _unit_tube: CylinderMesh
var _glow: StandardMaterial3D


func _init() -> void:
	set_process(false)


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
	var live := _lend(Kind.PUFF, PUFF_SECONDS)
	live.node.position = at
	(live.node as MeshInstance3D).scale = Vector3.ONE * PUFF_RADIUS
	_puff_material(live.node).albedo_color = PUFF_COLOUR


func tracer(from: Vector3, to: Vector3, radius: float = TRACER_RADIUS) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	tracers_drawn += 1
	var live := _lend(Kind.TRACER, TRACER_SECONDS)
	var instance := live.node as MeshInstance3D
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	instance.scale = Vector3.ONE
	instance.look_at_from_position((from + to) / 2.0, to, up)
	instance.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	# The unit tube is 1 m long and 1 m round: stretched to the streak.
	instance.scale = Vector3(radius, length, radius)


func muzzle_flash(at: Vector3) -> void:
	var live := _lend(Kind.FLASH, FLASH_SECONDS)
	live.node.position = at
	_burst(at, 0.12)


func spark(at: Vector3) -> void:
	_burst(at, 0.1)


func number(at: Vector3, text: String, headshot: bool) -> void:
	var live := _lend(Kind.NUMBER, NUMBER_SECONDS)
	var label := live.node as Label3D
	label.text = text
	label.modulate = HEAD_COLOUR if headshot else BODY_COLOUR
	label.position = at
	live.base = at.y


## Ends every effect on show now (they are hidden, and kept for the next ones).
func stop_all() -> void:
	for live in _live:
		_release(live)
	_live.clear()
	set_process(false)


## Whether `node` is one of the pooled effects (the warm-up frees only what is not).
func owns(node: Node) -> bool:
	for kind in _idle.size():
		for live: Live in _idle[kind]:
			if live.node == node:
				return true
	for live in _live:
		if live.node == node:
			return true
	return false


## Effects on show now, for tests.
func live_count() -> int:
	return _live.size()


## Effects on show of one kind, for tests.
func live_of(kind: Kind) -> int:
	var count := 0
	for live in _live:
		if live.kind == kind:
			count += 1
	return count


## Nodes made so far, for tests: it stops growing once every kind has met its busiest moment.
func nodes_made() -> int:
	var total := 0
	for made in _made:
		total += made
	return total


func _process(delta: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var live := _live[i]
		live.age += delta
		if live.age >= live.seconds:
			_release(live)
			_live.remove_at(i)
		else:
			_animate(live)
		i -= 1
	if _live.is_empty():
		set_process(false)


func _burst(at: Vector3, radius: float) -> void:
	var live := _lend(Kind.BURST, FLASH_SECONDS)
	live.node.position = at
	live.node.scale = Vector3.ONE * radius


func _animate(live: Live) -> void:
	var t := live.age / live.seconds
	match live.kind:
		Kind.PUFF:
			(live.node as MeshInstance3D).scale = (
				Vector3.ONE * PUFF_RADIUS * lerpf(1.0, PUFF_GROWTH, t)
			)
			_puff_material(live.node).albedo_color.a = PUFF_COLOUR.a * (1.0 - t)
		Kind.NUMBER:
			live.node.position.y = live.base + NUMBER_RISE * t


## An effect of `kind` shown for `seconds`: an idle one, a new one while the pool has room, or the
## oldest live one of its kind taken over.
func _lend(kind: Kind, seconds: float) -> Live:
	var live: Live = null
	if not _idle[kind].is_empty():
		live = _idle[kind].pop_back()
	elif _made[kind] < _pool_size(kind):
		live = Live.new()
		live.kind = kind
		live.node = _make(kind)
		_made[kind] += 1
	else:
		for old in _live:
			if old.kind == kind:
				live = old
				break
		_live.erase(live)
	live.age = 0.0
	live.seconds = seconds
	live.node.visible = true
	_live.append(live)
	set_process(true)
	return live


func _release(live: Live) -> void:
	live.node.visible = false
	_idle[live.kind].append(live)


func _pool_size(kind: Kind) -> int:
	match kind:
		Kind.FLASH:
			return FLASH_POOL
		Kind.BURST:
			return BURST_POOL
		Kind.PUFF:
			return PUFF_POOL
		Kind.TRACER:
			return TRACER_POOL
	return NUMBER_POOL


func _make(kind: Kind) -> Node3D:
	var node: Node3D
	match kind:
		Kind.FLASH:
			var light := OmniLight3D.new()
			light.light_energy = FLASH_ENERGY
			light.omni_range = 5.0
			light.light_color = TRACER_COLOUR
			node = light
		Kind.BURST:
			node = _mesh_instance(_sphere(), _glow_material())
		Kind.PUFF:
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = PUFF_COLOUR
			node = _mesh_instance(_sphere(), null)
			(node as MeshInstance3D).material_override = material
		Kind.TRACER:
			node = _mesh_instance(_tube(), _glow_material())
		Kind.NUMBER:
			var label := Label3D.new()
			label.font_size = 56
			label.pixel_size = 0.006
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.outline_size = 12
			node = label
	node.visible = false
	add_child(node)
	return node


func _mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


func _puff_material(node: Node3D) -> StandardMaterial3D:
	return (node as MeshInstance3D).material_override as StandardMaterial3D


## A sphere of radius 1 m, scaled to the size wanted.
func _sphere() -> SphereMesh:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 1.0
		_unit_sphere.height = 2.0
	return _unit_sphere


## A tube 1 m long and of radius 1 m, along y, scaled to the streak.
func _tube() -> CylinderMesh:
	if _unit_tube == null:
		_unit_tube = CylinderMesh.new()
		_unit_tube.top_radius = 1.0
		_unit_tube.bottom_radius = 1.0
		_unit_tube.height = 1.0
		_unit_tube.radial_segments = 6
	return _unit_tube


## The glowing material of the sparks and the streaks, one for all.
func _glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.albedo_color = TRACER_COLOUR
	return _glow


## One effect on show: its node, how long it has lived and how long it lasts.
class Live:
	extends RefCounted
	var kind := Kind.FLASH
	var node: Node3D
	var age := 0.0
	var seconds := 0.0
	## Where it started, in metres: the height a number rises from, the size a burst keeps.
	var base := 0.0
