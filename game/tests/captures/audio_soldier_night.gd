extends Node
## An audio capture of a real night with the soldier's voice: the autopilot plays through the
## shoulder camera (the player's own, with `local_input` and `capture_mouse` off, so no mouse is
## held), and a few moments the bot does not reach in a short run (a boss, going down, getting up,
## a grenade, the generator) are told to the soldier as the events the server would send. The
## buses are recorded as stems (Voice, Effects, Ambience) so the voice can be measured against the
## guns and the beds, and every voice line prints `VOICE <seconds> <id>` for the report
## (`tools/audio/voice_report.py`).
##
## Run under Movie Maker (`--write-movie <folder>/night.png --fixed-fps 15`), with the user
## arguments `--out=<folder>` (the stems are written there) and `--seconds=S` (game seconds of
## autopilot before the told moments, default 70).

const MOVIE_FPS := 15.0
const STEMS: Array[StringName] = [&"Voice", &"Effects", &"Ambience"]
const TOLD_GAP := 7.0
const PLAYER := Night.PLAYER_ID

var _args := {}
var _night: Night
var _hud: Hud
var _records := {}
var _frames := 0
var _ticks := 0
var _told := false
var _done := false


func _ready() -> void:
	_args = _parse_args()
	Audio.seed_random(384)
	Audio.played.connect(_on_played)
	for bus in STEMS:
		var record := AudioEffectRecord.new()
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), record)
		record.set_recording_active(true)
		_records[bus] = record
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = (load(Hud.SCENE) as PackedScene).instantiate()
	layer.add_child(_hud)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.speed_base = 2.2
	tuning.rounds.first_spawn_delay = 0.5
	tuning.rounds.intro_seconds = 4.0
	tuning.economy.item(&"door_concession").price = 250
	tuning.economy.item(&"weapon_shotgun").price = 150
	_night = Night.new()
	_night.hud = _hud
	add_child(_night)
	_night.shoulder_camera = true
	await _night.start(Night.Mode.AUTOPILOT, Night.SEED, tuning)
	# The machine's mouse is never held or read: the bot drives the player.
	var player := _night.player()
	if player != null:
		player.local_input = false
		player.capture_mouse = false
	_night.ticked.connect(_on_tick)


func _process(_delta: float) -> void:
	_frames += 1


func _on_played(id: StringName, _position: Variant) -> void:
	var text := String(id)
	if SoldierVoiceCatalog.is_take(id):
		print("VOICE %.2f %s" % [_now(), id])
	elif text.begins_with("shot_") or text.begins_with("blast_"):
		print("GUN %.2f %s" % [_now(), id])


func _now() -> float:
	return _frames / MOVIE_FPS


func _on_tick() -> void:
	_ticks += 1
	if _done or not _night.running:
		return
	if not _told and _ticks / 60.0 >= float(_args.get("seconds", 70)):
		_told = true
		_tell_the_rest()


## Moments a short autopilot run does not reach: the events the server sends, where the rest of
## the client can take them (a boss's spawn and a grenade's throw carry what the view draws, so the
## soldier is told of those two directly).
func _tell_the_rest() -> void:
	_night.set_paused(true)
	var state := _night.state
	var voice := _night.get_node("SoldierVoice") as SoldierVoice
	var steps: Array[Callable] = [
		func() -> void: voice.say(&"boss_arrive", PLAYER),
		func() -> void: state.apply_events([{"type": &"fuel_low"}]),
		func() -> void: voice.say(&"grenade", PLAYER),
		func() -> void: state.apply_events([_hurt(20.0)]),
		func() -> void:
			state.apply_events(
				[{"type": &"player_downed", "player_id": PLAYER, "cause": &"blow", "bearing": 0.0}]
			),
		func() -> void: state.apply_events([{"type": &"player_revived", "player_id": PLAYER}]),
		func() -> void:
			(
				state
				. apply_events(
					[
						{
							"type": &"purchase_made",
							"player_id": PLAYER,
							"item_id": &"weapon_rifle",
							"price": 1200,
							"detail": {},
						}
					]
				)
			),
		func() -> void: state.apply_events([{"type": &"fuel_restored"}]),
		func() -> void: state.apply_events([_boss_killed()]),
	]
	for step in steps:
		step.call()
		for i in int(TOLD_GAP * MOVIE_FPS):
			await get_tree().process_frame
	_finish()


func _hurt(health: float) -> Dictionary:
	return {
		"type": &"player_hurt",
		"player_id": PLAYER,
		"damage": 30.0,
		"health": health,
		"max_health": 100.0,
		"bearing": 0.0,
		"source_id": 4,
	}


func _boss_killed() -> Dictionary:
	return {
		"type": &"zombie_removed",
		"zombie_id": 900,
		"zombie_type": &"headliner",
		"boss": true,
		"cause": &"killed",
		"killer_id": PLAYER,
		"zone": &"body",
		"melee": false,
	}


func _finish() -> void:
	_done = true
	for i in int(3.0 * MOVIE_FPS):
		await get_tree().process_frame
	var out := String(_args.get("out", ""))
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


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
