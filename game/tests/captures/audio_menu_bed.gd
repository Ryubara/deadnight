extends Node
## The menu's ambience and music alone, through the real service and the buses at the default
## settings (#926): the bed starts, plays `SECONDS`, is stopped and is given its fade out. The mix
## of the recording is the bed, which `tools/audio/menu_speakers.py` puts through a laptop's and a
## phone's speaker next to the hints of `audio_menu_levels.tscn`. Prints what starting it cost
## (the first start reads the files), `BED <seconds> <event>` for its beats, and how many beds
## still run after the fade out, and what mixing the streams costs a frame
## (`BED_MIX_COST_MS`).
##
## `gds godot -- --path game res://tests/captures/audio_menu_bed.tscn --write-movie <abs>/bed.avi
## --fixed-fps 60 --resolution 160x90`, then `ffmpeg -i bed.avi -vn -c:a pcm_s32le bed.wav`.

const FPS := 60.0
## Long enough for the bells' loop (113 s) to be heard whole, and a stay the length of a coffee.
const SECONDS := 120.0
const FADE_OUT_WAIT := 2.6
const MIX_SECONDS := 20.0

var _frame_start := 0


func _ready() -> void:
	get_window().size = Vector2i(160, 90)
	Settings.path = "user://audio_menu_bed.cfg"
	Settings.reset_defaults()
	Audio.seed_random(5)
	_print_mix_cost()
	_frame_start = Engine.get_frames_drawn()
	for id in MenuAmbience.BEDS:
		var began := Time.get_ticks_usec()
		Audio.start_bed(id)
		print("BED_START_COST_MS %s %.2f" % [id, (Time.get_ticks_usec() - began) / 1000.0])
	print("BED %.3f start" % _seconds())
	await _wait(SECONDS)
	print("BED %.3f stop" % _seconds())
	MenuAmbience.stop()
	await _wait(FADE_OUT_WAIT)
	var running := 0
	for id in MenuAmbience.BEDS:
		running += int(Audio.is_bed_running(id))
	print("BED %.3f beds still running: %d" % [_seconds(), running])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.reset_defaults()
	await get_tree().process_frame
	get_tree().quit()


## What the mixer spends on each stream per block of a 60 Hz frame, read off a playback of its own
## (the same decode the audio thread does), over `MIX_SECONDS` of the loop.
func _print_mix_cost() -> void:
	var block := int(AudioServer.get_mix_rate() / FPS)
	for id in MenuAmbience.BEDS:
		var stream := load(SoundCatalog.get_def(id).path_for(1)) as AudioStream
		var playback := stream.instantiate_playback()
		playback.start(0.0)
		var total := 0
		var worst := 0
		var blocks := int(MIX_SECONDS * FPS)
		for _i in blocks:
			var began := Time.get_ticks_usec()
			playback.mix_audio(1.0, block)
			var spent := Time.get_ticks_usec() - began
			total += spent
			worst = maxi(worst, spent)
		print(
			(
				"BED_MIX_COST_MS %s mean %.3f worst %.3f per frame"
				% [id, total / 1000.0 / blocks, worst / 1000.0]
			)
		)


func _seconds() -> float:
	return (Engine.get_frames_drawn() - _frame_start) / FPS


func _wait(seconds: float) -> void:
	for _i in int(round(seconds * FPS)):
		await get_tree().process_frame
