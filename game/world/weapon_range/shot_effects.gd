class_name ShotEffects
extends Node3D
## The instant, client-side look of a shot: the muzzle flash (`MuzzleFlash`, on the weapon's muzzle
## point when it has one), a small impact where it landed (`ImpactFx`: a dust puff on a wall, a
## dark-red puff on a zombie), damage numbers, and a tracer only for a weapon that asks for one
## (`WeaponDef.tracer`). All of it is predicted from the shooter's own view and needs no answer from
## the server. Sizes and why: docs/design/shot-feedback.md.

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
## The flash of something that has no weapon def (a flare's burst), in metres across.
const DEFAULT_FLASH := 0.3

## Streaks drawn so far, for tests.
var tracers_drawn := 0
## The impacts, pooled and capped.
var impacts := ImpactFx.new()

var _flash: MuzzleFlash


func _ready() -> void:
	add_child(impacts)


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


func _is_near_any(point: Vector3, points: Array) -> bool:
	for other: Vector3 in points:
		if point.distance_to(other) < SAME_POINT:
			return true
	return false


func _glow(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	return material


func _free_after(node: Node, seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(node.queue_free)
