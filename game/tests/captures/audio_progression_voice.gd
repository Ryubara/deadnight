extends Node
## The progression cheers (#1063) as a player hears them, recorded for a listening clip. Run under
## Movie Maker (`--write-movie <folder>/x.png --fixed-fps 15`); the movie's `.wav` is the mix.
##
## - `--mode=listen`: every take of every progression moment, both voices, one after another through
##   the real audio service (the local player's own flat voice), `TAKE <seconds> <id>` for each.
## - `--mode=beside`: what a cheer must not hide, as the player hears them: a pistol shot at the
##   muzzle and a groan 6 m off alone, then each moment in each voice (take 1) alone and with the
##   shot just before it (`BESIDE <seconds> <voice> <moment> alone|shot`). The mix has no effects
##   on any bus, so this is the sound of both together.
## - `--mode=fight`: a night the autopilot plays for `--seconds=S` game seconds, with a cheer told
##   every `--gap=G` seconds from `--first=F` (`CHEER <seconds> <moment>` when it plays, `GUN` and
##   `VOICE` for the rest, like `audio_soldier_night.gd`). `--voice=female` plays every soldier
##   line of the night with the female take set (the night's player is the male character).
##   The Voice, Effects and Ambience buses are recorded as stems into `--out=<folder>`.
##   With `--account=<xp>` the player has an account of that raw XP (a profile in memory), so the
##   night's kills pay XP, the rules tell the same `level_up`, `tier_up` and `unlock_earned` a game
##   server would (`SERVER <seconds> <event> <level>`) and the soldier cheers them as it does
##   online;
##   `--told=0` skips the cheers told by hand. `--challenges=6,12+` tells the server's
##   `challenge_done` for the player at those seconds (a `+` brings the `level_up` its reward paid,
##   in the same instant, so one line is said: the challenge's), as `ChallengeAward` would
##   (`TOLD <seconds> challenge_done`). The director's history is printed at the end
##   (`HISTORY <seconds> <moment> <speaker> <take>`) and written to `--out`.

const MOVIE_FPS := 15.0
const STEMS: Array[StringName] = [&"Voice", &"Effects", &"Ambience"]
const GAP_BETWEEN_TAKES := 0.6
const GAP_BETWEEN_MOMENTS := 1.0
const PLAYER := Night.PLAYER_ID
const LISTENER := Vector3(0.6, 1.6, 2.3)
const MUZZLE := Vector3(0.3, 1.45, -0.4)
const GROAN_AT := Vector3(0.6, 1.6, -3.7)
const SHOT_LEAD := 0.3

var _args := {}
var _frames := 0
var _night: Night
var _records := {}
var _female := false


func _ready() -> void:
	_args = _parse_args()
	_female = String(_args.get("voice", "male")) == "female"
	Audio.seed_random(1063)
	Audio.played.connect(_on_played)
	match String(_args.get("mode", "listen")):
		"listen":
			_listen()
		"beside":
			_beside()
		_:
			_fight()


func _process(_delta: float) -> void:
	_frames += 1


func _now() -> float:
	return _frames / MOVIE_FPS


func _wait(seconds: float) -> void:
	for i in int(ceil(seconds * MOVIE_FPS)):
		await get_tree().process_frame


func _on_played(id: StringName, _position: Variant) -> void:
	var text := String(id)
	if SoldierVoiceCatalog.is_take(id):
		var event := text.substr(text.find("_") + 1).rsplit("_", true, 1)[0]
		if SoldierVoiceCatalog.is_progress(StringName(event)):
			print("CHEER %.2f %s" % [_now(), id])
		else:
			print("VOICE %.2f %s" % [_now(), id])
	elif text.begins_with("shot_") or text.begins_with("blast_"):
		print("GUN %.2f %s" % [_now(), id])


func _listen() -> void:
	await _wait(1.0)
	var own_db := SoundCatalog.mix().own_voice_db
	for event in SoldierVoiceCatalog.PROGRESS:
		for voice: StringName in SoldierVoiceCatalog.voices():
			for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
				print("TAKE %.2f %s %s %d" % [_now(), voice, event, n])
				Audio.play(SoldierVoiceCatalog.take_id(event, n, voice), null, own_db)
				await _wait(SoldierVoiceCatalog.length(event, n, voice) + GAP_BETWEEN_TAKES)
		await _wait(GAP_BETWEEN_MOMENTS)
	await _wait(1.5)
	print("CAPTURE done at %.1f s" % _now())
	Audio.stop_all()
	await Audio.wait_for_mixer()
	get_tree().quit()


func _beside() -> void:
	get_window().size = Vector2i(160, 90)
	var listener := Camera3D.new()
	add_child(listener)
	listener.position = LISTENER
	listener.make_current()
	Audio.listener = listener
	var own_db := SoundCatalog.mix().own_voice_db
	await _wait(1.0)
	print("BESIDE %.2f - reference shot" % _now())
	Audio.play(&"shot_pistol", MUZZLE)
	await _wait(2.4)
	print("BESIDE %.2f - reference groan" % _now())
	Audio.play(&"zombie_groan", GROAN_AT)
	await _wait(3.4)
	for event in SoldierVoiceCatalog.PROGRESS:
		for voice: StringName in SoldierVoiceCatalog.voices():
			var id := SoldierVoiceCatalog.take_id(event, 1, voice)
			var seconds := SoldierVoiceCatalog.length(event, 1, voice)
			print("BESIDE %.2f %s %s alone" % [_now(), voice, event])
			Audio.play(id, null, own_db)
			await _wait(seconds + GAP_BETWEEN_TAKES)
			print("BESIDE %.2f %s %s shot" % [_now(), voice, event])
			Audio.play(&"shot_pistol", MUZZLE)
			await _wait(SHOT_LEAD)
			Audio.play(id, null, own_db)
			await _wait(seconds + GAP_BETWEEN_MOMENTS)
	await _wait(1.0)
	print("CAPTURE done at %.1f s" % _now())
	Audio.stop_all()
	await Audio.wait_for_mixer()
	get_tree().quit()


