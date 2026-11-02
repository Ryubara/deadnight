extends GdUnitTestSuite
## The rules every firearm's shot follows (`docs/research/gun-audio.md`, issue 407): the
## shooter's own shots are close (flat, not run through a 3D voice from the muzzle), the pitch and
## level of a shot vary inside one narrow documented range, and no firearm falls below its
## documented loudness against the night's beds. The loudness is measured with ffmpeg on a
## recording of the game (`tools/audio/gun_levels.py` writes `gun_levels.json`); this test fails
## when a trim is changed without measuring again.

const OWN := 1
const OTHER := 2
const MUZZLE := Vector3(0.3, 1.45, -0.4)
const CAMERA_AT := Vector3(0.6, 1.6, 2.3)
const FIREARMS: Array[StringName] = [&"pistol", &"smg", &"rifle", &"shotgun", &"flare_gun"]
const TABLE := "res://tests/night/gun_levels.json"
## A shot is at least this many LU above the night's beds (integrated, measured alone): one shot's
## loudest 400 ms, and a two second burst as a whole.
const MIN_SHOT_ABOVE_BEDS_LU := 14.0
const MIN_BURST_ABOVE_BEDS_LU := 17.0
## No bus effect is relied on (the web build plays samples, which ignore them): the headroom is
## in the files and the trims, so a shot or a burst never gets closer to full scale than this.
const MAX_PEAK_DBFS := -1.0
## The whole pitch rule in semitones, and the level rule in dB (either way).
const PITCH_RANGE := 0.2
const LEVEL_RANGE := 0.6

var _heard: Array[Dictionary] = []
var _sounds: WeaponSounds
var _state: ClientState


func before_test() -> void:
	_heard = []
	_state = ClientState.new()
	_state.player_id = OWN
	_sounds = auto_free(WeaponSounds.new())
	_sounds.play = func(id: StringName, at: Variant, db: float) -> void:
		_heard.append({"id": id, "at": at, "db": db})
	add_child(_sounds)
	_sounds.setup(_state, 407)
	_state.apply_events(
		[
			{
				"type": &"frame",
				"players": {OWN: {"pos": Vector3.ZERO}, OTHER: {"pos": Vector3(9, 0, 9)}},
				"zombies": []
			}
		]
	)


func _shot(weapon: StringName, shooter: int) -> void:
	(
		_state
		. apply_events(
			[
				{
					"type": &"shot_fired",
					"shooter_id": shooter,
					"weapon_id": weapon,
					"muzzle": MUZZLE,
					"ends": [] as Array[Vector3],
				}
			]
		)
	)
	_sounds.schedule.advance(1.0)


func _firearm_voices() -> Array[StringName]:
	var ids: Array[StringName] = []
	for weapon: StringName in WeaponSounds.FIRE:
		for id: StringName in WeaponSounds.FIRE[weapon].values():
			ids.append(id)
	return ids


func test_the_shooters_own_shots_play_flat_and_a_strangers_play_from_the_muzzle() -> void:
	for weapon in FIREARMS:
		_heard.clear()
		_shot(weapon, OWN)
		assert_array(_heard).is_not_empty()
		for h in _heard:
			(
				assert_bool(h["at"] == null)
				. override_failure_message("own %s: %s played at %s" % [weapon, h["id"], h["at"]])
				. is_true()
			)
		_heard.clear()
		_shot(weapon, OTHER)
		for h in _heard:
			assert_vector(h["at"]).is_equal(MUZZLE)


func test_a_flat_shot_gets_no_distance_attenuation_and_no_pan() -> void:
	var audio := auto_free(AudioService.new()) as AudioService
	add_child(audio)
	audio.seed_random(407)
	for id in _firearm_voices():
		var def := SoundCatalog.get_def(id)
		var player := audio.play(id, null, 0.25) as AudioStreamPlayer
		assert_object(player).override_failure_message("%s did not play flat" % id).is_not_null()
		# Nothing but its trim and the play's own wobble: no distance term, no spatial voice.
		assert_float(player.volume_db).is_equal_approx(def.volume_db + 0.25, 0.001)
		audio.stop_all()
		audio.advance(5.0)


