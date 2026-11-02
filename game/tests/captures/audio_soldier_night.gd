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
	_night.ticked.connect(_on_tick)


func _process(_delta: float) -> void:
	_frames += 1


func _on_played(id: StringName, _position: Variant) -> void:
	var text := String(id)
	if text.begins_with("vox_"):
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


## Moments a short autopilot run does not reach, as the events the server sends.
func _tell_the_rest() -> void:
	_night.set_paused(true)
	var state := _night.state
	var steps: Array[Dictionary] = [
		{
			"type": &"zombie_spawn_requested",
			"zombie_id": 900,
			"zombie_type": &"headliner",
			"boss": true
		},
		{"type": &"fuel_low"},
		{
			"type": &"grenade_thrown",
			"grenade_id": 1,
			"thrower_id": PLAYER,
			"position": state.position()
		},
		{
			"type": &"player_hurt",
			"player_id": PLAYER,
			"damage": 30.0,
			"health": 20.0,
			"max_health": 100.0,
			"bearing": 0.0,
			"source_id": 4
		},
		{"type": &"player_downed", "player_id": PLAYER, "cause": &"blow", "bearing": 0.0},
		{"type": &"player_revived", "player_id": PLAYER},
		{
			"type": &"purchase_made",
			"player_id": PLAYER,
			"item_id": &"weapon_rifle",
			"price": 1200,
			"detail": {}
		},
		{"type": &"fuel_restored"},
		{
			"type": &"zombie_removed",
			"zombie_id": 900,
			"zombie_type": &"headliner",
			"boss": true,
			"cause": &"killed",
			"killer_id": PLAYER,
			"zone": &"body",
			"melee": false
		},
	]
	for step in steps:
		state.apply_events([step])
		for i in int(TOLD_GAP * MOVIE_FPS):
			await get_tree().process_frame
	_finish()


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
