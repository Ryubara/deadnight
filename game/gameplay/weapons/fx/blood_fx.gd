class_name BloodFx
extends Node3D
## Blood where a zombie is hit: a splash at the wound, flung along the shot, and capped marks on the
## ground and the wall behind it that dry and fade. Both are pooled quads with a shader and no
## texture (`blood_splash.gdshader`, `blood_decal.gdshader`): nothing is made while a night is
## played, a finished splash is hidden and waits, and one past the cap takes over the oldest, so a
## long night never grows. Time is the frames' own `delta`, never the clock, so tests and captures
## see the same blood. How it looks and why: docs/design/shot-feedback.md#blood.

const SPLASH_SHADER := preload("res://gameplay/weapons/fx/blood_splash.gdshader")
const MARK_SHADER := preload("res://gameplay/weapons/fx/blood_decal.gdshader")
## The splash shader draws at most this many drops.
const MAX_DROPS := 16
## The marks' fade is redrawn every this many frames (it takes seconds, so nobody sees the steps).
const MARK_EVERY := 4
## How far above the wound the ray for a ground mark starts, in metres.
const GROUND_START := 0.3
## How far a mark is stretched along its flow: a wall mark drips, a ground mark is flung.
const WALL_STRETCH := 1.9
const GROUND_STRETCH := 1.5

var tuning := BloodTuning.shipped()
## The most marks alive at once (`BloodTuning.marks_desktop` or `marks_web` unless a test sets it).
var mark_cap := 0

var _splashes: Array[Splash] = []
var _marks: Array[Mark] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _frame := 0


## One splash: its quad, its material and when it began.
class Splash:
	extends MeshInstance3D
	var active := false
	var born := 0.0
	var life := 1.0
	var material: ShaderMaterial
	var origin := Vector3.ZERO


## One mark on a surface.
class Mark:
	extends MeshInstance3D
	var active := false
	var born := 0.0
	var life := 1.0
	var material: ShaderMaterial


func _init() -> void:
	_rng.seed = 618
	mark_cap = tuning.marks_web if OS.has_feature("web") else tuning.marks_desktop
	set_process(false)


## Makes every splash and mark ahead of the night, hidden, so no hit builds one while it is played.
func prewarm() -> void:
	while _splashes.size() < tuning.splashes:
		_splashes.append(_make_splash())
	while _marks.size() < mark_cap:
		_marks.append(_make_mark())


## Ends every splash and mark (they are hidden, and kept for the next ones).
func stop_all() -> void:
	for slot in _splashes:
		slot.active = false
		slot.visible = false
	for slot in _marks:
		slot.active = false
		slot.visible = false
	set_process(false)


func splashes_alive() -> int:
	var count := 0
	for slot in _splashes:
		if slot.active:
			count += 1
	return count


func marks_alive() -> int:
	var count := 0
	for slot in _marks:
		if slot.active:
			count += 1
	return count


## Where the splashes on show are centred (before the small lift toward the camera), for tests.
func splash_origins() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for slot in _splashes:
		if slot.active:
			found.append(slot.origin)
	return found


## Where the marks on show lie, for tests.
func mark_points() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for slot in _marks:
		if slot.active:
			found.append(slot.global_position)
	return found


## Nodes made so far, for tests: it stops growing once the pools are full.
func nodes_made() -> int:
	return _splashes.size() + _marks.size()


## The blood of one hit: a splash at `point` and the marks round it. `dir` is the way the shot or
## blow went (ZERO for a burst that has none), `cast` is `WorldCast.cast`-shaped (`from`, `to` ->
## `{distance, normal}` or `{}`) and may be empty, which leaves the marks out.
func hit(
	point: Vector3,
	dir: Vector3,
	kind: BloodTuning.Kind,
	headshot: bool,
	damage: float,
	pellets: int = 1,
	cast: Callable = Callable()
) -> void:
	splash(point, dir, kind, headshot, damage, pellets)
	marks(point, dir, kind, headshot, cast)


