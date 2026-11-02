extends SceneTree
## Run by `test_audio_quit.gd` in a child Godot (not a test itself): starts the night's beds and two
## sounds, then quits at once, the way a test run or a capture ends. `--stop` calls `stop_all` just
## before. Whatever the audio server still holds at that moment is printed by the engine as `leaked
## at exit` or `still in use` (#487); the child runs with `--verbose`, which also names them.

const FRAMES := 20

var _frames := 0
var _stop := false


func _initialize() -> void:
	_stop = OS.get_cmdline_user_args().has("--stop")


func _process(_delta: float) -> bool:
	var audio := root.get_node("Audio") as AudioService
	_frames += 1
	if _frames == 1:
		audio.start_bed(&"bed_crickets")
		audio.start_bed(&"bed_highway")
		audio.play(&"door_open", Vector3(2, 0, 2))
		audio.play(&"melee_swing", Vector3(1, 0, 1))
	if _frames == FRAMES:
		if _stop:
			audio.stop_all()
		quit()
	return false
