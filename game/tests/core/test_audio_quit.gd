# Quitting leaves nothing held by the audio server (#487). A stopped or playing voice stays in the
# server, holding its stream, until the mixer thread has taken a few steps; a process that quits
# at once printed `ObjectDB instances were leaked at exit` and `resources still in use at exit`,
# at random on a loaded machine, and failed CI's leak check with every test passing. The audio
# service now waits those steps out as it leaves the tree. A child Godot ends the way a test run
# does and its output is read for the two lines.
extends GdUnitTestSuite

const PROBE := "res://tests/core/audio_quit_probe.gd"
const LEAK_LINES := ["leaked at exit", "still in use", "Leaked instance", "Resource still in use"]


## What the child Godot printed, errors included.
func _run_probe(extra: PackedStringArray = []) -> String:
	var output := []
	var arguments := PackedStringArray(
		["--headless", "--verbose", "--path", ProjectSettings.globalize_path("res://"), "-s", PROBE]
	)
	if not extra.is_empty():
		arguments.append("--")
		arguments.append_array(extra)
	OS.execute(OS.get_executable_path(), arguments, output, true)
	return "\n".join(PackedStringArray(output))


func _leak_lines(text: String) -> PackedStringArray:
	var found := PackedStringArray()
	for line in text.split("\n"):
		for needle: String in LEAK_LINES:
			if line.contains(needle):
				found.append(line.strip_edges())
				break
	return found


func test_quitting_with_sounds_playing_leaves_no_stream_held() -> void:
	assert_array(_leak_lines(_run_probe())).is_empty()


func test_quitting_right_after_stop_all_leaves_no_stream_held() -> void:
	assert_array(_leak_lines(_run_probe(["--stop"]))).is_empty()


func test_the_blocking_wait_returns_once_the_mixer_has_stepped() -> void:
	var audio := auto_free(AudioService.new()) as AudioService
	assert_bool(audio.drain_mixer_blocking()).is_true()
