extends Node
## A quiet night with the wind (#782): the first round is on but nothing has spawned yet, so there
## is no gunfire and no score, only the beds (the crickets, the highway, the projector) and the
## wind: its base layer and its gusts. The Ambience bus is recorded as a stem, and every gust
## prints `WIND <seconds> gust <file> db=<draw> length=<s> lull=<s> detail=<id>` and every detail
## `WIND <seconds> detail <id>`, which `tools/audio/wind_levels.py night` reads.
##
## Run under Movie Maker (`--write-movie <folder>/wind.png --fixed-fps 10`) with the user arguments
## `--out=<folder>` (the stem is written there), `--seconds=S` (default 120), `--seed=N` (the wind's
## seed, default 785) and `--solo` (the crickets, the highway and the projector stopped: the wind
## alone, for its loudness) or `--nowind` (the wind stopped: the beds alone, to read what the wind
## adds). The same seed gives the same gusts with or without `--solo`.

const MOVIE_FPS := 10.0
const FIELD_VIEW_FROM := Vector3(-51.5, 3.2, -40.0)
const FIELD_VIEW_AT := Vector3(-62.0, 1.3, -46.0)
const BAR_WIDTH := 480.0

var _args := {}
var _night: Night
var _wind: WindSounds
var _record: AudioEffectRecord
var _frames := 0
var _origin := 0.0
var _logged := 0
var _label: Label
var _bar: ColorRect
var _done := false


func _ready() -> void:
	_args = _parse_args()
	Audio.seed_random(int(_args.get("seed", 785)))
	Audio.played.connect(_on_played)
	_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Ambience"), _record)
	_build_overlay()
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.first_spawn_delay = 100000.0
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, Night.SEED, tuning)
	var camera := Camera3D.new()
	camera.fov = 62.0
	add_child(camera)
	camera.make_current()
	camera.look_at_from_position(FIELD_VIEW_FROM, FIELD_VIEW_AT)
	_night.state.apply_events(_night.server.rules.apply(RulesAction.skip_break()))
	_wind = _night.view.sounds.wind
	_wind.reseed(int(_args.get("seed", 785)))
	if _args.has("solo"):
		_solo()
	if _args.has("nowind"):
		_wind.stop()
	_frames = 0
	_logged = 0
	_wind.played.clear()
	_origin = _wind.clock()
	_record.set_recording_active(true)
	print("CAPTURE start at movie frame %d" % Engine.get_frames_drawn())


## Stops the other beds, so the stem is the wind alone.
func _solo() -> void:
	for id in NightSounds.NIGHT_BEDS:
		Audio.stop_bed(id)
	Audio.stop_bed(NightSounds.SCORE)
	for anchor in _night.view.sounds.find_children("Projector", "Node3D", false, false):
		for player in anchor.get_children():
			if player is AudioStreamPlayer3D:
				(player as AudioStreamPlayer3D).stop()


func _process(_delta: float) -> void:
	if _wind == null or _done:
		return
	_frames += 1
	while _logged < _wind.played.size():
		var gust: Dictionary = _wind.played[_logged]
		print(
			(
				"WIND %.2f gust %s db=%.2f length=%.2f lull=%.2f detail=%s"
				% [
					float(gust["at"]) - _origin,
					gust["file"],
					gust["db"],
					gust["length"],
					gust["lull"],
					gust["detail"]
				]
			)
		)
		_logged += 1
	_bar.size.x = maxf(2.0, BAR_WIDTH * _wind.swell())
	_label.text = (
		"%5.1f s   %s"
		% [
			_frames / MOVIE_FPS,
			"gust %d: %s" % [_logged, _gust_text()] if _wind.is_blowing() else "base layer only"
		]
	)
	if _frames / MOVIE_FPS >= float(_args.get("seconds", 120)):
		_finish()


func _gust_text() -> String:
	var gust: Dictionary = _wind.played[_logged - 1]
	return (
		"%.1f s, %+.1f dB, from %d deg%s"
		% [
			gust["length"],
			gust["db"],
			int(rad_to_deg(fposmod(gust["bearing"], TAU))),
			(
				"  (+ %s)" % String(gust["detail"]).trim_prefix("wind_")
				if gust["detail"] != &""
				else ""
			)
		]
	)


func _on_played(id: StringName, _position: Variant) -> void:
	if String(id).begins_with("wind_") and id != WindSounds.GUST:
		print("WIND %.2f detail %s" % [_frames / MOVIE_FPS, id])


func _finish() -> void:
	_done = true
	for i in int(3.0 * MOVIE_FPS):
		await get_tree().process_frame
	var out := String(_args.get("out", ""))
	_record.set_recording_active(false)
	var wav := _record.get_recording()
	if wav != null and out != "":
		var name := "stem_ambience_solo.wav" if _args.has("solo") else "stem_ambience.wav"
		if _args.has("nowind"):
			name = "stem_ambience_nowind.wav"
		wav.save_to_wav("%s/%s" % [out, name])
	var index := AudioServer.get_bus_index(&"Ambience")
	AudioServer.remove_bus_effect(index, AudioServer.get_bus_effect_count(index) - 1)
	print("CAPTURE done at %.1f s" % (_frames / MOVIE_FPS))
	_night.queue_free()
	await _night.tree_exited
	Audio.stop_all()
	await Audio.wait_for_mixer()
	get_tree().quit()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	_bar = ColorRect.new()
	_bar.position = Vector2(16.0, 64.0)
	_bar.size = Vector2(2.0, 14.0)
	_bar.color = Color(0.62, 0.78, 0.95)
	layer.add_child(_bar)


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
