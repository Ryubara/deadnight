# The blood of a zombie hit (docs/design/shot-feedback.md#blood): a splash at the impact point,
# varied by weapon and by headshot, and capped, fading marks on the ground and the wall.
extends GdUnitTestSuite

const TICK := 1.0 / 60.0
const POINT := Vector3(2.0, 1.2, -3.0)
const FLOOR_Y := 0.0
const WALL_Z := -6.0

var _effects: ShotEffects
var _blood: BloodFx


func before_test() -> void:
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.position = Vector3(0.0, 1.5, 6.0)
	camera.make_current()
	_effects = auto_free(ShotEffects.new())
	add_child(_effects)
	_blood = _effects.blood


## A world that is a floor at y = 0 and a wall across z = -6 (the `WorldCast.cast` shape).
func _world(from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var floor_t := _hit_plane(from, to, Vector3.UP, FLOOR_Y)
	if floor_t >= 0.0:
		best = {"distance": floor_t * from.distance_to(to), "normal": Vector3.UP}
	var wall_t := _hit_plane(from, to, Vector3.BACK, WALL_Z)
	if wall_t >= 0.0 and (best.is_empty() or wall_t * from.distance_to(to) < best["distance"]):
		best = {"distance": wall_t * from.distance_to(to), "normal": Vector3.BACK}
	return best


## Where along from-to (0 to 1) the segment crosses the plane `normal . p = offset`, or -1.
func _hit_plane(from: Vector3, to: Vector3, normal: Vector3, offset: float) -> float:
	var a := normal.dot(from) - offset
	var b := normal.dot(to) - offset
	if a * b > 0.0 or is_equal_approx(a, b):
		return -1.0
	return a / (a - b)


func _event(weapon: StringName, headshot: bool = false, melee: bool = false) -> Dictionary:
	return {
		"type": &"damage_dealt",
		"point": POINT,
		"dir": Vector3.FORWARD,
		"weapon_id": weapon,
		"headshot": headshot,
		"melee": melee,
		"damage": 40.0,
		"pellets": 1,
	}


func _run(frames: int) -> void:
	for _i in frames:
		_blood._process(TICK)


func _splash_scale() -> float:
	return _blood.get_child(0).scale.x


func test_a_hit_puts_the_splash_at_the_impact_point() -> void:
	_effects.blood_hit(_event(&"pistol"), _world)
	assert_int(_blood.splashes_alive()).is_equal(1)
	assert_vector(_blood.splash_origins()[0]).is_equal(POINT)


func test_a_pellet_hit_reaches_the_floor_under_it_and_the_wall_behind_it() -> void:
	_effects.blood_hit(_event(&"shotgun"), _world)
	var points := _blood.mark_points()
	var on_floor := points.filter(func(p: Vector3) -> bool: return p.y < 0.1)
	var on_wall := points.filter(func(p: Vector3) -> bool: return absf(p.z - WALL_Z) < 0.1)
	assert_int(on_floor.size()).override_failure_message("no mark on the floor").is_greater(0)
	assert_int(on_wall.size()).override_failure_message("no mark on the wall").is_greater(0)
	# The floor mark is near the zombie, under the wound; the wall mark is on the shot's line.
	(
		assert_float(Vector2(on_floor[0].x, on_floor[0].z).distance_to(Vector2(POINT.x, POINT.z)))
		. is_less(1.5)
	)
	assert_float(absf(on_wall[0].x - POINT.x)).is_less(0.6)


func test_a_mark_lies_a_little_off_the_surface_not_in_it() -> void:
	_effects.blood_hit(_event(&"pistol"), _world)
	for point in _blood.mark_points():
		var off := minf(absf(point.y - FLOOR_Y), absf(point.z - WALL_Z))
		assert_float(off).is_between(0.0, 0.1)


func test_no_cast_means_a_splash_and_no_marks() -> void:
	_effects.blood_hit(_event(&"pistol"))
	assert_int(_blood.splashes_alive()).is_equal(1)
	assert_int(_blood.marks_alive()).is_equal(0)


func test_an_event_from_an_older_server_still_bleeds() -> void:
	var old := {
		"type": &"damage_dealt", "point": POINT, "damage": 24.0, "headshot": false, "melee": false
	}
	_effects.blood_hit(old, _world)
	assert_int(_blood.splashes_alive()).is_equal(1)
	assert_vector(_blood.splash_origins()[0]).is_equal(POINT)


func test_each_kind_of_hit_has_its_own_blood() -> void:
	var tuning := _blood.tuning
	var kinds := {
		&"pistol": BloodTuning.Kind.BULLET,
		&"smg": BloodTuning.Kind.BULLET,
		&"shotgun": BloodTuning.Kind.PELLETS,
		&"rifle": BloodTuning.Kind.RIFLE,
	}
	for id: StringName in kinds:
		assert_int(tuning.kind_of(WeaponCatalog.get_def(id), false)).is_equal(kinds[id])
	for id: StringName in [&"crowbar", &"fire_axe", &"baseball_bat", &"quick_melee"]:
		assert_int(tuning.kind_of(WeaponCatalog.get_def(id), true)).is_equal(BloodTuning.Kind.MELEE)
	# Five different classes, so they do not all look alike.
	var seen := {}
	for kind in BloodTuning.Kind.values():
		seen[tuning.class_of(kind)] = true
	assert_int(seen.size()).is_equal(5)
	assert_float(tuning.rifle.reach).is_greater(tuning.bullet.reach)
	assert_float(tuning.rifle.cone_deg).is_less(tuning.bullet.cone_deg)
	assert_float(tuning.pellets.drop_size).is_less(tuning.bullet.drop_size)
	assert_float(tuning.melee.smear).is_greater(0.0)
	assert_float(tuning.bullet.smear).is_equal(0.0)


func test_a_headshot_splashes_bigger_than_a_body_shot_of_the_same_gun() -> void:
	_effects.blood_hit(_event(&"rifle", false), Callable())
	var body := _splash_scale()
	_blood.stop_all()
	_effects.blood_hit(_event(&"rifle", true), Callable())
	assert_float(_splash_scale()).is_greater(body * 1.2)


func test_a_pellet_hit_has_more_drops_the_more_pellets_land() -> void:
	var few := _event(&"shotgun")
	few["pellets"] = 1
	var many := _event(&"shotgun")
	many["pellets"] = 6
	_effects.blood_hit(few)
	var few_drops: int = _blood.get_child(0).material.get_shader_parameter(&"drops")
	_blood.stop_all()
	_effects.blood_hit(many)
	var many_drops: int = _blood.get_child(0).material.get_shader_parameter(&"drops")
	assert_int(many_drops).is_greater(few_drops)
	assert_int(many_drops).is_less_equal(BloodFx.MAX_DROPS)


func test_the_splash_ends_by_itself_and_waits_for_the_next() -> void:
	_effects.blood_hit(_event(&"pistol"))
	var seconds := _blood.tuning.bullet.seconds
	_run(int(seconds / TICK) + 2)
	assert_int(_blood.splashes_alive()).is_equal(0)
	assert_bool(_blood.is_processing()).is_false()


func test_marks_never_pass_their_cap_however_long_the_night() -> void:
	_blood.mark_cap = 20
	_blood.prewarm()
	var made := _blood.nodes_made()
	for i in 200:
		_blood.mark(Vector3(i * 0.1, 0.0, 0.0), Vector3.UP, Vector3.RIGHT, 0.4)
		_run(2)
		assert_int(_blood.marks_alive()).is_less_equal(20)
	assert_int(_blood.marks_alive()).is_equal(20)
	assert_int(_blood.nodes_made()).override_failure_message("a mark was made in play").is_equal(
		made
	)


func test_a_new_mark_over_the_cap_takes_the_oldest() -> void:
	_blood.mark_cap = 3
	for i in 3:
		_blood.mark(Vector3(i, 0.0, 0.0), Vector3.UP, Vector3.RIGHT, 0.4)
		_run(2)
	_blood.mark(Vector3(10.0, 0.0, 0.0), Vector3.UP, Vector3.RIGHT, 0.4)
	var xs := _blood.mark_points().map(func(p: Vector3) -> float: return p.x)
	assert_array(xs).has_size(3)
	assert_bool(xs.has(0.0)).override_failure_message("the oldest was kept").is_false()
	assert_bool(xs.has(10.0)).is_true()


func test_the_cap_is_smaller_in_the_browser_than_on_a_desktop() -> void:
	var tuning := _blood.tuning
	assert_int(tuning.marks_web).is_less(tuning.marks_desktop)
	assert_int(_blood.mark_cap).is_equal(tuning.marks_desktop)  # the test runs on the desktop


func test_a_mark_fades_out_and_is_gone() -> void:
	_blood.mark(Vector3.ZERO, Vector3.UP, Vector3.RIGHT, 0.4)
	var slot := _blood.get_child(0)
	var seconds := _blood.tuning.mark_seconds
	var fade_from := 1.0 - _blood.tuning.mark_fade_share
	_run(int(seconds * (fade_from - 0.05) / TICK))
	assert_bool(slot.visible).is_true()
	assert_float(slot.material.get_shader_parameter(&"progress")).is_less(fade_from)
	_run(int(seconds * 0.2 / TICK))
	assert_float(slot.material.get_shader_parameter(&"progress")).is_greater(fade_from)
	assert_bool(slot.visible).is_true()
	_run(int(seconds * 0.3 / TICK) + 10)
	assert_int(_blood.marks_alive()).is_equal(0)
	assert_bool(slot.visible).is_false()


func test_twenty_zombies_shot_for_a_minute_make_no_new_nodes() -> void:
	_blood.prewarm()
	var made := _blood.nodes_made()
	var at := Vector3.ZERO
	for second in 60:
		for z in 20:
			at = Vector3(z * 0.8 - 8.0, 1.2, -3.0 - fmod(second * 0.37, 2.0))
			var event := _event(&"smg" if z % 2 == 0 else &"shotgun", z % 5 == 0)
			event["point"] = at
			_effects.blood_hit(event, _world)
		_run(60)
		assert_int(_blood.splashes_alive()).is_less_equal(_blood.tuning.splashes)
		assert_int(_blood.marks_alive()).is_less_equal(_blood.mark_cap)
	assert_int(_blood.nodes_made()).is_equal(made)


func test_stop_all_hides_everything() -> void:
	_effects.blood_hit(_event(&"rifle", true), _world)
	_effects.stop_all()
	assert_int(_blood.splashes_alive()).is_equal(0)
	assert_int(_blood.marks_alive()).is_equal(0)
	assert_bool(_effects.owns(_blood)).is_true()
