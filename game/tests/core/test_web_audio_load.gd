# The browser audio check (`tools/web_smoke/audio_load.py`) plays the service's whole pool: if the
# pool changes, the check has to play the new size or its result says nothing about the build.
extends GdUnitTestSuite

const LOAD_SCENE := preload("res://tools/web_audio_load/web_audio_load.gd")


func test_the_busiest_phase_plays_the_whole_pool() -> void:
	var most_positional := 0
	var most_flat := 0
	for phase: Dictionary in LOAD_SCENE.PHASES:
		most_positional = maxi(most_positional, phase.get("voices", 0))
		most_flat = maxi(most_flat, phase.get("flat", 0))
	assert_int(most_positional).is_equal(AudioService.POOL_3D)
	assert_int(most_flat).is_equal(AudioService.POOL_2D)


func test_the_phases_compare_one_setting_at_a_time() -> void:
	var names: Array[String] = []
	for phase: Dictionary in LOAD_SCENE.PHASES:
		names.append(phase["name"])
	for needed in ["silence", "open", "filtered", "ducked", "bus_quiet", "voices_44", "hitches_44"]:
		assert_array(names).contains([needed])
	assert_int(names.size()).is_equal(names.duplicate().size())
