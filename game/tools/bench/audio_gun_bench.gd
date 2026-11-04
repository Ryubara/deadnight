extends Node
## The guns as the player hears them, for measurement: each firearm fires one shot and then a two
## second burst at its own rate of fire through the night's own `WeaponSounds` and the audio
## service, with the listener where the shoulder camera sits behind the shooter. Then the night's
## ambient beds run alone, so the guns can be read against them. Run with Movie Maker
## (`--write-movie out.avi --fixed-fps 60 --resolution 160x90`, then `ffmpeg -i out.avi -vn -c:a
## pcm_s32le out.wav`: an `out.png` movie writes a file for each frame and ran at half the speed;
## time is the sum of the frames' deltas, so a browser run works too). Prints
## `SLOT <weapon> <single start> <burst start> <burst end>` for each weapon (seconds into the
## movie), `SHOT <seconds> <weapon> <sound> <pitch> <volume_db> <flat|3d> <distance>` for each
## sound a shot started, `TRIM <weapon> <sound> <volume_db>` for the catalog's trim of each voice
## and `BED <start> <end>`. Arguments after `--`: `other` to hear the shots as another player's
## (the shooter is not this screen's player), `weapons=smg,pistol` for some of the guns only.

const SLOT_SECONDS := 7.0
const SINGLE_AT := 0.5
const BURST_AT := 2.5
const BURST_SECONDS := 2.0
const BED_SECONDS := 12.0
## Where the shoulder camera is, and the server's muzzle, relative to the shooter's feet and
## facing (`PlayerTuning`: shoulder 0.6, arm 2.3, pivot 1.6; `NightTuning.muzzle_offset`).
const CAMERA_AT := Vector3(0.6, 1.6, 2.3)
const MUZZLE := Vector3(0.3, 1.45, -0.4)
const OWN := 1
const OTHER := 2
## Seconds between the shots of the guns the catalogue does not have yet (#790 before #793): the
## intervals of #785's table (`docs/design/weapons.md`, the nine new weapons); a weapon with a
## definition fires at its own `fire_interval`.
const PROVISIONAL_INTERVAL := {
	&"ppsh": 0.055,
	&"m249": 0.09,
	&"m4a1": 0.11,
	&"fifty_cal": 0.9,
	&"mp5": 0.1,
	&"pump_870": 0.65,
	&"dual_pistols": 0.15,
}

var _weapons: Array[StringName] = [
	&"pistol",
	&"smg",
	&"rifle",
	&"shotgun",
	&"flare_gun",
	&"ppsh",
	&"m249",
	&"m4a1",
	&"fifty_cal",
	&"mp5",
	&"pump_870",
	&"dual_pistols",
	&"house_pistol",
]
var _state := ClientState.new()
var _sounds: WeaponSounds
var _now := 0.0
var _shooter := OWN
var _weapon_index := 0
var _next_shot := -1.0
var _single_done := false
var _stage := &"slots"
var _bed_started := false
var _listener: Camera3D
var _bed_end := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().size = Vector2i(160, 90)
	Audio.seed_random(407)
	for argument in OS.get_cmdline_user_args():
		if argument == "other":
			_shooter = OTHER
		elif argument.begins_with("weapons="):
			_weapons.clear()
			for weapon in argument.trim_prefix("weapons=").split(","):
				_weapons.append(StringName(weapon))
	_listener = Camera3D.new()
	add_child(_listener)
	_listener.make_current()
	_listener.position = CAMERA_AT
	Audio.listener = _listener
	_state.player_id = OWN
	_sounds = WeaponSounds.new()
	_sounds.play = _play
	add_child(_sounds)
	_sounds.setup(_state, 407)
	for weapon in _weapons:
		for id: StringName in WeaponSounds.FIRE[weapon].values():
			print("TRIM %s %s %.2f" % [weapon, id, SoundCatalog.get_def(id).volume_db])
	_state.apply_events(
		[
			{
				"type": &"frame",
				"players": {OWN: {"pos": Vector3.ZERO}, OTHER: {"pos": Vector3(0, 0, 0)}},
				"zombies": []
			}
		]
	)


func _process(delta: float) -> void:
	var now := _now
	_now += delta
	if _stage == &"slots":
		_step_slots(now)
	elif _stage == &"bed":
		_step_bed(now)
	elif now > _bed_end + 1.0:
		Audio.stop_all()
		get_tree().quit()


func _step_slots(now: float) -> void:
	if _weapon_index >= _weapons.size():
		_stage = &"bed"
		return
	var weapon := _weapons[_weapon_index]
	var start := _weapon_index * SLOT_SECONDS
	var local := now - start
	var interval := interval_of(weapon)
	if not _single_done and local >= SINGLE_AT:
		_single_done = true
		print(
			(
				"SLOT %s %.3f %.3f %.3f"
				% [weapon, start + SINGLE_AT, start + BURST_AT, start + BURST_AT + BURST_SECONDS]
			)
		)
		_fire(weapon)
	if local >= BURST_AT and local < BURST_AT + BURST_SECONDS:
		if _next_shot < 0.0:
			_next_shot = BURST_AT
		while _next_shot <= local:
			_fire(weapon)
			_next_shot += interval
	if local >= SLOT_SECONDS:
		_weapon_index += 1
		_next_shot = -1.0
		_single_done = false


## How long the weapon waits between shots: its definition's, or the provisional one.
static func interval_of(weapon: StringName) -> float:
	if (
		PROVISIONAL_INTERVAL.has(weapon)
		and not ResourceLoader.exists("%s%s.tres" % [WeaponCatalog.DIR, weapon])
	):
		return PROVISIONAL_INTERVAL[weapon]
	return WeaponCatalog.get_def(weapon).fire_interval


func _step_bed(now: float) -> void:
	if not _bed_started:
		_bed_started = true
		_bed_end = now + BED_SECONDS
		print("BED %.3f %.3f" % [now, _bed_end])
		for id in NightSounds.NIGHT_BEDS:
			Audio.start_bed(id)
	if now >= _bed_end:
		_stage = &"end"


func _fire(weapon: StringName) -> void:
	(
		_state
		. apply_events(
			[
				{
					"type": &"shot_fired",
					"shooter_id": _shooter,
					"weapon_id": weapon,
					"muzzle": MUZZLE,
					"ends": [],
				}
			]
		)
	)


func _play(id: StringName, at: Variant, extra_db: float) -> void:
	var player: Node = Audio.play(id, at, extra_db)
	if player == null:
		print("SHOT %.3f %s %s dropped" % [_now, _slot_weapon(), id])
		return
	var kind := "flat" if at == null else "3d"
	var distance := 0.0 if at == null else _listener.global_position.distance_to(at)
	var level := 0.0
	if player is AudioStreamPlayer3D:
		level = (player as AudioStreamPlayer3D).max_db
	print(
		(
			"SHOT %.3f %s %s %.4f %.2f %s %.2f max_db=%.1f"
			% [
				_now,
				_slot_weapon(),
				id,
				player.pitch_scale,
				player.volume_db,
				kind,
				distance,
				level
			]
		)
	)


func _slot_weapon() -> StringName:
	return _weapons[mini(_weapon_index, _weapons.size() - 1)]
