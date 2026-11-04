# The second map's sound (issue #657, docs/research/maps/small-map-audio.md), driven like a client:
# the listener moves, events come in, sounds go out. The room tone and the wind under the roof
# follow the room, and each piece (a window's boards, the plank door, the debris blocker, feet on
# wood) plays where and when it should. The yard is `test_smallmap_yard.gd`.
extends GdUnitTestSuite

const GREYBOX := preload("res://world/smallmap/smallmap_greybox.tscn")
const BACKDROP := preload("res://world/smallmap/backdrop.tscn")
const SETTLE_FRAMES := 4
## Inside the start room, facing the first window across the hall.
const START_EAR := Vector3(8.0, 1.6, 10.0)
const WINDOW_1 := Vector3(8.0, 1.55, 14.65)
## South of that window, straight out of it, and due north through the walls.
const OUT_SOUTH := Vector3(8.0, 1.6, 40.0)
const OUT_NORTH := Vector3(8.0, 1.6, -30.0)
const FAR_AWAY := Vector3(900.0, 1.6, 900.0)
const OUTSIDE := Vector3(30.0, 1.6, 30.0)

var _heard: Array[Dictionary] = []
var _ears: Node3D
var _greybox: Node3D
var _backdrop: Node3D
var _state: ClientState
var _sounds: SmallMapSounds


func before_test() -> void:
	Audio.stop_all()
	Audio.seed_random(11)
	_heard = []
	_backdrop = null
	Audio.played.connect(_on_played)
	_ears = auto_free(Node3D.new())
	add_child(_ears)
	_ears.global_position = START_EAR
	Audio.listener = _ears


func after_test() -> void:
	Audio.played.disconnect(_on_played)
	Audio.listener = null
	Audio.stop_all()


func _on_played(id: StringName, position: Variant) -> void:
	_heard.append({"id": id, "at": position})


## The map and its backdrop built, the physics settled, the sounds set up.
func _start(with_backdrop := true) -> void:
	_greybox = auto_free(GREYBOX.instantiate())
	add_child(_greybox)
	if with_backdrop:
		_backdrop = auto_free(BACKDROP.instantiate())
		add_child(_backdrop)
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	_state = ClientState.new()
	_sounds = auto_free(SmallMapSounds.new())
	add_child(_sounds)
	_sounds.setup(_state, _greybox, _backdrop)
	_run(0.2)


## Lets the sounds' own plays be heard here (with the level they were asked at) and not started.
func _listen() -> void:
	_sounds.play = func(id: StringName, at: Variant, db: float) -> void:
		_heard.append({"id": id, "at": at, "db": db})


func _tell(event: Dictionary) -> void:
	_state.apply_events([event])


func _ids() -> Array:
	return _heard.map(func(h: Dictionary) -> StringName: return h["id"])


func _last(id: StringName) -> Dictionary:
	for i in range(_heard.size() - 1, -1, -1):
		if _heard[i]["id"] == id:
			return _heard[i]
	return {}


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(left, 0.1)
		_sounds.advance(step)
		Audio.advance(step)
		left -= step


func _stand(at: Vector3) -> void:
	_ears.global_position = at
	_run(0.2)


# --- The sounds are in the game ---


func test_every_new_sound_is_in_the_catalog_with_its_files() -> void:
	var looping: Array[StringName] = [
		&"bed_room_tone", &"bed_roof_wind", &"yard_wind", &"yard_fire", &"yard_wire", &"yard_road"
	]
	for id in looping:
		var def := SoundCatalog.get_def(id)
		assert_object(def).override_failure_message(id).is_not_null()
		assert_bool(def.loop).override_failure_message(id).is_true()
		assert_str(def.bus).override_failure_message(id).is_equal("Ambience")
		assert_bool(ResourceLoader.exists(def.path_for(1))).override_failure_message(id).is_true()
	for id: StringName in [&"yard_rattle", &"debris_clear", &"step_wood", &"step_own_wood"]:
		var def := SoundCatalog.get_def(id)
		assert_object(def).override_failure_message(id).is_not_null()
		assert_bool(def.loop).is_false()
		for variant in def.variants:
			assert_bool(ResourceLoader.exists(def.path_for(variant + 1))).is_true()
	assert_str(SoundCatalog.get_def(&"yard_rattle").bus).is_equal("Ambience")
	assert_str(SoundCatalog.get_def(&"debris_clear").bus).is_equal("Effects")
	assert_int(SoundCatalog.get_def(&"step_wood").variants).is_equal(8)
	assert_int(SoundCatalog.get_def(&"step_own_wood").variants).is_equal(8)


