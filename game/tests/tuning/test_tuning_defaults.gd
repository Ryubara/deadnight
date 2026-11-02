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
	assert_int(table.size()).is_equal(97)
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
		if not table.has(String(id)) and not String(id).begins_with(SoldierVoiceCatalog.PREFIX):
			extra.append(String(id))
	assert_array(Array(extra)).is_empty()


func test_the_soldiers_takes_play_at_the_mixs_voice_numbers() -> void:
	var mix := SoundCatalog.mix()
	var took := 0
	for event in SoldierVoiceCatalog.events():
		for n in range(1, SoldierVoiceCatalog.takes_of(event) + 1):
			var def := SoundCatalog.get_def(SoldierVoiceCatalog.take_id(event, n))
			assert_float(def.volume_db).is_equal(mix.voice_db)
			assert_float(def.max_distance).is_equal(mix.voice_max_distance)
			assert_float(def.unit_size).is_equal(mix.voice_unit_size)
			took += 1
	assert_int(took).is_greater(80)


func test_the_aim_assist_file_holds_the_old_constants() -> void:
	_check(load(AimAssistTuning.SHIPPED_PATH), DefaultValues.AIM_ASSIST_TUNING)


func test_the_shot_effects_file_holds_the_old_constants() -> void:
	_check(load(ShotFxTuning.SHIPPED_PATH), DefaultValues.SHOT_FX_TUNING)
