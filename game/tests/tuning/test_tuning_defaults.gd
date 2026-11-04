extends GdUnitTestSuite
## Each tuning resource is a `.tres` you edit, and the values it ships with are the numbers the game
## had as constants before (`DefaultValues`). A failure names the property: retune on purpose, then
## change the number in `default_values.gd` too.


func _check(resource: Resource, table: Dictionary) -> void:
	assert_object(resource).is_not_null()
	assert_array(Array(DefaultValues.differences(resource, table))).is_empty()


func test_the_zombie_tuning_file_holds_the_old_constants() -> void:
	_check(load(ZombieTuning.SHIPPED_PATH), DefaultValues.ZOMBIE_TUNING)


func test_the_sound_mix_file_holds_the_old_constants() -> void:
	_check(load(SoundMix.SHIPPED_PATH), DefaultValues.SOUND_MIX)


func test_every_sound_has_the_values_it_had_in_code() -> void:
	var table := DefaultValues.sounds()
	assert_int(table.size()).is_equal(220)
	var wrong := PackedStringArray()
	for id: String in table:
		var def := SoundCatalog.get_def(StringName(id))
		if def == null:
			wrong.append("%s: no such sound" % id)
			continue
		for line in DefaultValues.differences(def, table[id]):
			wrong.append("%s %s" % [id, line])
	assert_array(Array(wrong)).is_empty()


func test_no_sound_is_in_the_catalog_but_not_the_table() -> void:
	var table := DefaultValues.sounds()
	var extra := PackedStringArray()
	for id: StringName in SoundCatalog.ids():
		if not table.has(String(id)) and not SoldierVoiceCatalog.is_take(id):
			extra.append(String(id))
	assert_array(Array(extra)).is_empty()


func test_the_soldiers_takes_play_at_the_mixs_voice_numbers() -> void:
	var mix := SoundCatalog.mix()
	var took := 0
	for voice in SoldierVoiceCatalog.voices():
		for event in SoldierVoiceCatalog.events():
			for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
				var def := SoundCatalog.get_def(SoldierVoiceCatalog.take_id(event, n, voice))
				assert_float(def.volume_db).is_equal(mix.voice_db)
				assert_float(def.max_distance).is_equal(mix.voice_max_distance)
				assert_float(def.unit_size).is_equal(mix.voice_unit_size)
				took += 1
	# Both voices: the male soldier's 115 takes and the female soldier's 115.
	assert_int(took).is_equal(230)


func test_the_aim_assist_file_holds_the_old_constants() -> void:
	_check(load(AimAssistTuning.SHIPPED_PATH), DefaultValues.AIM_ASSIST_TUNING)


func test_the_night_sound_file_holds_the_old_constants() -> void:
	_check(load(NightSoundTuning.SHIPPED_PATH), DefaultValues.NIGHT_SOUND_TUNING)


func test_the_light_file_holds_the_old_constants() -> void:
	_check(load(LightTuning.SHIPPED_PATH), DefaultValues.LIGHT_TUNING)


func test_the_soldiers_moments_hold_the_old_table() -> void:
	var table := SoldierVoiceCatalog.moments()
	assert_int(table.size()).is_equal(DefaultValues.SOLDIER_MOMENTS.size())
	var wrong := PackedStringArray()
	for row: Array in DefaultValues.SOLDIER_MOMENTS:
		var info: Dictionary = table.get(row[0], {})
		var now := [
			row[0],
			info.get("takes"),
			info.get("priority"),
			info.get("cooldown"),
			info.get("chance")
		]
		if now != row:
			wrong.append("%s: shipped %s, file %s" % [row[0], row, now])
	assert_array(Array(wrong)).is_empty()
	assert_array(table.keys()).is_equal(
		DefaultValues.SOLDIER_MOMENTS.map(func(r: Array) -> Variant: return r[0])
	)


func test_the_hud_file_holds_the_old_constants() -> void:
	_check(load(HudTuning.SHIPPED_PATH), DefaultValues.HUD_TUNING)


func test_the_touch_file_holds_the_old_constants() -> void:
	_check(load(TouchTuning.SHIPPED_PATH), DefaultValues.TOUCH_TUNING)


func test_the_shot_effects_file_holds_the_old_constants() -> void:
	_check(load(ShotFxTuning.SHIPPED_PATH), DefaultValues.SHOT_FX_TUNING)