func test_the_debris_blockers_play_no_padlock_on_purchase() -> void:
	assert_array(SmallMapSounds.ITEM_SOUNDS.keys()).contains_exactly_in_any_order(
		SmallMapSounds.DEBRIS_DOORS
	)
	for id: StringName in SmallMapSounds.DEBRIS_DOORS:
		assert_array(SmallMapSounds.ITEM_SOUNDS[id]).is_empty()


# --- The rooms ---


func test_a_point_is_in_the_room_whose_rectangle_and_floor_hold_it() -> void:
	await _start(false)
	var cases := {
		Vector3(8.0, 1.6, 7.0): &"Start",
		Vector3(0.0, 1.6, -4.0): &"Side",
		Vector3(8.0, 5.0, 2.0): &"UpperA",
		Vector3(-3.0, 5.0, -4.0): &"UpperB",
		OUTSIDE: &"",
		Vector3(-12.0, 1.6, 0.0): &"",
	}
	for point: Vector3 in cases:
		assert_str(_sounds.rooms.room_at(point)).override_failure_message(str(point)).is_equal(
			cases[point]
		)


func test_a_stair_is_part_of_the_room_below_until_its_top() -> void:
	await _start(false)
	assert_str(_sounds.rooms.room_at(Vector3(5.0, 2.9, 1.0))).is_equal("Start")
	assert_str(_sounds.rooms.room_at(Vector3(9.0, 4.3, 1.0))).is_equal("UpperA")


# --- Room tone and the wind under the roof ---


func test_the_room_tone_follows_the_room_the_listener_is_in() -> void:
	await _start(false)
	var t := SmallMapSoundTuning.current()
	assert_bool(Audio.is_bed_running(&"bed_room_tone")).is_true()
	_stand(Vector3(8.0, 1.6, 7.0))
	_run(4.0)
	assert_str(_sounds.room).is_equal("Start")
	assert_float(Audio.bed_fade_db(&"bed_room_tone")).is_equal_approx(t.tone_db[&"Start"], 0.01)
	assert_bool(Audio.is_bed_running(&"bed_roof_wind")).is_false()
	_stand(Vector3(-3.0, 5.0, -4.0))
	_run(4.0)
	assert_str(_sounds.room).is_equal("UpperB")
	assert_float(Audio.bed_fade_db(&"bed_room_tone")).is_equal_approx(t.tone_db[&"UpperB"], 0.01)
	# Heard at the loop's level before the gusts drove it (-19 dB) less the room's: the loop's trim is
	# `ROOF_HEADROOM_DB` higher and the bed rests that much lower (`test_smallmap_gusts.gd`).
	var trim := SoundCatalog.get_def(&"bed_roof_wind").volume_db
	assert_float(trim + Audio.bed_fade_db(&"bed_roof_wind")).is_equal_approx(
		-19.0 + t.roof_db[&"UpperB"], 0.01
	)
	_stand(Vector3(8.0, 5.0, 2.0))
	_run(4.0)
	assert_float(trim + Audio.bed_fade_db(&"bed_roof_wind")).is_equal_approx(
		-19.0 + t.roof_db[&"UpperA"], 0.01
	)


func test_the_room_tone_fades_away_outside_the_walls_and_back() -> void:
	await _start(false)
	_run(4.0)
	assert_float(Audio.bed_fade_db(&"bed_room_tone")).is_greater(-1.0)
	_stand(OUTSIDE)
	_run(3.0)
	assert_bool(Audio.is_bed_running(&"bed_room_tone")).is_false()
	_stand(START_EAR)
	_run(4.0)
	assert_bool(Audio.is_bed_running(&"bed_room_tone")).is_true()
	assert_float(Audio.bed_fade_db(&"bed_room_tone")).is_greater(-1.0)


