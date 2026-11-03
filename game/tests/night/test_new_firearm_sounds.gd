extends GdUnitTestSuite
## The second batch of firearms' sounds (#790, `tools/audio/gun_recipes_2.py`): each has a report
## and a late tail, an equip and a dry click of its own, and the steps of a reload that match its
## mechanism; each sounds like its kind (the .50 calibre's report is the longest and the PPSh's
## among the shortest); and every sound the bank has is used by something. The levels of the
## shots are `test_gun_audio_rules.gd`'s.

const OWN := 1
const MUZZLE := Vector3(0.0, 1.5, 0.0)
const NEW_GUNS: Array[StringName] = [
	&"ppsh", &"m249", &"m4a1", &"fifty_cal", &"mp5", &"pump_870", &"dual_pistols"
]
const BANK := "res://core/audio/banks/firearms_2.tres"
## The step a gun's reload must have for its mechanism: its own sound, not another gun's.
const SIGNATURE_STEP := {
	&"ppsh": [&"drum_out", &"drum_in"],
	&"m249": [&"cover_open", &"belt_in", &"cover_shut"],
	&"m4a1": [&"mag_out", &"mag_in"],
	&"fifty_cal": [&"mag_out", &"mag_in", &"bolt"],
	&"mp5": [&"mag_out", &"mag_in", &"bolt"],
	&"pump_870": [&"shell_in", &"pump"],
	&"dual_pistols": [&"mag_out", &"mag_in", &"slide"],
}

var _heard: Array[Dictionary] = []
var _sounds: WeaponSounds
var _state: ClientState


func before_test() -> void:
	_heard = []
	_state = ClientState.new()
	_state.player_id = OWN
	_sounds = auto_free(WeaponSounds.new())
	_sounds.play = func(id: StringName, at: Variant, db: float) -> void:
		_heard.append({"id": id, "at": at, "db": db, "t": _sounds.schedule.now()})
	add_child(_sounds)
	_sounds.setup(_state, 790)
	_state.apply_events(
		[{"type": &"frame", "players": {OWN: {"pos": Vector3(1, 0, 2)}}, "zombies": []}]
	)


func _ids() -> Array:
	return _heard.map(func(h: Dictionary) -> StringName: return h["id"])


func _length(id: StringName) -> float:
	var total := 0.0
	var def := SoundCatalog.get_def(id)
	for variant in range(1, def.variants + 1):
		total += (load(def.path_for(variant)) as AudioStream).get_length()
	return total / def.variants


func test_every_new_gun_is_a_report_and_a_late_tail() -> void:
	for weapon in NEW_GUNS:
		_heard.clear()
		var start := _sounds.schedule.now()
		(
			_state
			. apply_events(
				[
					{
						"type": &"shot_fired",
						"shooter_id": OWN,
						"weapon_id": weapon,
						"muzzle": MUZZLE,
						"ends": [] as Array[Vector3],
					}
				]
			)
		)
		assert_array(_ids()).is_equal([StringName("shot_%s" % weapon)])
		_sounds.schedule.advance(0.2)
		assert_array(_ids()).contains([StringName("tail_%s" % weapon)])
		var tuning := NightSoundTuning.current()
		assert_float(_heard[-1]["t"] - start).is_between(
			tuning.tail_delay, tuning.tail_delay + tuning.tail_spread + 0.001
		)


func test_each_gun_comes_up_and_clicks_dry_with_its_own_sound() -> void:
	for weapon in NEW_GUNS:
		_heard.clear()
		_state.apply_events(
			[
				{
					"type": &"weapon_equipped",
					"player_id": OWN,
					"weapon_id": weapon,
					"ammo": 1,
					"reserve": 1
				}
			]
		)
		assert_array(_ids()).is_equal([StringName("equip_%s" % weapon)])
		_heard.clear()
		(
			_state
			. apply_events(
				[
					{
						"type": &"frame",
						"players": {OWN: {"pos": Vector3(1, 0, 2), "weapon": weapon}},
						"zombies": []
					},
					{"type": &"fire_rejected", "shooter_id": OWN, "seq": 1, "reason": &"empty"},
				]
			)
		)
		assert_array(_ids()).is_equal([StringName("dry_%s" % weapon)])


