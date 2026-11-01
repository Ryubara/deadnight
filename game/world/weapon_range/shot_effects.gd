class_name ShotEffects
extends Node3D
## The instant, client-side look of a shot: the muzzle flash (`MuzzleFlash`, on the weapon's muzzle
## point when it has one), a small impact where it landed (`ImpactFx`: a dust puff on a wall, a
## dark-red puff on a zombie), damage numbers, and a tracer only for a weapon that asks for one
## (`WeaponDef.tracer`). All of it is predicted from the shooter's own view and needs no answer from
## the server. Sizes and why: docs/design/shot-feedback.md.
##
## Nothing here is made or freed while a night is played: the flash and the impacts are pooled
## (`MuzzleFlash`, `ImpactFx`), and so are the streaks and the damage numbers (`_lend`): a finished
## one is hidden and waits for the next, with its mesh and material, so a shot or a kill allocates
## nothing and the renderer never builds a shader again for a material that was freed (a shader
## goes with the last material that uses it). Their animation is by `_process`, from their age.

enum Kind { TRACER, NUMBER }

const TRACER_COLOUR := Color(1.0, 0.86, 0.45)
const TRACER_RADIUS := 0.02
const TRACER_SECONDS := 0.3
const NUMBER_SECONDS := 1.0
const NUMBER_RISE := 0.8
const HEAD_COLOUR := Color(1.0, 0.45, 0.35)
const BODY_COLOUR := Color(1.0, 1.0, 1.0)
## A shot that ended within this many metres of its range hit something.
const RANGE_SLACK := 0.1
## A pellet that ended this close to a point it hit a zombie at hit the zombie, not the wall.
const SAME_POINT := 0.02
## A weapon with no model in the hand (the pistol: the hand stays empty) flashes this far along the
## barrel from the body's muzzle, where its fist is, so the body does not hide the flash.
const BARE_REACH := 0.6
## How many streaks and numbers can be alive at once; past it the oldest of its kind is taken over.
const TRACER_POOL := 8
const NUMBER_POOL := 16
## The flash of something that has no weapon def (a flare's burst), in metres across.
const DEFAULT_FLASH := 0.3

## Streaks drawn so far, for tests.
var tracers_drawn := 0
## The impacts, pooled and capped.
var impacts := ImpactFx.new()

var _flash: MuzzleFlash
var _idle: Array[Array] = [[], []]
var _made: Array[int] = [0, 0]
var _live: Array[Live] = []
var _unit_tube: CylinderMesh
var _glow: StandardMaterial3D


func _ready() -> void:
	add_child(impacts)
	set_process(false)


func _init() -> void:
	# Tweens on the drawn frame move these, not the physics tick: the engine's physics
	# interpolation (docs/research/physics-interpolation.md) would blend them a tick late.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## The look of one shot of `def` from `muzzle` that ended at each of `ends` (one per pellet): the
## muzzle flash (on `anchor`, the weapon's muzzle point, when there is one), then a small puff on
## every zombie hit at `flesh` and a spark, puff and mark at every end that stopped short of the
## weapon's range on something else. A streak only when the weapon asks for one. A projectile
## weapon draws only the flash: its body flies and bursts.
func shot(
	def: WeaponDef, muzzle: Vector3, ends: Array, flesh: Array = [], anchor: Node3D = null
) -> void:
	var aim := Vector3.ZERO
	if not ends.is_empty():
		aim = (ends[0] as Vector3) - muzzle
	muzzle_flash(muzzle, def.flash_size, anchor, aim)
	if def.is_projectile():
		return
	for point: Vector3 in flesh:
		impacts.spawn(point, ImpactFx.Kind.FLESH)
	for end: Vector3 in ends:
		if def.tracer:
			tracer(muzzle, end)
		if def.is_melee() or muzzle.distance_to(end) >= def.max_range - RANGE_SLACK:
			continue
		if not _is_near_any(end, flesh):
			impacts.spawn(end, ImpactFx.Kind.WORLD)


## A spark, a puff and a mark where a shot landed on the world.
func impact(at: Vector3) -> void:
	impacts.spawn(at, ImpactFx.Kind.WORLD)


## A small glint where something burst (a flare, a board).
func spark(at: Vector3) -> void:
	impacts.spark(at)


func tracer(from: Vector3, to: Vector3, radius: float = TRACER_RADIUS) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	tracers_drawn += 1
	var instance := _lend(Kind.TRACER, TRACER_SECONDS).node as MeshInstance3D
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	instance.scale = Vector3.ONE
	instance.look_at_from_position((from + to) / 2.0, to, up)
	instance.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	# The unit tube is 1 m long and 1 m round: stretched to the streak.
	instance.scale = Vector3(radius, length, radius)


