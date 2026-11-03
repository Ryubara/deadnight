extends GdUnitTestSuite
## A warning has to carry through cover (#680): the grenade's fuse beep takes only part of the
## dulling a wall gives a shot, so the player behind the car or the wall still hears the fuse.

var _audio: AudioService
var _listener: Node3D


func before_test() -> void:
	_listener = auto_free(Node3D.new())
	add_child(_listener)
	_audio = AudioService.new()
	_audio.listener = _listener
	_audio.seed_random(7)
	add_child(_audio)
	_audio.occlusion_probe = func(_from: Vector3, _to: Vector3) -> float: return 1.0


func after_test() -> void:
	_audio.free()
	# The game's own service gives the UI hook back to itself.
	Audio.install_ui_hook()


func test_a_beep_behind_a_wall_keeps_more_level_and_brightness_than_a_shot() -> void:
	var shot := _audio.play(&"shot_rifle", Vector3(0, 0, 10)) as AudioStreamPlayer3D
	var shot_cutoff := shot.attenuation_filter_cutoff_hz
	var beep_def := SoundCatalog.get_def(&"grenade_beep")
	assert_float(beep_def.occlusion_scale).is_between(0.1, 0.6)
	var beep := _audio.play(&"grenade_beep", Vector3(0, 0, 10)) as AudioStreamPlayer3D
	var expected := beep_def.volume_db + AudioService.OCCLUSION_DB * beep_def.occlusion_scale
	assert_float(beep.volume_db).is_equal_approx(expected, 0.001)
	assert_float(beep.attenuation_filter_cutoff_hz).is_greater(shot_cutoff + 1000.0)


func test_every_other_sound_keeps_the_full_occlusion() -> void:
	var odd: Array[String] = []
	for id in SoundCatalog.ids():
		var def := SoundCatalog.get_def(id)
		if def.occlusion_scale != 1.0 and id != &"grenade_beep":
			odd.append(String(id))
	assert_array(odd).is_empty()
