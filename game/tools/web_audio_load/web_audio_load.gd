extends Node3D
## A stand-in for a loud night's sound, to be run in a browser (`tools/web_smoke/audio_load.py`) and
## natively: it starts looping voices in steps and says what each step cost and what came out. Not
## part of the game (the main scene never loads it).
##
## It answers two questions the web build raised (`docs/research/web-export.md`, Audio): do the
## things the mix relies on (a bus effect for the duck, a player's distance filter) still apply when
## the browser plays the sounds, and what does a pool of voices cost a frame and does it crackle.
## Each phase marks its start, the end of its settling second and its end into
## `window.deadnight_marks` (`WebProbe.mark`) so the page can cut what its audio tap heard, and the
## frame times seen here are printed and put in `window.deadnight_audio_load` at the end.
##
## `?playback=stream|sample` on the page (or `--playback=...` natively) picks how the players play;
## without it the project's default (a browser's is samples).

const PHASE_SECONDS := 4.0
## The first second of a phase is not measured: voices are starting and filters settling.
const SETTLE_SECONDS := 1.0
const LOOP := "res://assets/audio/world/generator_hum_1.ogg"
const BRIGHT := "res://assets/audio/ambience/crickets_1.ogg"
const EFFECTS_BUS := &"Effects"
const VOICE_DB := -18.0
const RING_MIN := 4.0
const RING_MAX := 22.0
const OPEN_CUTOFF_HZ := 20500.0
const FILTERED_CUTOFF_HZ := 800.0
const DUCK_DB := -12.0
## What the service's duck is asked for in the `svc_ducked` phase, and the stand-in sound it plays:
## the brightest file the game has (a low-pass shows on it), looped, on the Effects bus like a shot.
const SERVICE_DUCK_DB := -12.0
const SERVICE_SOUND := &"rig_bright"
const SERVICE_DISTANCE := 5.0
## The bus's own volume (the settings screen's slider) for the `bus_quiet` phase.
const QUIET_BUS_DB := -12.0
## The stall of the last phase, every `HITCH_EVERY` seconds: a frame that takes this long on the
## main thread (a first-use shader compile, a garbage collection). One second in thirty of a real
## night has a frame about this long (`docs/research/web-export.md`).
const HITCH_MS := 60
const HITCH_EVERY := 0.5
## One phase: what plays and with which setting. `voices` positional, `flat` non-positional, `fixed`
## starts the voice at the beginning of its file (no random offset).
const PHASES: Array[Dictionary] = [
	{"name": "silence"},
	{"name": "open", "voices": 1, "sound": BRIGHT, "fixed": true},
	{"name": "filtered", "voices": 1, "sound": BRIGHT, "cutoff": FILTERED_CUTOFF_HZ, "fixed": true},
	{"name": "ducked", "voices": 1, "sound": BRIGHT, "duck_db": DUCK_DB, "fixed": true},
	{"name": "bus_quiet", "voices": 1, "sound": BRIGHT, "bus_db": QUIET_BUS_DB, "fixed": true},
	# The game's own service (`Audio`) plays one bright loop, so what the player hears of the duck, the
	# wall and the rear cue is measured through the code that does them: `svc_open` is the reference,
	# the others change one thing (`svc_duck_db` is the sound's own duck, `occlusion` the wall's
	# 0..1, `behind` puts the voice behind the listener, `rear_cue` whether it is darkened there).
	{"name": "svc_open", "service": true},
	{"name": "svc_ducked", "service": true, "svc_duck_db": SERVICE_DUCK_DB},
	{"name": "svc_occluded", "service": true, "occlusion": 1.0},
	{"name": "svc_behind", "service": true, "behind": true, "rear_cue": false},
	{"name": "svc_rear", "service": true, "behind": true, "rear_cue": true},
	{"name": "voices_8", "voices": 8},
	{"name": "voices_16", "voices": 16},
	{"name": "voices_32", "voices": 32},
	{"name": "voices_44", "voices": 32, "flat": 12},
	{"name": "hitches_44", "voices": 32, "flat": 12, "hitch_ms": HITCH_MS},
]

var results: Array[Dictionary] = []

var _playback := -1
var _players: Array[Node] = []
var _phase := -1
var _clock := 0.0
var _deltas: PackedFloat64Array = PackedFloat64Array()
var _duck: AudioEffectAmplify
var _rng := RandomNumberGenerator.new()
var _done := false
var _settled := false


func _ready() -> void:
	_rng.seed = 88
	_playback = _requested_playback()
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	# The service's own voices are not used here, but its bus effects and layout are the game's.
	_next_phase()


func _process(delta: float) -> void:
	if _done:
		return
	_clock += delta
	_hitch(delta)
	if _clock >= SETTLE_SECONDS:
		if not _settled:
			_settled = true
			WebProbe.mark("audio:%s:measure" % PHASES[_phase]["name"])
		_deltas.append(delta)
	if _clock >= PHASE_SECONDS:
		_finish_phase()
		_next_phase()


## What the page or the command line asks for: 0 stream, 1 sample, -1 the project's default.
## A phase with `hitch_ms` stalls the main thread now and then, as a real frame sometimes does.
func _hitch(delta: float) -> void:
	var length: int = PHASES[_phase].get("hitch_ms", 0)
	if length > 0 and fmod(_clock, HITCH_EVERY) < delta:
		OS.delay_msec(length)