## A flash `size` metres across at `at` (or on `anchor`, the weapon's muzzle point, which sets the
## place), the barrel pointing along `aim` (the muzzle point's own way when it has one).
func muzzle_flash(
	at: Vector3, size: float = DEFAULT_FLASH, anchor: Node3D = null, aim: Vector3 = Vector3.ZERO
) -> void:
	if size <= 0.0:
		return
	var flash: MuzzleFlash
	var barrel := aim
	if anchor != null and is_instance_valid(anchor) and anchor.is_inside_tree():
		flash = MuzzleFlash.on(anchor)
		barrel = -anchor.global_basis.z
	else:
		if _flash == null:
			_flash = MuzzleFlash.new()
			add_child(_flash)
		flash = _flash
		flash.global_position = (
			at + barrel.normalized() * BARE_REACH if barrel.length() > 0.01 else at
		)
	flash.fire(size, barrel)


func number(at: Vector3, text: String, headshot: bool) -> void:
	var live := _lend(Kind.NUMBER, NUMBER_SECONDS)
	var label := live.node as Label3D
	label.text = text
	label.modulate = HEAD_COLOUR if headshot else BODY_COLOUR
	label.position = at
	live.base = at.y


## Makes every pooled node ahead of the night (the impacts' slots, the streaks, the numbers),
## hidden, so no shot or kill builds one while it is played.
func prewarm() -> void:
	impacts.prewarm()
	for kind in [Kind.TRACER, Kind.NUMBER]:
		while _made[kind] < (TRACER_POOL if kind == Kind.TRACER else NUMBER_POOL):
			var live := Live.new()
			live.kind = kind
			live.node = _make(kind)
			_made[kind] += 1
			_idle[kind].append(live)


## Ends every effect on show now (they are hidden, and kept for the next ones).
func stop_all() -> void:
	for live in _live:
		_release(live)
	_live.clear()
	set_process(false)
	impacts.stop_all()
	if _flash != null:
		_flash.visible = false


## Whether `node` is part of the effects' own gear, which the warm-up must not free.
func owns(node: Node) -> bool:
	if node == impacts or node == _flash:
		return true
	for live in _live:
		if live.node == node:
			return true
	for kind in _idle.size():
		for live: Live in _idle[kind]:
			if live.node == node:
				return true
	return false


## Effects on show now (streaks and numbers), for tests.
func live_count() -> int:
	return _live.size()


## Effects on show of one kind, for tests.
func live_of(kind: Kind) -> int:
	var count := 0
	for live in _live:
		if live.kind == kind:
			count += 1
	return count


## Nodes made for streaks and numbers so far, for tests: it stops growing once each kind has met
## its busiest moment.
func nodes_made() -> int:
	return _made[0] + _made[1]


func _process(delta: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var live := _live[i]
		live.age += delta
		if live.age >= live.seconds:
			_release(live)
			_live.remove_at(i)
		elif live.kind == Kind.NUMBER:
			live.node.position.y = live.base + NUMBER_RISE * live.age / live.seconds
		i -= 1
	if _live.is_empty():
		set_process(false)


## A streak or a number shown for `seconds`: an idle one, a new one while the pool has room, or
## the oldest live one of its kind taken over.
func _lend(kind: Kind, seconds: float) -> Live:
	var live: Live = null
	if not _idle[kind].is_empty():
		live = _idle[kind].pop_back()
	elif _made[kind] < (TRACER_POOL if kind == Kind.TRACER else NUMBER_POOL):
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


func _make(kind: Kind) -> Node3D:
	var node: Node3D
	if kind == Kind.TRACER:
		if _unit_tube == null:
			_unit_tube = CylinderMesh.new()
			_unit_tube.top_radius = 1.0
			_unit_tube.bottom_radius = 1.0
			_unit_tube.height = 1.0
			_unit_tube.radial_segments = 6
		var instance := MeshInstance3D.new()
		instance.mesh = _unit_tube
		instance.material_override = _glow_material()
		node = instance
	else:
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


func _is_near_any(point: Vector3, points: Array) -> bool:
	for other: Vector3 in points:
		if point.distance_to(other) < SAME_POINT:
			return true
	return false


## The glowing material of the streaks, one for all.
func _glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.albedo_color = TRACER_COLOUR
	return _glow


## One streak or number on show: its node, how long it has lived and how long it lasts.
class Live:
	extends RefCounted
	var kind := Kind.TRACER
	var node: Node3D
	var age := 0.0
	var seconds := 0.0
	## The height a number rises from.
	var base := 0.0
