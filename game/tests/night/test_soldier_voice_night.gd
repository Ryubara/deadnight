extends GdUnitTestSuite
## The soldier's voice in a real night: the night makes it, and what the server tells it comes out
## of the audio service as a take of the Voice bus (flat for the player at this screen).

const OWN := Night.PLAYER_ID

var _heard: Array[Dictionary] = []
var _ears: Node3D


func before_test() -> void:
	Audio.stop_all()
	Audio.seed_random(11)
	_heard = []
	Audio.played.connect(_on_played)
	_ears = auto_free(Node3D.new())
	add_child(_ears)
	Audio.listener = _ears


func after_test() -> void:
	Audio.played.disconnect(_on_played)
	Audio.listener = null
	Audio.stop_all()


func _on_played(id: StringName, position: Variant) -> void:
	_heard.append({"id": id, "at": position})


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	return night


func _ids() -> Array:
	return _heard.map(func(h: Dictionary) -> String: return String(h["id"]))


func test_the_night_has_a_soldier_voice() -> void:
	var night := await _start()
	assert_object(night.get_node_or_null("SoldierVoice")).is_instanceof(SoldierVoice)


func test_going_down_plays_a_downed_take_flat_through_the_service() -> void:
	var night := await _start()
	night.state.apply_events(
		[{"type": &"player_downed", "player_id": OWN, "cause": &"blow", "bearing": 0.0}]
	)
	var downed := _heard.filter(
		func(h: Dictionary) -> bool: return String(h["id"]).begins_with("vox_downed_")
	)
	assert_int(downed.size()).is_equal(1)
	assert_object(downed[0]["at"]).is_null()
	assert_int(Audio.active_voices()).is_greater(0)


func test_a_blow_grunts_and_the_old_synthesised_voice_is_gone() -> void:
	var night := await _start()
	for i in 10:
		(
			night
			. state
			. apply_events(
				[
					{
						"type": &"player_hurt",
						"player_id": OWN,
						"damage": 10.0,
						"health": 90.0,
						"max_health": 100.0,
						"bearing": 0.0,
						"source_id": 4,
					}
				]
			)
		)
	var ids := _ids()
	assert_array(ids).not_contains(["player_hurt", "player_downed"])
	assert_bool(ids.any(func(id: String) -> bool: return id.begins_with("vox_hurt_"))).is_true()
	assert_object(SoundCatalog.get_def(&"player_hurt")).is_null()