## The splash at the wound.
func splash(
	point: Vector3,
	dir: Vector3,
	kind: BloodTuning.Kind,
	headshot: bool,
	damage: float,
	pellets: int = 1
) -> void:
	var cls := tuning.class_of(kind)
	var share := lerpf(tuning.damage_least, 1.0, clampf(damage / tuning.damage_full, 0.0, 1.0))
	var drops := cls.drops + roundi(cls.drops_per_pellet * maxi(pellets - 1, 0))
	var reach := cls.reach * share
	var drop := cls.drop_size * share
	var blot := cls.splat_size * share
	var back := cls.back
	if headshot:
		drops = roundi(drops * tuning.head_drops_scale)
		reach *= tuning.head_reach_scale
		drop *= tuning.head_size_scale
		blot *= tuning.head_size_scale
		back = maxf(back, tuning.head_back)
	var slot := _free_splash()
	slot.active = true
	slot.visible = true
	slot.born = _clock
	slot.life = cls.seconds
	slot.origin = point
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var lift := Vector3.ZERO
	if camera != null:
		lift = (camera.global_position - point).normalized() * tuning.splash_lift
	slot.global_position = point + lift
	slot.scale = Vector3.ONE * reach * 2.0
	var material := slot.material
	material.set_shader_parameter(&"progress", 0.0)
	material.set_shader_parameter(&"seed", _rng.randf() * TAU)
	material.set_shader_parameter(&"spray_dir", _unit(dir))
	material.set_shader_parameter(&"drops", clampi(drops, 1, MAX_DROPS))
	material.set_shader_parameter(&"cone", deg_to_rad(cls.cone_deg))
	material.set_shader_parameter(&"drop_radius", drop * 0.5 / reach)
	material.set_shader_parameter(&"blot_radius", blot * 0.5 / reach)
	material.set_shader_parameter(&"streak", cls.streak)
	material.set_shader_parameter(&"smear", cls.smear)
	material.set_shader_parameter(&"back", back)
	material.set_shader_parameter(
		&"colour", tuning.head_colour if headshot else tuning.blood_colour
	)
	material.set_shader_parameter(
		&"highlight", tuning.head_light_colour if headshot else tuning.blood_light_colour
	)
	set_process(true)


## The marks of one hit: on the ground under and beyond the zombie, and on the wall behind it.
func marks(
	point: Vector3, dir: Vector3, kind: BloodTuning.Kind, headshot: bool, cast: Callable
) -> void:
	if not cast.is_valid():
		return
	var cls := tuning.class_of(kind)
	var aim := _unit(dir)
	var size_scale := tuning.head_size_scale if headshot else 1.0
	var ground := cls.ground_marks
	if headshot:
		ground = roundi(ground * tuning.head_marks_scale)
	for i in ground:
		_ground_mark(point, aim, cls.mark_size * size_scale, i, ground, cast)
	if aim == Vector3.ZERO:
		return
	var reach := tuning.wall_reach
	if kind == BloodTuning.Kind.RIFLE or headshot:
		reach *= tuning.strong_reach_scale
	for i in cls.wall_marks:
		var ray := aim
		if i > 0:
			var wobble := Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.08, 0.08), 0.0)
			ray = (aim + wobble).normalized()
		var found: Dictionary = cast.call(point, point + ray * reach)
		if found.is_empty():
			continue
		var normal: Vector3 = found["normal"]
		var distance: float = found["distance"]
		var size := cls.mark_size * size_scale * lerpf(1.0, 0.5, distance / reach)
		size *= _rng.randf_range(0.8, 1.2)
		var along := Vector3.DOWN
		var stretch := WALL_STRETCH
		if normal.y >= tuning.floor_normal_y:  # a shot into the floor: a mark like the others
			along = Vector3(ray.x, 0.0, ray.z).normalized()
			stretch = GROUND_STRETCH
		mark(point + ray * distance, normal, along, size, stretch)


## One mark `size` metres across on a surface at `at` with the given `normal`, stretched along
## `along` (a way on the surface; any way will do when it is not).
func mark(
	at: Vector3, normal: Vector3, along: Vector3, size: float, stretch: float = GROUND_STRETCH
) -> void:
	var n := normal.normalized()
	var x := along - n * along.dot(n)
	if x.length_squared() < 0.0001:
		x = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP)
	x = x.normalized()
	var slot := _free_mark()
	slot.active = true
	slot.visible = true
	slot.born = _clock
	slot.life = tuning.mark_seconds
	var basis := Basis(x, n.cross(x), n).scaled_local(Vector3(size, size, 1.0))
	slot.global_transform = Transform3D(basis, at)
	slot.material.set_shader_parameter(&"progress", 0.0)
	slot.material.set_shader_parameter(&"seed", _rng.randf() * TAU)
	slot.material.set_shader_parameter(&"stretch", stretch)
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	_frame += 1
	var any := false
	for slot in _splashes:
		if not slot.active:
			continue
		var progress := (_clock - slot.born) / slot.life
		if progress >= 1.0:
			slot.active = false
			slot.visible = false
			continue
		slot.material.set_shader_parameter(&"progress", progress)
		any = true
	var redraw := _frame % MARK_EVERY == 0
	for slot in _marks:
		if not slot.active:
			continue
		var progress := (_clock - slot.born) / slot.life
		if progress >= 1.0:
			slot.active = false
			slot.visible = false
			continue
		if redraw:
			slot.material.set_shader_parameter(&"progress", progress)
		any = true
	set_process(any)


