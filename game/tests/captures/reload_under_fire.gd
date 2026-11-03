extends Node
## Whether a reload is heard under fire (#683): the sounds of a reload and of a gun firing without a
## break, played as a client plays them (`WeaponSounds`, through the audio service and its buses),
## heard from the shoulder camera. Not part of the game. Two scenes:
## - `own`: the player reloads `--weapon` while a teammate 3 m ahead fires `--gun`;
## - `mate`: a teammate 4 m ahead reloads `--weapon` while the player fires `--gun` (the own gun
##   plays flat and full, the hardest case);
## - `team`: a teammate 4 m ahead reloads while another, 6 m off to the left, fires `--gun`.
## `--part=fire` plays only the gunfire, `--part=reload` only the reload, `--part=both` both; the
## buses have no effects, so the mix is the sum and the two parts are measured apart on the same
## timeline (`tools/audio/reload_audibility.py`). Run with Movie Maker at a fixed rate, the sound in
## the movie's .wav:
## `gds godot -- --path game res://tests/captures/reload_under_fire.tscn --write-movie <abs>/m.png
##  --fixed-fps 30 --resolution 160x90 -- --scene=own --weapon=rifle --gun=smg --part=reload`.
## Prints `STEP <seconds> <sound>` for every reload step.

const OWN := 1
const MATE := 2
const OTHER := 3
const MOVIE_FPS := 30.0
## The shoulder camera from the player's feet: `PlayerTuning.shoulder_offset`, `pivot_height`,
## `arm_length`.
const LISTENER := Vector3(0.6, 1.6, 2.3)
const MATE_AT := {
	"own": Vector3(1.0, 0.0, -2.8), "mate": Vector3(1.4, 0.0, -3.8), "team": Vector3(1.4, 0.0, -3.8)
}
const OTHER_AT := Vector3(-4.0, 0.0, -4.5)
const MUZZLE_LIFT := Vector3(0.0, 1.4, -0.4)
## When the reload starts, and how long the gunfire runs after it ends.
const RELOAD_AT := 1.0
const AFTER := 0.6

var _scene := "own"
var _weapon := &"rifle"
var _gun := &"smg"
var _part := "both"
var _fire_state: ClientState
var _reload_state: ClientState
var _fire_sounds: WeaponSounds
var _reload_sounds: WeaponSounds
var _start := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			_scene = argument.trim_prefix("--scene=")
		elif argument.begins_with("--weapon="):
			_weapon = StringName(argument.trim_prefix("--weapon="))
		elif argument.begins_with("--gun="):
			_gun = StringName(argument.trim_prefix("--gun="))
		elif argument.begins_with("--part="):
			_part = argument.trim_prefix("--part=")
	Audio.seed_random(5)
	var listener := Camera3D.new()
	add_child(listener)
	listener.position = LISTENER
	listener.make_current()
	Audio.listener = listener
	var mate_at: Vector3 = MATE_AT[_scene]
	var frame := {
		"type": &"frame",
		"players": {OWN: {"pos": Vector3.ZERO}, MATE: {"pos": mate_at}, OTHER: {"pos": OTHER_AT}},
		"zombies": [],
	}
	# Two clients' worth of sound, each with its own random numbers, so the fire sounds the same
	# whether the reload plays beside it or not.
	_fire_state = ClientState.new()
	_fire_state.player_id = OWN
	_fire_sounds = WeaponSounds.new()
	add_child(_fire_sounds)
	_fire_sounds.setup(_fire_state, 11)
	_fire_state.apply_events([frame])
	_reload_state = ClientState.new()
	_reload_state.player_id = OWN
	_reload_sounds = WeaponSounds.new()
	add_child(_reload_sounds)
	_reload_sounds.setup(_reload_state, 23)
	_reload_state.apply_events([frame])
	_reload_sounds.play = func(id: StringName, at: Variant, extra_db: float) -> void:
		print("STEP %.3f %s" % [_now(), id])
		Audio.play(id, at, extra_db)
	_start = Engine.get_frames_drawn()
	var shooter: int = {"own": MATE, "mate": OWN, "team": OTHER}[_scene]
	var reloader := OWN if _scene == "own" else MATE
	var shooter_at: Vector3 = {OWN: Vector3.ZERO, MATE: mate_at, OTHER: OTHER_AT}[shooter]
	var muzzle := shooter_at + MUZZLE_LIFT
	var reload_seconds: float = WeaponCatalog.get_def(_weapon).reload_time
	var gun_interval: float = WeaponCatalog.get_def(_gun).fire_interval
	var end := RELOAD_AT + reload_seconds + AFTER
	var next_shot := 0.0
	var reloaded := false
	print("SCENE %s weapon %s gun %s part %s" % [_scene, _weapon, _gun, _part])
	while _now() < end:
		if _now() >= next_shot:
			if _part != "reload":
				(
					_fire_state
					. apply_events(
						[
							{
								"type": &"shot_fired",
								"shooter_id": shooter,
								"weapon_id": _gun,
								"muzzle": muzzle,
								"ends": [],
							}
						]
					)
				)
			next_shot += gun_interval
		if not reloaded and _now() >= RELOAD_AT:
			reloaded = true
			print("RELOAD %.3f %.3f" % [_now(), reload_seconds])
			if _part != "fire":
				(
					_reload_state
					. apply_events(
						[
							{
								"type": &"reload_started",
								"shooter_id": reloader,
								"weapon_id": _weapon,
								"seconds": reload_seconds,
							}
						]
					)
				)
		await get_tree().process_frame
	print("END %.3f" % _now())
	get_tree().quit()


func _now() -> float:
	return (Engine.get_frames_drawn() - _start) / MOVIE_FPS