func test_a_weapon_without_sounds_of_its_own_rustles_and_clicks_the_common_way() -> void:
	(
		_state
		. apply_events(
			[
				{
					"type": &"weapon_equipped",
					"player_id": OWN,
					"weapon_id": &"pistol",
					"ammo": 1,
					"reserve": 1
				},
				{
					"type": &"frame",
					"players": {OWN: {"pos": Vector3(1, 0, 2), "weapon": &"pistol"}},
					"zombies": []
				},
				{"type": &"fire_rejected", "shooter_id": OWN, "seq": 1, "reason": &"empty"},
			]
		)
	)
	assert_array(_ids()).is_equal([&"weapon_swap", &"dry_fire"])


func test_every_reload_reaches_for_the_pouch_and_has_the_steps_of_its_mechanism() -> void:
	var owner_of := {}
	for weapon in NEW_GUNS:
		var steps: Dictionary = WeaponSounds.RELOAD[weapon]
		assert_bool(steps.has(&"pouch")).override_failure_message(String(weapon)).is_true()
		for step: StringName in SIGNATURE_STEP[weapon]:
			(
				assert_bool(steps.has(step))
				. override_failure_message("%s: %s" % [weapon, step])
				. is_true()
			)
		# Its own steps are its own: none is another gun's sound, but the pouch.
		for step: StringName in steps:
			if step != &"pouch":
				(
					assert_bool(owner_of.has(steps[step]))
					. override_failure_message(
						"%s is also %s's" % [steps[step], owner_of.get(steps[step])]
					)
					. is_false()
				)
				owner_of[steps[step]] = weapon


func test_every_sound_of_the_bank_is_played_by_something_and_has_its_files() -> void:
	var used := {}
	for weapon: StringName in NEW_GUNS:
		for id: StringName in WeaponSounds.FIRE[weapon].values():
			used[id] = true
		for id: StringName in WeaponSounds.RELOAD[weapon].values():
			used[id] = true
		used[WeaponSounds.EQUIP[weapon]] = true
		used[WeaponSounds.DRY[weapon]] = true
	var bank := load(BANK) as SoundBank
	var unused := PackedStringArray()
	for def in bank.sounds:
		if not used.has(def.id):
			unused.append(String(def.id))
		for variant in range(1, def.variants + 1):
			(
				assert_bool(ResourceLoader.exists(def.path_for(variant)))
				. override_failure_message(def.path_for(variant))
				. is_true()
			)
	assert_array(Array(unused)).is_empty()
	for id: StringName in used:
		if id != &"reload_pouch":
			(
				assert_bool(bank.sounds.any(func(d: SoundDef) -> bool: return d.id == id))
				. override_failure_message("%s is not in the bank" % id)
				. is_true()
			)


func test_each_gun_sounds_like_its_kind() -> void:
	# The .50 calibre is the longest report and the longest tail; the fast light SMGs (the PPSh, the
	# MP5) are shorter than the rifles and the shotguns.
	var fifty := _length(&"shot_fifty_cal")
	for weapon in NEW_GUNS:
		if weapon != &"fifty_cal":
			assert_float(fifty).override_failure_message("fifty vs %s" % weapon).is_greater(
				_length(StringName("shot_%s" % weapon))
			)
			assert_float(_length(&"tail_fifty_cal")).is_greater(
				_length(StringName("tail_%s" % weapon))
			)
	for light: StringName in [&"shot_ppsh", &"shot_mp5"]:
		for heavy: StringName in [&"shot_m249", &"shot_pump_870", &"shot_rifle", &"shot_shotgun"]:
			(
				assert_float(_length(light))
				. override_failure_message("%s vs %s" % [light, heavy])
				. is_less(_length(heavy))
			)
	# The heaviest steps are the long ones: the .50's bolt, the pump's stroke and the SAW's belt.
	assert_float(_length(&"reload_fifty_bolt")).is_greater(_length(&"reload_m4a1_bolt") * 3.0)
	assert_float(_length(&"reload_pump_stroke")).is_greater(_length(&"reload_pump_shell") * 3.0)
	assert_float(_length(&"reload_m249_belt")).is_greater(_length(&"reload_m249_charge"))


func test_the_automatic_guns_tails_are_spaced_not_stacked() -> void:
	# Fast guns share the tommy gun's tail cooldown, so a burst does not stack its rooms.
	for weapon: StringName in [&"ppsh", &"mp5", &"m4a1", &"m249"]:
		assert_float(SoundCatalog.get_def(StringName("tail_%s" % weapon)).cooldown).is_equal(
			SoundCatalog.get_def(&"tail_smg").cooldown
		)
