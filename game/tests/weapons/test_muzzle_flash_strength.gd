# The muzzle flash must read from the shoulder camera (issue #408; docs/design/shot-feedback.md,
# "How strong the flash must be"): drawn for at least three frames and 50 ms at any frame rate, a
# star big enough on the screen, drawn clear of the gun and the hands that used to hide it, and
# lit by a warm light that is bright but not blinding. The pixels themselves are measured by
# `tests/captures/flash_probe.gd` (desktop) and `tools/web_smoke/flash.py` (browser) against the
# floors of `tests/captures/flash_floors.json`; this suite holds the numbers they come from and
# the floors check itself.
extends GdUnitTestSuite

## The flash is drawn for at least this many rendered frames and this long, at any frame rate.
const MIN_FRAMES := 3
const MIN_SECONDS := 0.05
## The big star, at the start of its life and at its smallest random size, is at least this share
## of the screen's height from the shoulder camera.
const MIN_STAR_HEIGHT := 0.07
## The flash is drawn at least this far (m) toward the camera from the muzzle, clear of the gun.
const MIN_LIFT := 0.5
## The flash light: bright enough to light the ground ahead, never a floodlight.
const LIGHT_ENERGY := Vector2(1.5, 3.0)
const LIGHT_RANGE := Vector2(2.5, 4.5)
const FIREARMS: Array[StringName] = [&"pistol", &"smg", &"rifle", &"shotgun", &"flare_gun"]
## Shoulder camera: the arm's length (`PlayerTuning.arm_length`) and a little more to the muzzle.
const SHOULDER_DISTANCE := 2.8
const FOV := 70.0

var _camera: Camera3D


func before_test() -> void:
	_camera = auto_free(Camera3D.new())
	add_child(_camera)
	_camera.fov = FOV
	_camera.position = Vector3(0.0, 0.0, SHOULDER_DISTANCE)
	_camera.make_current()


func _flash() -> MuzzleFlash:
	var flash: MuzzleFlash = auto_free(MuzzleFlash.new())
	add_child(flash)
	return flash


## Frames the flash stays up after a shot at a frame rate of `delta`, each one `_process` call.
func _frames_up(flash: MuzzleFlash, delta: float) -> int:
	flash.fire(0.3, Vector3.RIGHT)
	var count := 0
	while flash.is_up() and count < 1000:
		flash._process(delta)
		if flash.is_up():
			count += 1
	return count


# --- how long ---


func test_the_flash_is_drawn_for_three_frames_at_30_and_60_fps() -> void:
	for delta in [1.0 / 30.0, 1.0 / 60.0]:
		var up := _frames_up(_flash(), delta)
		assert_int(up).override_failure_message("at %.0f fps" % (1.0 / delta)).is_greater_equal(
			MIN_FRAMES
		)


func test_the_flash_is_drawn_for_fifty_milliseconds_on_a_fast_screen() -> void:
	for delta in [1.0 / 90.0, 1.0 / 120.0, 1.0 / 144.0, 1.0 / 240.0]:
		var up := _frames_up(_flash(), delta)
		# The first frame is a part of a frame (the shot is fired somewhere inside it).
		(
			assert_float(float(up + 1) * delta)
			. override_failure_message("at %.0f fps" % (1.0 / delta))
			. is_greater_equal(MIN_SECONDS)
		)
		assert_int(up).is_greater_equal(MIN_FRAMES)


func test_the_flash_dies_down_over_its_life() -> void:
	var flash := _flash()
	flash.fire(0.3, Vector3.RIGHT)
	flash._process(1.0 / 60.0)
	var first := flash.quads[1].global_transform.basis.x.length()
	flash._process(1.0 / 60.0)
	flash._process(1.0 / 60.0)
	var last := flash.quads[1].global_transform.basis.x.length()
	assert_float(last).is_less(first)


# --- how big and how clear ---


func test_every_firearms_star_is_big_enough_from_the_shoulder_camera() -> void:
	var half_height := tan(deg_to_rad(FOV) / 2.0)
	for id in FIREARMS:
		var size := WeaponCatalog.get_def(id).flash_size
		var flash := _flash()
		# The smallest roll.
		flash.scale_range = Vector2(flash.scale_range.x, flash.scale_range.x)
		flash.fire(size, Vector3.RIGHT)
		var quad := flash.quads[0]
		# The star fills `halo_fill` of its quad; the quad's distance is the one it is drawn at.
		var star := quad.global_transform.basis.x.length() * flash.halo_fill
		var away := quad.global_position.distance_to(_camera.global_position)
		var share := star / (2.0 * away * half_height)
		(
			assert_float(share)
			. override_failure_message("%s: the star is %.1f%% of the screen" % [id, share * 100.0])
			. is_greater_equal(MIN_STAR_HEIGHT)
		)


func test_heavier_guns_still_flash_bigger() -> void:
	var sizes: Array[float] = []
	for id: StringName in [&"pistol", &"rifle", &"shotgun"]:
		sizes.append(WeaponCatalog.get_def(id).flash_size)
	assert_float(sizes[1]).is_greater(sizes[0])
	assert_float(sizes[2]).is_greater(sizes[1])


