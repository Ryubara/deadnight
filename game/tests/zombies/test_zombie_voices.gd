extends GdUnitTestSuite
## The dead's voices, from the frames and events a client hears: rationed idle groans, the snarl
## when one is noticed, the swing cue timed to the blow, the headliner's roar and growl, hurt and
## death, feet in the clips' cadence, and the budget that keeps 28 zombies readable. No wall time:
## the voices' clock is the `delta` each test passes.

const FRAME := 1.0 / 60.0
const CHASE := ZombieBody.Mode.CHASE
const ATTACK := ZombieBody.Mode.ATTACK
const EMERGING := ZombieBody.Mode.EMERGING
const DYING := ZombieBody.Mode.DYING

var _audio: AudioService
var _listener: Node3D
var _voices: ZombieVoices


func before_test() -> void:
	_listener = auto_free(Node3D.new())
	add_child(_listener)  # at the origin, looking down -Z
	_audio = AudioService.new()
	_audio.listener = _listener
	_audio.seed_random(3)
	add_child(_audio)
	_voices = ZombieVoices.new(_audio, 5)
	_voices.windups = {&"headliner": 1.2}


func after_test() -> void:
	_audio.free()
	Audio.install_ui_hook()


func _entry(
	id: int,
	at: Vector3,
	mode: int = CHASE,
	look: StringName = &"walker",
	speed := 0.0,
	episode := 0
) -> Dictionary:
	return {
		"id": id,
		"position": at,
		"yaw": 0.0,
		"mode": mode,
		"episode": episode,
		"speed": speed,
		"look": look,
	}


## Steps the voices and the service for `seconds`; `frame.call(t)` gives each step's zombies.
func _run(seconds: float, frame: Callable) -> void:
	var t := 0.0
	while t < seconds:
		var entries: Array[Dictionary] = []
		entries.assign(frame.call(t))
		_voices.update(entries, FRAME)
		_audio.advance(FRAME)
		t += FRAME


func _count(sound: StringName) -> int:
	return int(_voices.requested.get(sound, 0))


func test_28_zombies_due_at_once_start_one_idle_voice() -> void:
	var crowd: Array[Dictionary] = []
	for i in 28:
		crowd.append(_entry(i + 1, Vector3(i * 0.2, 0, -25.0 - i * 0.35)))
	_voices.update(crowd, 0.0)
	assert_int(_voices.requested.size()).is_equal(0)
	_voices.update(crowd, 12.0)  # every timer has run out in the same frame
	assert_int(_count(&"zombie_groan")).is_equal(1)
	assert_int(_audio.budget_3d().group_count(&"zombie_voice")).is_equal(1)


func test_idle_voices_keep_to_the_hordes_gate_over_time() -> void:
	var crowd: Array[Dictionary] = []
	for i in 28:
		crowd.append(_entry(i + 1, Vector3(i * 0.2, 0, -25.0 - i * 0.35)))
	var seen := {"most": 0}  # a lambda copies plain variables; a dictionary is shared
	_run(
		30.0,
		func(_t: float) -> Array:
			seen["most"] = maxi(seen["most"], _audio.budget_3d().group_count(&"zombie_voice"))
			return crowd
	)
	var total := _count(&"zombie_groan")
	# One every 0.6 to 1.6 s at most; and none from zombies who are not due: well under 28 a second.
	assert_int(total).is_less_equal(int(30.0 / ZombieVoices.IDLE_GAP.x) + 1)
	assert_int(total).is_greater(5)
	assert_int(seen["most"]).is_less_equal(SoundCatalog.GROUP_LIMITS[&"zombie_voice"])


func test_a_zombie_that_comes_within_range_snarls_once() -> void:
	_run(
		12.0,
		func(t: float) -> Array:
			# walks in at 3 m/s from 40 m
			return [_entry(1, Vector3(0, 0, -40.0 + t * 3.0), CHASE, &"walker", 3.0)]
	)
	assert_int(_count(&"zombie_alert")).is_equal(1)