## A mark on the ground: the first under the wound, the rest thrown farther along the shot.
func _ground_mark(
	point: Vector3, aim: Vector3, size: float, index: int, count: int, cast: Callable
) -> void:
	var way := Vector3(aim.x, 0.0, aim.z)
	if way.length_squared() > 0.0001:
		way = way.normalized()
	else:
		var turn := _rng.randf() * TAU
		way = Vector3(cos(turn), 0.0, sin(turn))
	var throw := tuning.ground_throw * float(index) / maxf(count - 1.0, 1.0)
	throw *= _rng.randf_range(0.6, 1.0)
	var jitter := Vector3(_rng.randf_range(-0.15, 0.15), 0.0, _rng.randf_range(-0.15, 0.15))
	var start := point + way * throw + jitter + Vector3.UP * GROUND_START
	var found: Dictionary = cast.call(
		start, start + Vector3.DOWN * (tuning.ground_reach + GROUND_START)
	)
	if found.is_empty():
		return
	var normal: Vector3 = found["normal"]
	if normal.y < tuning.floor_normal_y:
		return
	var spot := start + Vector3.DOWN * float(found["distance"])
	var width := size * _rng.randf_range(0.8, 1.2) * (1.0 + 0.25 * index)
	mark(spot, normal, way, width, GROUND_STRETCH)


## `dir` as a unit vector, or ZERO when it is not a direction.
func _unit(dir: Vector3) -> Vector3:
	if not dir.is_finite() or dir.length_squared() < 0.25:
		return Vector3.ZERO
	return dir.normalized()


## An idle splash, a new one while under the cap, else the oldest alive.
func _free_splash() -> Splash:
	var oldest: Splash = null
	for slot in _splashes:
		if not slot.active:
			return slot
		if oldest == null or slot.born < oldest.born:
			oldest = slot
	if _splashes.size() < tuning.splashes:
		var made := _make_splash()
		_splashes.append(made)
		return made
	return oldest


## An idle mark while fewer than `mark_cap` are alive, else the oldest alive.
func _free_mark() -> Mark:
	var alive := 0
	var oldest: Mark = null
	var idle: Mark = null
	for slot in _marks:
		if slot.active:
			alive += 1
			if oldest == null or slot.born < oldest.born:
				oldest = slot
		elif idle == null:
			idle = slot
	if alive >= mark_cap and oldest != null:
		return oldest
	if idle != null:
		return idle
	var made := _make_mark()
	_marks.append(made)
	return made


func _make_splash() -> Splash:
	var slot := Splash.new()
	slot.top_level = true
	slot.visible = false
	slot.mesh = QuadMesh.new()
	slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	slot.material = ShaderMaterial.new()
	slot.material.shader = SPLASH_SHADER
	slot.material_override = slot.material
	add_child(slot)
	return slot


func _make_mark() -> Mark:
	var slot := Mark.new()
	slot.top_level = true
	slot.visible = false
	slot.mesh = QuadMesh.new()
	slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = MARK_SHADER
	material.set_shader_parameter(&"wet_colour", tuning.blood_colour)
	material.set_shader_parameter(&"dried_colour", tuning.dried_colour)
	material.set_shader_parameter(&"highlight", tuning.blood_light_colour)
	material.set_shader_parameter(&"fade_from", 1.0 - tuning.mark_fade_share)
	material.set_shader_parameter(&"lift", tuning.mark_lift)
	material.set_shader_parameter(&"lift_per_metre", tuning.mark_lift_per_metre)
	slot.material = material
	slot.material_override = material
	add_child(slot)
	return slot