func test_the_flash_is_drawn_clear_of_the_gun_and_looks_the_same_size() -> void:
	var flash := _flash()
	flash.fire(0.3, Vector3.RIGHT)
	var quad := flash.quads[1]
	var lift := quad.global_position.distance_to(flash.global_position)
	assert_float(lift).is_greater_equal(MIN_LIFT)
	assert_float(quad.global_position.z).is_greater(flash.global_position.z)
	# Nearer the camera and smaller by the same ratio: the same size on the screen.
	var before := flash.global_position.distance_to(_camera.global_position)
	var after := quad.global_position.distance_to(_camera.global_position)
	var drawn := quad.global_transform.basis.x.length() / after
	var at_muzzle: float = 0.3 * flash.small_star * flash.life_scale.x * flash._grow / before
	assert_float(drawn).is_equal_approx(at_muzzle, at_muzzle * 0.02)


func test_a_flash_next_to_the_camera_is_not_lifted_through_it() -> void:
	var flash := _flash()
	_camera.position = Vector3(0.0, 0.0, 0.5)
	flash.fire(0.3, Vector3.RIGHT)
	var lift := flash.quads[0].global_position.distance_to(flash.global_position)
	assert_float(lift).is_less_equal(0.5 * 0.4 + 0.001)


# --- the light ---


func test_the_flash_light_is_warm_bright_and_one() -> void:
	var flash := _flash()
	flash.fire(0.3, Vector3.RIGHT)
	assert_bool(flash.light.visible).is_true()
	assert_float(flash.light.light_energy).is_between(LIGHT_ENERGY.x, LIGHT_ENERGY.y)
	assert_float(flash.light.omni_range).is_between(LIGHT_RANGE.x, LIGHT_RANGE.y)
	assert_bool(flash.light.shadow_enabled).is_false()
	var colour := flash.light.light_color
	assert_bool(colour.r >= colour.g and colour.g >= colour.b).is_true()
	# It sits ahead of the muzzle, so it lights what the gun points at.
	assert_float(flash.light.global_position.x).is_greater(flash.global_position.x)
	var second := _flash()
	second.fire(0.3, Vector3.RIGHT)
	assert_int(get_tree().get_nodes_in_group(MuzzleFlash.LIT_GROUP).size()).is_equal(1)


func test_the_light_never_dips_under_the_floor_when_the_gun_points_down() -> void:
	var flash := _flash()
	flash.global_position = Vector3(0.0, 0.4, 0.0)
	# A rifle pointing at the ground at 60 degrees.
	flash.fire(0.3, Vector3(1.0, -1.7, 0.0))
	assert_float(flash.light.global_position.y).is_greater(flash.global_position.y)
	assert_float(flash.light.global_position.y).is_greater(0.5)


# --- the floors check itself ---


## A summary a good flash gives, from the floors file.
func _good() -> Dictionary:
	var floors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FlashFloors.PATH))
	var summary := {}
	for key: String in floors["min"]:
		summary[key] = floors["min"][key] * 2
	for key: String in floors["max"]:
		summary[key] = floors["max"][key] * 0.5
	return summary


func test_the_floors_name_frames_size_and_brightness() -> void:
	var floors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FlashFloors.PATH))
	for key in ["frames_seen", "area_pct", "height_pct", "hot_px", "peak_luma", "mean_rise"]:
		assert_bool(floors["min"].has(key)).override_failure_message(key).is_true()
	assert_bool(floors["max"].has("screen_gain")).is_true()
	assert_float(floors["min"]["frames_seen"]).is_greater_equal(MIN_FRAMES)


func test_a_good_flash_passes_the_floors() -> void:
	assert_array(FlashFloors.problems(_good())).is_empty()


func test_a_flash_seen_for_too_few_frames_fails_the_floors() -> void:
	var summary := _good()
	summary["frames_seen"] = MIN_FRAMES - 1
	assert_array(FlashFloors.problems(summary)).is_not_empty()


func test_a_flash_too_small_or_too_dim_fails_the_floors() -> void:
	for key in ["area_pct", "height_pct", "hot_px", "peak_luma", "mean_rise"]:
		var summary := _good()
		summary[key] = 0
		assert_array(FlashFloors.problems(summary)).override_failure_message(key).is_not_empty()


func test_a_flash_that_blinds_fails_the_floors() -> void:
	var summary := _good()
	summary["screen_gain"] = 100.0
	assert_array(FlashFloors.problems(summary)).is_not_empty()


func test_the_summary_counts_the_frames_a_flash_is_seen_on() -> void:
	var rows: Array = []
	for n in 6:
		rows.append({"n": n, "up": n in [2, 3, 4], "quad_px": 500 if n in [2, 3, 4] else 0})
	var summary := FlashFloors.summarise(rows)
	assert_int(summary["frames_up"]).is_equal(3)
	assert_int(summary["frames_seen"]).is_equal(3)
	assert_int(summary["first_frame"]).is_equal(2)
	assert_int(summary["last_frame"]).is_equal(4)