func test_a_strangers_shot_close_by_is_held_to_its_trim_not_boosted_past_it() -> void:
	# Another player's gun two to three metres away: the engine's inverse-distance boost is capped at
	# the trim (`near_cap_db`), so it is neither quieter nor hotter than the shooter's own.
	var audio := auto_free(AudioService.new()) as AudioService
	var listener := auto_free(Node3D.new()) as Node3D
	add_child(listener)
	listener.global_position = CAMERA_AT
	audio.listener = listener
	add_child(audio)
	for id in _firearm_voices():
		var def := SoundCatalog.get_def(id)
		var player := audio.play(id, MUZZLE) as AudioStreamPlayer3D
		assert_object(player).override_failure_message(String(id)).is_not_null()
		assert_float(player.max_db).is_equal_approx(player.volume_db, 0.001)
		assert_float(def.near_cap_db).is_equal(0.0)
		audio.stop_all()
		audio.advance(5.0)


func test_every_firearm_voice_shares_the_one_pitch_rule() -> void:
	for id in _firearm_voices():
		var def := SoundCatalog.get_def(id)
		(
			assert_float(def.pitch_semitones)
			. override_failure_message("%s pitch %s" % [id, def.pitch_semitones])
			. is_equal(ArmsCatalog.FIREARM_PITCH_SEMITONES)
		)
	assert_float(ArmsCatalog.FIREARM_PITCH_SEMITONES).is_less_equal(PITCH_RANGE)


func test_a_burst_of_every_firearm_stays_inside_the_pitch_and_level_rules() -> void:
	var audio := auto_free(AudioService.new()) as AudioService
	add_child(audio)
	audio.seed_random(407)
	var semitones_limit := ArmsCatalog.FIREARM_PITCH_SEMITONES + 0.001
	for weapon in FIREARMS:
		for i in 60:
			_heard.clear()
			_shot(weapon, OWN)
			for h in _heard:
				assert_float(absf(h["db"])).is_less_equal(WeaponSounds.LEVEL_JITTER_DB + 0.001)
				var player := audio.play(h["id"], null, h["db"]) as AudioStreamPlayer
				if player != null:
					var shift := absf(12.0 * log(player.pitch_scale) / log(2.0))
					(
						assert_float(shift)
						. override_failure_message("%s shifted %s semitones" % [h["id"], shift])
						. is_less_equal(semitones_limit)
					)
			audio.stop_all()
			audio.advance(5.0)
	assert_float(WeaponSounds.LEVEL_JITTER_DB * 2.0).is_less_equal(LEVEL_RANGE * 2.0)


func test_the_guns_stay_above_the_night_beds_by_the_documented_loudness() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	var bed: float = table["bed_lufs"]
	for weapon: String in table["guns"]:
		var gun: Dictionary = table["guns"][weapon]
		(
			assert_float(float(gun["single_momentary_lufs"]) - bed)
			. override_failure_message(
				(
					"%s: one shot is only %s LU over the beds"
					% [weapon, gun["single_momentary_lufs"] - bed]
				)
			)
			. is_greater_equal(MIN_SHOT_ABOVE_BEDS_LU)
		)
		(
			assert_float(float(gun["burst_lufs"]) - bed)
			. override_failure_message(
				"%s: a burst is only %s LU over the beds" % [weapon, gun["burst_lufs"] - bed]
			)
			. is_greater_equal(MIN_BURST_ABOVE_BEDS_LU)
		)
		assert_float(float(gun["peak_dbfs"])).override_failure_message(weapon).is_less_equal(
			MAX_PEAK_DBFS
		)


func test_the_measured_loudness_is_of_the_trims_the_catalog_has() -> void:
	# A trim moved without measuring again would leave the table above describing another game.
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	for weapon: String in table["guns"]:
		var trims: Dictionary = table["guns"][weapon]["trims_db"]
		assert_array(trims.keys()).is_not_empty()
		for id: String in trims:
			var def := SoundCatalog.get_def(StringName(id))
			assert_object(def).override_failure_message(id).is_not_null()
			(
				assert_float(def.volume_db)
				. override_failure_message(
					"%s trim is %s, measured at %s: measure again" % [id, def.volume_db, trims[id]]
				)
				. is_equal_approx(float(trims[id]), 0.001)
			)
	for weapon: StringName in FIREARMS:
		(
			assert_bool(table["guns"].has(String(weapon)))
			. override_failure_message("no measurement of %s" % weapon)
			. is_true()
		)