func _fight() -> void:
	for bus in STEMS:
		var record := AudioEffectRecord.new()
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), record)
		record.set_recording_active(true)
		_records[bus] = record
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud: Hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(hud)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.speed_base = 2.2
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.intro_seconds = 4.0
	_night = Night.new()
	_night.hud = hud
	if _args.has("account"):
		var path := "user://audio_progression_voice_profile.json"
		for leftover in [path, path + ".tmp", path + ".broken"]:
			if FileAccess.file_exists(leftover):
				DirAccess.remove_absolute(leftover)
		var store := ProfileStore.open(path, func() -> bool: return true)
		store.profile.xp = int(_args["account"])
		_night.profile_store = store
	add_child(_night)
	_night.shoulder_camera = true
	await _night.start(Night.Mode.AUTOPILOT, Night.SEED, tuning)
	var player := _night.player()
	if player != null:
		player.local_input = false
		player.capture_mouse = false
	var voice := _night.get_node("SoldierVoice") as SoldierVoice
	_night.state.event_received.connect(_on_server_event)
	if _female:
		voice.play = func(id: StringName, at: Variant, db: float) -> Variant:
			return Audio.play(StringName(String(id).replace("vox_", "voxf_")), at, db)
	var seconds := float(_args.get("seconds", 60))
	var first := float(_args.get("first", 14))
	var gap := float(_args.get("gap", 5))
	var next := 0
	var events: Array[StringName] = SoldierVoiceCatalog.PROGRESS
	if int(_args.get("told", 1)) == 0:
		next = events.size()
	var challenges := _challenge_times()
	var ticks := 0
	while _night.running and ticks / 60.0 < seconds:
		await _night.ticked
		ticks += 1
		if next < events.size() and ticks / 60.0 >= first + gap * next:
			voice.celebrate(events[next], PLAYER)
			print("TOLD %.2f %s" % [_now(), events[next]])
			next += 1
		while not challenges.is_empty() and ticks / 60.0 >= challenges[0]["at"]:
			_tell_challenge(challenges.pop_front()["with_level"])
	await _wait(3.0)
	var out := String(_args.get("out", ""))
	var history: Array = voice.director.history
	for line: Dictionary in history:
		if SoldierVoiceCatalog.is_progress(line["event"]):
			print(
				"HISTORY %.2f %s %d %d" % [line["at"], line["event"], line["speaker"], line["take"]]
			)
	if out != "":
		var file := FileAccess.open("%s/director_history.json" % out, FileAccess.WRITE)
		file.store_string(JSON.stringify(history, "  "))
		file.close()
	for bus: StringName in _records:
		var record: AudioEffectRecord = _records[bus]
		record.set_recording_active(false)
		var wav := record.get_recording()
		if wav != null and out != "":
			wav.save_to_wav("%s/stem_%s.wav" % [out, String(bus).to_lower()])
		var index := AudioServer.get_bus_index(bus)
		AudioServer.remove_bus_effect(index, AudioServer.get_bus_effect_count(index) - 1)
	_records.clear()
	print("CAPTURE done at %.1f s" % _now())
	_night.queue_free()
	await _night.tree_exited
	Audio.stop_all()
	await Audio.wait_for_mixer()
	get_tree().quit()


## The seconds (and whether a level comes with it) from `--challenges=6,12+`, earliest first.
func _challenge_times() -> Array[Dictionary]:
	var times: Array[Dictionary] = []
	for part: String in String(_args.get("challenges", "")).split(",", false):
		times.append({"at": float(part.trim_suffix("+")), "with_level": part.ends_with("+")})
	return times


## What the game server tells when a challenge is done: the event of `ChallengeAward`, and with
## `with_level` the level its XP reward paid.
func _tell_challenge(with_level: bool) -> void:
	var events: Array[Dictionary] = [
		{
			"type": &"challenge_done",
			"player_id": PLAYER,
			"id": &"d_kills",
			"family": 0,
			"text": "Put down 40",
			"target": 40,
			"rung": 0,
			"rungs": 1,
			"reward": {"xp": 50},
		}
	]
	if with_level:
		events.append({"type": &"level_up", "player_id": PLAYER, "level": 3, "total": 200})
	_night.state.apply_events(events)
	print("TOLD %.2f challenge_done%s" % [_now(), " + level_up" if with_level else ""])


func _on_server_event(event: Dictionary) -> void:
	match event["type"]:
		&"level_up", &"tier_up", &"unlock_earned", &"challenge_done":
			print("SERVER %.2f %s %d" % [_now(), event["type"], event.get("level", 0)])


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