func test_a_night_that_is_over_ends_the_room_tone_and_the_yard() -> void:
	await _start()
	_run(4.0)
	_tell({"type": &"game_over", "round_reached": 3})
	_run(3.0)
	assert_bool(Audio.is_bed_running(&"bed_room_tone")).is_false()
	_stand(Vector3(-3.0, 5.0, -4.0))
	_run(3.0)
	assert_bool(Audio.is_bed_running(&"bed_roof_wind")).is_false()
	for source in _sounds.yard.sources:
		assert_bool(source.player.playing).is_false()


# --- The pieces ---


func test_a_board_torn_off_a_window_cracks_at_its_opening() -> void:
	await _start(false)
	_listen()
	_tell({"type": &"board_torn", "barricade_id": &"start_1", "boards": 3, "zombie_id": 1})
	assert_array(_ids()).is_equal([&"board_tear"])
	assert_vector(_last(&"board_tear")["at"]).is_equal_approx(WINDOW_1, Vector3.ONE * 0.01)


func test_the_last_board_has_its_own_louder_sound_and_a_repair_knocks() -> void:
	await _start(false)
	_listen()
	_tell({"type": &"board_torn", "barricade_id": &"upper_a1", "boards": 0, "zombie_id": 1})
	_tell({"type": &"board_repaired", "barricade_id": &"upper_a1", "boards": 1, "player_id": 1})
	assert_array(_ids()).is_equal([&"board_last", &"board_repair"])
	var upper: Vector3 = _last(&"board_last")["at"]
	assert_float(upper.y).is_equal_approx(3.4 + SmallMapSoundTuning.current().window_lift, 0.01)


func test_a_window_nobody_knows_makes_no_sound() -> void:
	await _start(false)
	_listen()
	_tell({"type": &"board_torn", "barricade_id": &"nowhere", "boards": 2, "zombie_id": 1})
	assert_array(_ids()).is_empty()


func test_the_plank_door_opens_and_the_debris_comes_off_its_stair() -> void:
	await _start(false)
	_listen()
	_tell({"type": &"door_opened", "door_id": &"door_side"})
	assert_array(_ids()).is_equal([&"door_open"])
	assert_vector(_heard[0]["at"]).is_equal_approx(Vector3(14.0, 1.2, -0.15), Vector3.ONE * 0.01)
	_tell({"type": &"door_opened", "door_id": &"door_stairs_start"})
	_tell({"type": &"door_opened", "door_id": &"door_stairs_side"})
	assert_array(_ids()).is_equal([&"door_open", &"debris_clear", &"debris_clear"])
	assert_vector(_heard[1]["at"]).is_equal_approx(Vector3(3.0, 1.2, 1.0), Vector3.ONE * 0.01)
	assert_vector(_heard[2]["at"]).is_equal_approx(Vector3(-3.0, 1.2, -6.8), Vector3.ONE * 0.01)


func test_a_door_taken_down_still_sounds_where_it_stood() -> void:
	await _start(false)
	_listen()
	var door := _greybox.get_node("Doors/Stairs_Start")
	for part in door.get_children():
		door.remove_child(part)
		part.queue_free()
	_tell({"type": &"door_opened", "door_id": &"door_stairs_start"})
	assert_array(_ids()).is_equal([&"debris_clear"])


# --- Feet on wood ---


func test_the_stairs_and_the_upper_floor_step_like_wood_the_ground_floor_like_asphalt() -> void:
	await _start(false)
	var surfaces := FootSurface.new()
	var space := _greybox.get_world_3d().direct_space_state
	assert_str(surfaces.at(space, Vector3(8.0, 0.0, 10.0))).is_equal("asphalt")
	assert_str(surfaces.at(space, Vector3(8.0, 3.4, 2.0))).is_equal("wood")
	assert_str(surfaces.at(space, Vector3(5.6, 1.8, 1.0))).is_equal("wood")
	assert_str(FootstepSounds.sound_for(&"wood", true)).is_equal("step_own_wood")
	assert_str(FootstepSounds.sound_for(&"wood", false)).is_equal("step_wood")