func _requested_playback() -> int:
	var asked := ""
	if OS.has_feature("web"):
		asked = str(
			JavaScriptBridge.eval(
				"new URLSearchParams(window.location.search).get('playback') || ''"
			)
		)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--playback="):
			asked = argument.trim_prefix("--playback=")
	match asked:
		"stream":
			return AudioServer.PLAYBACK_TYPE_STREAM
		"sample":
			return AudioServer.PLAYBACK_TYPE_SAMPLE
	return -1


func _next_phase() -> void:
	_clear()
	_phase += 1
	if _phase >= PHASES.size():
		_finish()
		return
	var spec := PHASES[_phase]
	_clock = 0.0
	_settled = false
	_deltas = PackedFloat64Array()
	WebProbe.mark("audio:%s:start" % spec["name"])
	if spec.get("service", false):
		_start_service(spec)
		return
	if spec.has("duck_db"):
		_set_duck(spec["duck_db"])
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(EFFECTS_BUS), spec.get("bus_db", 0.0))
	for i in int(spec.get("voices", 0)):
		_start_voice(spec, i, true)
	for i in int(spec.get("flat", 0)):
		_start_voice(spec, i, false)


## One bright voice through `Audio`, in front of the listener (the camera looks down -Z) or behind.
func _start_service(spec: Dictionary) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(EFFECTS_BUS), 0.0)
	var def := (
		SoundDef
		. make(
			SERVICE_SOUND,
			SoundCatalog.ROOT + "ambience/crickets_%d.ogg",
			1,
			{
				"loop": true,
				"volume_db": VOICE_DB,
				"pitch_semitones": 0.0,
				"group": &"generator",
				"rear_cue": spec.get("rear_cue", false),
				"duck_db": spec.get("svc_duck_db", 0.0),
				"duck_hold": 600.0 if spec.has("svc_duck_db") else 0.0,
			}
		)
	)
	SoundCatalog.get_def(&"ui_hover")  # builds the table
	SoundCatalog._defs[SERVICE_SOUND] = def
	var occlusion: float = spec.get("occlusion", 0.0)
	Audio.occlusion_probe = func(_from: Vector3, _to: Vector3) -> float: return occlusion
	var z := SERVICE_DISTANCE if spec.get("behind", false) else -SERVICE_DISTANCE
	Audio.play(SERVICE_SOUND, Vector3(0.0, 0.0, z))


func _start_voice(spec: Dictionary, index: int, positional: bool) -> void:
	var stream := (
		(load(spec.get("sound", LOOP)) as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
	)
	stream.loop = true
	var player: Node
	if positional:
		var voice := AudioStreamPlayer3D.new()
		voice.attenuation_filter_cutoff_hz = spec.get("cutoff", OPEN_CUTOFF_HZ)
		voice.unit_size = 8.0
		voice.max_distance = 60.0
		var angle := TAU * (index + _rng.randf()) / maxf(1.0, spec.get("voices", 1))
		var ring := _rng.randf_range(RING_MIN, RING_MAX) if spec.get("voices", 1) > 1 else 5.0
		voice.position = Vector3(cos(angle), 0.0, sin(angle)) * ring
		player = voice
	else:
		player = AudioStreamPlayer.new()
	player.set("stream", stream)
	player.set("bus", EFFECTS_BUS)
	player.set("volume_db", VOICE_DB)
	if _playback >= 0:
		player.set("playback_type", _playback)
	add_child(player)
	_players.append(player)
	# The phases that compare a setting start at the same place in the file, so only the setting
	# differs.
	player.call("play", 0.0 if spec.get("fixed", false) else _rng.randf() * stream.get_length())


func _set_duck(db: float) -> void:
	var bus := AudioServer.get_bus_index(EFFECTS_BUS)
	_duck = AudioEffectAmplify.new()
	_duck.volume_db = db
	AudioServer.add_bus_effect(bus, _duck)


func _clear() -> void:
	if has_node("/root/Audio"):
		Audio.stop_all()
		Audio.occlusion_probe = Callable()
	for player in _players:
		player.call("stop")
		player.set("stream", null)
		player.queue_free()
	_players.clear()
	if _duck != null:
		var bus := AudioServer.get_bus_index(EFFECTS_BUS)
		for index in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect(bus, index) == _duck:
				AudioServer.remove_bus_effect(bus, index)
				break
		_duck = null


func _finish_phase() -> void:
	WebProbe.mark("audio:%s:end" % PHASES[_phase]["name"])
	var sorted := Array(_deltas)
	sorted.sort()
	var total := 0.0
	for value: float in sorted:
		total += value
	var count := sorted.size()
	(
		results
		. append(
			{
				"phase": PHASES[_phase]["name"],
				"voices": int(PHASES[_phase].get("voices", 0)) + int(PHASES[_phase].get("flat", 0)),
				"frames": count,
				"mean_ms": snappedf(1000.0 * total / maxf(1.0, count), 0.1),
				"p95_ms": snappedf(1000.0 * (sorted[int(count * 0.95)] if count > 0 else 0.0), 0.1),
				"max_ms": snappedf(1000.0 * (sorted[count - 1] if count > 0 else 0.0), 0.1),
			}
		)
	)


func _finish() -> void:
	_done = true
	var text := JSON.stringify(
		{"playback": _playback, "mix_rate": AudioServer.get_mix_rate(), "phases": results}
	)
	print("AUDIO_LOAD ", text)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.deadnight_audio_load = %s" % text)
	elif DisplayServer.get_name() == "headless" or not OS.has_feature("editor"):
		await get_tree().process_frame
		get_tree().quit()
