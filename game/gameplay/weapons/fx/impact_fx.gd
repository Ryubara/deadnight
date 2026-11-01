class_name ImpactFx
extends Node3D
## Where a shot landed, small and short: on a wall a tiny spark, a puff of dust and a dark dot that
## lingers a moment; on a zombie one small dark-red puff. Pooled: at most `MAX_ACTIVE` impacts are
## alive, and one past that recycles the oldest, so a shotgun or a machine gun never piles up
## quads. Each part is one camera-facing quad with a shader and no texture (`flash_star.gdshader`,
## `impact_puff.gdshader`). Time is the frames' own `delta` and a count of rendered frames, never
## the clock, so tests and captures see the same impacts. Sizes and why:
## docs/design/shot-feedback.md.

enum Kind { WORLD, FLESH }

const STAR_SHADER := preload("res://gameplay/weapons/fx/flash_star.gdshader")
const PUFF_SHADER := preload("res://gameplay/weapons/fx/impact_puff.gdshader")

## The most impacts alive at once.
const MAX_ACTIVE := 24
## Rendered frames a spark stays.
const SPARK_FRAMES := 2
## Sizes are diameters in metres. The old impact was a 0.2 spark and a 0.1 puff that swelled to
## 0.52 (a round sphere each); these never go past the bounds below.
const SPARK_SIZE := 0.09
const DUST_FROM := 0.09
const DUST_TO := 0.2
const DUST_SECONDS := 0.28
const MARK_SIZE := 0.045
const MARK_SECONDS := 0.8
const BLOOD_FROM := 0.06
const BLOOD_TO := 0.14
const BLOOD_SECONDS := 0.22
## The largest part any impact may draw, for the tests that keep them small.
const MAX_SIZE := 0.25
## Quads are nudged this far toward the camera so a wall does not cut them in half.
const LIFT := 0.04

const DUST := Color(0.62, 0.58, 0.5)
const DUST_LIGHT := Color(0.82, 0.78, 0.68)
const MARK := Color(0.1, 0.085, 0.08, 0.85)
const BLOOD := Color(0.42, 0.03, 0.05)
const BLOOD_LIGHT := Color(0.68, 0.1, 0.1)

var _spark_material: ShaderMaterial
var _slots: Array[Slot] = []
var _rng := RandomNumberGenerator.new()


## One impact: its three parts and how long it has lived.
class Slot:
	extends Node3D
	var kind := Kind.WORLD
	var active := false
	var seconds := 0.0
	var frames := 0
	var life := 0.0
	var spark: MeshInstance3D
	var puff: MeshInstance3D
	var mark: MeshInstance3D
	var puff_material: ShaderMaterial
	var mark_material: ShaderMaterial


func _init() -> void:
	_rng.seed = 1958
	set_process(false)


## How many impacts are alive.
func active_count() -> int:
	var count := 0
	for slot in _slots:
		if slot.active:
			count += 1
	return count


## How many parts are drawn right now, for tests.
func visible_parts() -> int:
	var count := 0
	for slot in _slots:
		for part in [slot.spark, slot.puff, slot.mark]:
			if slot.active and part.visible:
				count += 1
	return count


## The largest diameter among the parts drawn now, for tests.
func largest_part() -> float:
	var largest := 0.0
	for slot in _slots:
		if not slot.active:
			continue
		for part in [slot.spark, slot.puff, slot.mark]:
			if part.visible:
				largest = maxf(largest, part.scale.x)
	return largest