func test_a_runner_shrieks_and_the_headliner_does_not_snarl() -> void:
	_voices.update([_entry(1, Vector3(0, 0, -10.0), CHASE, &"runner", 3.0)], FRAME)
	_voices.update([_entry(2, Vector3(5, 0, -10.0), CHASE, &"headliner", 0.6)], FRAME)
	assert_int(_count(&"zombie_shriek")).is_equal(1)
	assert_int(_count(&"zombie_alert")).is_equal(0)


func test_the_swing_cue_peaks_on_the_blow() -> void:
	var at := Vector3(0, 0, -2.0)
	_voices.update([_entry(1, at, CHASE)], FRAME)
	var swung_at := -1.0
	var heard_at := -1.0
	var t := 0.0
	while t < 1.0:
		var entries: Array[Dictionary] = [_entry(1, at, ATTACK, &"walker", 0.0, 1)]
		_voices.update(entries, FRAME)
		if swung_at < 0.0:
			swung_at = t
		if heard_at < 0.0 and _count(&"zombie_grunt") > 0:
			heard_at = t
		t += FRAME
	var lead: float = ZombieVoiceTable.get_role(&"walker", "swing_lead")
	# The file peaks `lead` into itself; started this long after the swing, it peaks on the blow.
	assert_float(heard_at - swung_at + lead).is_equal_approx(
		ZombieVoices.DEFAULT_WINDUP, FRAME * 2.0
	)


func test_a_long_swing_grunts_again_for_each_blow_at_the_boards() -> void:
	var at := Vector3(0, 0, -2.0)
	_voices.update([_entry(1, at, CHASE)], FRAME)
	_run(4.0, func(_t: float) -> Array: return [_entry(1, at, ATTACK, &"walker", 0.0, 1)])
	assert_int(_count(&"zombie_grunt")).is_between(3, 4)


func test_the_headliner_roars_on_arrival_growls_before_its_blow_and_roars_falling() -> void:
	var at := Vector3(0, 0, -12.0)
	_voices.update([_entry(9, at, EMERGING, &"headliner")], FRAME)
	assert_int(_count(&"zombie_roar")).is_equal(1)
	_voices.update([_entry(9, at, CHASE, &"headliner", 0.6)], FRAME)
	var started := _audio.started
	var growled_at := -1.0
	var t := 0.0
	while t < 1.5:
		_voices.update([_entry(9, at, ATTACK, &"headliner", 0.0, 1)], FRAME)
		if growled_at < 0.0 and _count(&"zombie_growl_boss") > 0:
			growled_at = t
		t += FRAME
	assert_float(growled_at).is_equal_approx(1.2 - 0.92, FRAME * 2.0)
	assert_int(_audio.started).is_greater(started)
	_voices.update([_entry(9, at, DYING, &"headliner", 0.0, 2)], FRAME)
	assert_int(_count(&"zombie_roar")).is_equal(2)


func test_a_headliner_seen_already_walking_does_not_roar_again() -> void:
	_voices.update([_entry(9, Vector3(0, 0, -12.0), CHASE, &"headliner", 0.6)], FRAME)
	assert_int(_count(&"zombie_roar")).is_equal(0)


func test_a_hit_hurts_and_the_killing_one_does_not() -> void:
	_voices.update([_entry(1, Vector3(0, 0, -6.0))], FRAME)
	_voices.on_event({"type": &"zombie_damaged", "zombie_id": 1, "health": 40.0})
	assert_int(_count(&"zombie_hurt")).is_equal(1)
	_voices.on_event({"type": &"zombie_damaged", "zombie_id": 1, "health": 30.0})  # too soon
	assert_int(_count(&"zombie_hurt")).is_equal(1)
	_voices.update([_entry(1, Vector3(0, 0, -6.0))], 1.0)
	_voices.on_event({"type": &"zombie_damaged", "zombie_id": 1, "health": 0.0})
	assert_int(_count(&"zombie_hurt")).is_equal(1)


func test_death_is_heard_once_when_the_zombie_falls_and_not_for_one_already_down() -> void:
	var at := Vector3(0, 0, -6.0)
	_voices.update([_entry(1, at), _entry(2, at, DYING)], FRAME)
	assert_int(_count(&"zombie_death")).is_equal(0)
	for _i in 3:
		_voices.update([_entry(1, at, DYING, &"walker", 0.0, 1), _entry(2, at, DYING)], FRAME)
	assert_int(_count(&"zombie_death")).is_equal(1)


