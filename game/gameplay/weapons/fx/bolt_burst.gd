class_name BoltBurst
extends Node3D
## The burst of a ray gun's bolt, client only: a bright core and a shell of the bolt's colour that
## swell to the splash radius and fade, where the server's `projectile_burst` says. It decides
## nothing (the splash damage is the server's) and makes no light: the lot's light cap leaves room
## for a flash and a blast only. A few bursts are pooled, made once (`prewarm`).

const POOL := 4
## Seconds the burst swells and fades, and the share of the radius the core reaches.
const SECONDS := 0.45
const CORE_SHARE := 0.45
const SHELL_ALPHA := 0.4
## The smallest a burst starts (a share of its radius).
const START_SHARE := 0.15

var _free: Array[Slot] = []
var _live: Array[Slot] = []
var _made := 0
var _mesh: SphereMesh


## One burst: its two spheres and how far along it is.
class Slot:
	extends RefCounted
	var root: Node3D
	var shell: MeshInstance3D
	var core: MeshInstance3D
	var age := 0.0
	var radius := 1.0
	var shell_colour := Color.WHITE
	var core_colour := Color.WHITE


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)


func prewarm() -> void:
	while _made < POOL:
		_free.append(_make())


## A burst at `at` that swells to `radius` metres, in the colours `core` and `shell`.
func burst(at: Vector3, radius: float, core: Color, shell: Color) -> void:
	var slot := _lend()
	slot.age = 0.0
	slot.radius = maxf(radius, 0.3)
	slot.core_colour = core
	slot.shell_colour = shell
	slot.root.position = at
	slot.root.visible = true
	_pose(slot)
	set_process(true)


func live_count() -> int:
	return _live.size()


func nodes_made() -> int:
	return _made


func stop_all() -> void:
	for slot in _live:
		slot.root.visible = false
		_free.append(slot)
	_live.clear()
	set_process(false)


func _process(delta: float) -> void:
	var i := _live.size() - 1
	while i >= 0:
		var slot := _live[i]
		slot.age += delta
		if slot.age >= SECONDS:
			slot.root.visible = false
			_free.append(slot)
			_live.remove_at(i)
		else:
			_pose(slot)
		i -= 1
	if _live.is_empty():
		set_process(false)


func _pose(slot: Slot) -> void:
	var share := clampf(slot.age / SECONDS, 0.0, 1.0)
	var swell := 1.0 - pow(1.0 - share, 3.0)
	var size := slot.radius * lerpf(START_SHARE, 1.0, swell)
	slot.shell.scale = Vector3.ONE * size
	slot.core.scale = Vector3.ONE * size * CORE_SHARE
	var fade := 1.0 - share
	_set_alpha(slot.shell, slot.shell_colour, SHELL_ALPHA * fade)
	_set_alpha(slot.core, slot.core_colour, fade)


static func _set_alpha(node: MeshInstance3D, colour: Color, alpha: float) -> void:
	(node.material_override as StandardMaterial3D).albedo_color = Color(colour, alpha)


func _lend() -> Slot:
	var slot: Slot
	if not _free.is_empty():
		slot = _free.pop_back()
	elif _made < POOL:
		slot = _make()
		_free.erase(slot)
	else:
		slot = _live.pop_front()
	_live.append(slot)
	return slot


func _make() -> Slot:
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 1.0
		_mesh.height = 2.0
		_mesh.radial_segments = 16
		_mesh.rings = 8
	var slot := Slot.new()
	slot.root = Node3D.new()
	slot.shell = _sphere()
	slot.core = _sphere()
	slot.root.add_child(slot.shell)
	slot.root.add_child(slot.core)
	slot.root.visible = false
	add_child(slot.root)
	_made += 1
	return slot


func _sphere() -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var node := MeshInstance3D.new()
	node.mesh = _mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
