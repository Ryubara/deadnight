extends Node
## The second map's night with its wind (#809): the map and its yard, the night's wind
## (`WindSounds`) and the map's own sound (`SmallMapSounds`: its room tone, its roof wind and its
## yard) with the gust driving the roof and yard wind. The map's sound is started in place of the
## lot's crickets and highway (`docs/research/maps/small-map-audio.md`: the yard is frosted and
## still), so they are not here unless `--beds` says so. The listener stands in one place for the
## whole run and the Ambience bus is recorded as a stem. Every gust
## prints `WIND <seconds> gust ...` (the line `tools/audio/wind_levels.py` reads), and ten times a
## second `TRACE <seconds> swell=<0 to 1> roof=<dB the roof wind is heard at> yard=<dB the yard
## wind loop that comes in at the first window is at> blowing=<0|1>`, which
## `tools/audio/gust_levels.py` reads with the stems.
##
## Run under Movie Maker (`--write-movie <folder>/x.png --fixed-fps 10`) with the user arguments
## `--out=<folder>`, `--stand=roof|hall|open` (upstairs under the hole in the roof; the hall in line
## with a boarded window; the same window with its boards off), `--seconds=S` (default 120),
## `--seed=N` (the wind's seed, default 785), `--beds` (the lot's crickets and highway too, as
## `NightSounds` starts them, for the louder case) and `--swell=off` (the gusts do not drive the
## roof and yard wind: the same night as before this change, for the comparison). The stem is
## written to `<out>/stem_<stand>_<on|off>.wav`.

const MOVIE_FPS := 10.0
const EYE := 1.6
const BAR_WIDTH := 480.0
## The yard wind loop that is traced is the one that comes in at this window (the one whose boards
## the open stand takes off).
const YARD_WINDOW := &"start_1"
const STANDS := {
	"roof": {"at": Vector3(-3.0, 5.0, -4.0), "look": Vector3(-3.0, 5.0, -8.0)},
	"hall": {"at": Vector3(4.0, EYE, 9.5), "look": Vector3(4.0, 1.4, 16.0)},
	"open": {"at": Vector3(4.0, EYE, 9.5), "look": Vector3(4.0, 1.4, 16.0)},
}

var _args := {}
var _stand := "roof"
var _state := ClientState.new()
var _wind: WindSounds
var _sounds: SmallMapSounds
var _record: AudioEffectRecord
var _frames := 0
var _origin := 0.0
var _logged := 0
var _label: Label
var _bar: ColorRect
var _ready_to_run := false
var _done := false


func _ready() -> void:
	_args = _parse_args()
	_stand = String(_args.get("stand", "roof"))
	var seed_value := int(_args.get("seed", 785))
	Audio.seed_random(seed_value)
	_build_overlay()
	if _args.get("swell", "on") == "off":
		var tuning := SmallMapSoundTuning.current()
		tuning.roof_gust_db = 0.0
		tuning.yard_gust_db = 0.0
	var greybox := (load("res://world/smallmap/smallmap_greybox.tscn") as PackedScene).instantiate()
	add_child(greybox)
	var backdrop := (load("res://world/smallmap/backdrop.tscn") as PackedScene).instantiate()
	add_child(backdrop)
	var camera := Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.make_current()
	Audio.listener = camera
	var stand: Dictionary = STANDS[_stand]
	camera.look_at_from_position(stand["at"], stand["look"])
	for _i in 6:
		await get_tree().physics_frame
	_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Ambience"), _record)
	if _args.has("beds"):
		for id in NightSounds.NIGHT_BEDS:
			Audio.start_bed(id)
	_wind = WindSounds.new()
	_wind.name = "WindSounds"
	add_child(_wind)
	_wind.setup(seed_value)
	_wind.start()
	_state.player_id = 1
	_sounds = SmallMapSounds.new()
	add_child(_sounds)
	_sounds.wind = _wind
	_sounds.setup(_state, greybox, backdrop)
	if _stand == "open":
		_state.apply_events(
			[{"type": &"board_torn", "barricade_id": &"start_1", "boards": 0, "zombie_id": 1}]
		)
	_origin = _wind.clock()
	_record.set_recording_active(true)
	_ready_to_run = true
	print("CAPTURE start at movie frame %d, stand %s" % [Engine.get_frames_drawn(), _stand])


func _process(_delta: float) -> void:
	if not _ready_to_run or _done:
		return
	_frames += 1
	var now := _frames / MOVIE_FPS
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
	var roof := Audio.bed_fade_db(SmallMapSounds.ROOF_WIND)
	roof += SoundCatalog.get_def(SmallMapSounds.ROOF_WIND).volume_db
	var yard := -INF
	for source in _sounds.yard.source_of(SmallMapYard.WIND):
		if source.way != null and source.way.window == YARD_WINDOW:
			yard = source.db
	print(
		(
			"TRACE %.2f swell=%.3f roof=%.2f yard=%.2f blowing=%d"
			% [now, _wind.swell(), roof, yard, 1 if _wind.is_blowing() else 0]
		)
	)
	_bar.size.x = maxf(2.0, BAR_WIDTH * _wind.swell())
	_label.text = (
		"%5.1f s   %s   gusts drive the loops: %s\nroof wind %.1f dB   yard wind %.1f dB"
		% [
			now,
			_stand,
			_args.get("swell", "on"),
			roof,
			yard,
		]
	)
	if now >= float(_args.get("seconds", 120)):
		_finish()


func _finish() -> void:
	_done = true
	for i in int(3.0 * MOVIE_FPS):
		await get_tree().process_frame
	var out := String(_args.get("out", ""))
	_record.set_recording_active(false)
	var wav := _record.get_recording()
	if wav != null and out != "":
		wav.save_to_wav("%s/stem_%s_%s.wav" % [out, _stand, _args.get("swell", "on")])
	var index := AudioServer.get_bus_index(&"Ambience")
	AudioServer.remove_bus_effect(index, AudioServer.get_bus_effect_count(index) - 1)
	print("CAPTURE done at %.1f s" % (_frames / MOVIE_FPS))
	_sounds.queue_free()
	_wind.stop()
	for id in NightSounds.NIGHT_BEDS:
		Audio.stop_bed(id)
	Audio.stop_all()
	await Audio.wait_for_mixer()
	get_tree().quit()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	_bar = ColorRect.new()
	_bar.position = Vector2(16.0, 92.0)
	_bar.size = Vector2(2.0, 14.0)
	_bar.color = Color(0.62, 0.78, 0.95)
	layer.add_child(_bar)


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
