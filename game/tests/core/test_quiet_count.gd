extends GdUnitTestSuite
## `QuietCount.settle` takes the sounds and motions in flight out of a count of objects: a reading
## after it is the same wherever the fight was when it began (#1102).

## Sounds started and tweens run for the busy reading; they must show in it, or the test proves
## nothing.
const SOUNDS := 16
const TWEENS := 6
## Longer than the wait for the tweens' end is a few frames, and than the sounds' own length is not
## (the sounds below last three to six seconds), so each of the two waits is needed.
const TWEEN_SECONDS := 1.5
## Rounds of sounds and tweens; the last two settle to the same count.
const ROUNDS := 3
## Objects the quiet reading may differ by (a frame of the engine's own).
const JITTER := 2

var _sounds: Array[StringName] = [
	&"crane_spin",
	&"round_start",
	&"special_round",
	&"wind_gust",
	&"generator_down",
	&"zombie_roar",
	&"vox_downed_1",
	&"vox_boss_arrive_1"
]


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _start_sounds_and_tweens(host: Node3D) -> void:
	for i in SOUNDS:
		if i % 2 == 0:
			Audio.play(_sounds[i % _sounds.size()], Vector3(float(i), 1.0, 0.0))
		else:
			Audio.play(_sounds[i % _sounds.size()])
	for i in TWEENS:
		var tween := host.create_tween()
		tween.tween_property(host, "position:x", float(i + 1), TWEEN_SECONDS)
		tween.tween_callback(host.set_visible.bind(true))


func test_sounds_and_tweens_in_flight_are_not_held() -> void:
	await AudioSettle.until_idle(get_tree())
	for id: StringName in _sounds:
		Audio.preload_sound(id)
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	# Two rounds first make what stays (a tween's class, the first use of a voice's slot), and the
	# second ends in a settle like the one checked; no assertion is made between the readings, since
	# an assertion is objects of its own.
	var settles := 0
	var quiet := 0
	var busy := 0
	var settled := 0
	for round in ROUNDS:
		_start_sounds_and_tweens(host)
		await get_tree().process_frame
		busy = _objects()
		if await QuietCount.settle(get_tree()):
			settles += 1
		settled = _objects()
		if round == ROUNDS - 2:
			quiet = settled
	assert_int(settles).override_failure_message("a tween never finished").is_equal(ROUNDS)
	(
		assert_int(busy - quiet)
		. override_failure_message("in flight: %d" % (busy - quiet))
		. is_greater_equal(2 * TWEENS)
	)
	(
		assert_int(absi(settled - quiet))
		. override_failure_message("quiet %d, busy %d, settled %d" % [quiet, busy, settled])
		. is_less_equal(JITTER)
	)