## An impact of `kind` at `at`.
func spawn(at: Vector3, kind: Kind) -> void:
	var slot := _free_slot()
	slot.kind = kind
	slot.active = true
	slot.seconds = 0.0
	slot.frames = 0
	slot.visible = true
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	slot.global_position = at
	if camera != null:
		var back := (camera.global_position - at).normalized()
		slot.global_position = at + back * LIFT
		slot.global_basis = Basis.looking_at(-back, Vector3.UP)
	else:
		slot.global_basis = Basis.IDENTITY
	var turn := _rng.randf() * TAU
	slot.spark.visible = kind == Kind.WORLD
	slot.mark.visible = kind == Kind.WORLD
	slot.puff.visible = true
	slot.spark.rotation.z = turn
	slot.spark.scale = Vector3.ONE * SPARK_SIZE * _rng.randf_range(0.85, 1.2)
	slot.mark.scale = Vector3.ONE * MARK_SIZE * _rng.randf_range(0.8, 1.2)
	slot.puff_material.set_shader_parameter(&"seed", _rng.randf() * TAU)
	slot.mark_material.set_shader_parameter(&"seed", _rng.randf() * TAU)
	if kind == Kind.WORLD:
		slot.puff_material.set_shader_parameter(&"colour", DUST)
		slot.puff_material.set_shader_parameter(&"highlight", DUST_LIGHT)
		slot.life = MARK_SECONDS
	else:
		slot.puff_material.set_shader_parameter(&"colour", BLOOD)
		slot.puff_material.set_shader_parameter(&"highlight", BLOOD_LIGHT)
		slot.life = BLOOD_SECONDS
	_pose(slot)
	set_process(true)


## Just the spark, for the places that only want a glint (a flare burst, a splinter).
func spark(at: Vector3) -> void:
	spawn(at, Kind.WORLD)


func seed_random(value: int) -> void:
	_rng.seed = value


func _process(delta: float) -> void:
	var any := false
	for slot in _slots:
		if not slot.active:
			continue
		slot.seconds += delta
		slot.frames += 1
		if slot.seconds >= slot.life:
			slot.active = false
			slot.visible = false
			continue
		_pose(slot)
		any = true
	set_process(any)


## Sizes and fades of one impact for the time it has lived.
func _pose(slot: Slot) -> void:
	if slot.kind == Kind.WORLD:
		slot.spark.visible = slot.frames <= SPARK_FRAMES
		var dust := clampf(slot.seconds / DUST_SECONDS, 0.0, 1.0)
		slot.puff.visible = dust < 1.0
		slot.puff.scale = Vector3.ONE * lerpf(DUST_FROM, DUST_TO, _ease_out(dust))
		slot.puff_material.set_shader_parameter(&"progress", dust)
		var mark := clampf(slot.seconds / MARK_SECONDS, 0.0, 1.0)
		slot.mark_material.set_shader_parameter(&"progress", mark)
	else:
		var blood := clampf(slot.seconds / BLOOD_SECONDS, 0.0, 1.0)
		slot.puff.scale = Vector3.ONE * lerpf(BLOOD_FROM, BLOOD_TO, _ease_out(blood))
		slot.puff_material.set_shader_parameter(&"progress", blood)


func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


## An idle slot, a new one while under the cap, else the oldest alive.
func _free_slot() -> Slot:
	for slot in _slots:
		if not slot.active:
			return slot
	if _slots.size() < MAX_ACTIVE:
		var slot := _make_slot()
		_slots.append(slot)
		add_child(slot)
		return slot
	var oldest: Slot = _slots[0]
	for slot in _slots:
		if slot.seconds > oldest.seconds:
			oldest = slot
	return oldest


func _make_slot() -> Slot:
	if _spark_material == null:
		_spark_material = ShaderMaterial.new()
		_spark_material.shader = STAR_SHADER
		_spark_material.set_shader_parameter(&"spikes", 4.0)
		_spark_material.set_shader_parameter(&"spike_depth", 0.75)
	var slot := Slot.new()
	slot.top_level = true
	slot.visible = false
	slot.puff_material = _puff_material(0.12, 1.0, 0.35)
	slot.mark_material = _puff_material(0.05, 0.0, 0.6)
	slot.mark_material.set_shader_parameter(&"colour", MARK)
	slot.spark = _quad(_spark_material)
	slot.puff = _quad(slot.puff_material)
	slot.mark = _quad(slot.mark_material)
	slot.add_child(slot.mark)
	slot.add_child(slot.puff)
	slot.add_child(slot.spark)
	return slot


func _puff_material(lumpiness: float, crescent: float, fade_from: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PUFF_SHADER
	material.set_shader_parameter(&"lumpiness", lumpiness)
	material.set_shader_parameter(&"crescent", crescent)
	material.set_shader_parameter(&"fade_from", fade_from)
	return material


func _quad(material: ShaderMaterial) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return quad