func _steps_over(seconds: float, look: StringName, speed: float, from_z := -6.0) -> int:
	var sound: StringName = ZombieVoiceTable.step_sound(look, speed)
	var at := Vector3(0, 0, from_z)
	_run(seconds, func(_t: float) -> Array: return [_entry(1, at, CHASE, look, speed)])
	return _count(sound)


## The steps a gait makes in `seconds`: two a cycle, at the cycle the clip is played in.
func _expected_steps(seconds: float, look: StringName, speed: float) -> int:
	return roundi(seconds / ZombieVoiceTable.cycle_seconds(look, speed) * 2.0)


func test_walking_feet_fall_twice_per_walk_cycle() -> void:
	var steps := _steps_over(20.0, &"walker", 1.0)
	assert_int(steps).is_between(29, 31)  # 20 s / 1.3333 s * 2, the walk played at its own pace
	assert_int(steps).is_between(
		_expected_steps(20.0, &"walker", 1.0) - 1, _expected_steps(20.0, &"walker", 1.0) + 1
	)


func test_running_feet_keep_the_runs_faster_cadence() -> void:
	# At 3.0 m/s a runner is in the run, played at 0.7 to 0.8 times: its steps follow the feet.
	var expected := _expected_steps(10.0, &"runner", 3.0)
	assert_int(_steps_over(10.0, &"runner", 3.0)).is_between(expected - 1, expected + 1)
	# At the cap the run is played faster than it was drawn, and the feet are quicker.
	var sprint := _expected_steps(10.0, &"runner", 6.0)
	assert_int(sprint).is_greater(expected)


func test_the_crawler_drags_and_the_brute_stomps_at_their_own_sounds() -> void:
	var drags := _expected_steps(10.0, &"crawler", 0.5)
	assert_int(_steps_over(10.0, &"crawler", 0.5)).is_between(drags - 1, drags + 1)
	assert_int(_count(&"zombie_drag")).is_greater(0)
	var stomps := _expected_steps(10.0, &"brute", 0.8)
	assert_int(_steps_over(10.0, &"brute", 0.8)).is_between(stomps - 1, stomps + 1)
	assert_int(_count(&"zombie_step_stomp")).is_greater(0)


func test_a_standing_zombie_and_a_far_one_make_no_footsteps() -> void:
	assert_int(_steps_over(5.0, &"walker", 0.0)).is_equal(0)
	assert_int(_steps_over(5.0, &"walker", 1.0, -60.0)).is_equal(0)


func test_a_horde_of_28_walking_and_swinging_stays_inside_the_budget() -> void:
	var crowd: Array[Dictionary] = []
	for i in 28:
		var angle := TAU * float(i) / 28.0
		var look: StringName = [&"walker", &"runner", &"brute", &"crawler"][i % 4]
		var mode := ATTACK if i % 3 == 0 else CHASE
		crowd.append(
			_entry(
				i + 1,
				Vector3(sin(angle), 0, cos(angle)) * (4.0 + i * 0.5),
				mode,
				look,
				1.5 + i % 3,
				1
			)
		)
	var most := {"voices": 0, "steps": 0, "all": 0}
	_run(
		20.0,
		func(_t: float) -> Array:
			var budget := _audio.budget_3d()
			most["voices"] = maxi(most["voices"], budget.group_count(&"zombie_voice"))
			most["steps"] = maxi(most["steps"], budget.group_count(&"zombie_step"))
			most["all"] = maxi(most["all"], budget.active_count())
			return crowd
	)
	assert_int(most["voices"]).is_less_equal(SoundCatalog.GROUP_LIMITS[&"zombie_voice"])
	assert_int(most["steps"]).is_less_equal(SoundCatalog.GROUP_LIMITS[&"zombie_step"])
	assert_int(most["all"]).is_less_equal(AudioService.POOL_3D)
	assert_int(_audio.started).is_greater(50)
