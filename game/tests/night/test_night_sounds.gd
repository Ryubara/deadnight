# What the night sounds like besides the guns, driven like a client: events in, sounds out. The
# ambient bed starts with the night and stops with it, the boards, doors, blows and the till play
# where they happen, and the score belongs to the breaks.
extends GdUnitTestSuite

const OWN := Night.PLAYER_ID
const NEAR := Vector3.ONE * 0.01
const BED_IDS: Array[StringName] = [&"bed_crickets", &"bed_highway", &"bed_score"]

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
	return _heard.map(func(h: Dictionary) -> StringName: return h["id"])


func _last(id: StringName) -> Dictionary:
	for i in range(_heard.size() - 1, -1, -1):
		if _heard[i]["id"] == id:
			return _heard[i]
	return {}


func _tell(night: Night, event: Dictionary) -> void:
	night.state.apply_events([event])


func _breach(night: Night) -> StringName:
	return night.world.barricade_ids()[0]


func _swing(weapon_id: StringName, muzzle: Vector3) -> Dictionary:
	return {
		"type": &"shot_fired",
		"shooter_id": OWN,
		"weapon_id": weapon_id,
		"seq": 1,
		"muzzle": muzzle,
		"ends": [muzzle],
		"ammo": 1,
		"reserve": 1,
	}


func test_the_night_starts_its_ambient_bed_and_the_score() -> void:
	var night := await _start()
	assert_object(night).is_not_null()
	for id in BED_IDS:
		assert_bool(Audio.is_bed_running(id)).override_failure_message(id).is_true()


func test_the_progression_cues_are_quieter_while_the_night_runs_and_not_after_it() -> void:
	var night := await _start()
	assert_bool(Audio.ui.in_night).is_true()
	night.free()
	assert_bool(Audio.ui.in_night).is_false()


func test_the_projector_runs_in_the_booth_as_a_loop_in_the_world() -> void:
	var night := await _start()
	var anchor := night.view.sounds.get_node_or_null("Projector") as Node3D
	assert_object(anchor).is_not_null()
	var player := anchor.get_child(0) as AudioStreamPlayer3D
	assert_bool(player.playing).is_true()
	assert_bool((player.stream as AudioStreamOggVorbis).loop).is_true()
	var booth := night.world.greybox.get_node("ProjectionBooth") as Node3D
	var nearest := INF
	for child in booth.get_children():
		var at := (child as Node3D).global_position
		nearest = minf(nearest, at.distance_to(anchor.global_position))
	assert_float(nearest).is_less(12.0)


func test_a_board_torn_creaks_and_cracks_at_the_breach() -> void:
	var night := await _start()
	var id := _breach(night)
	var centre := night.world.barricade(id).centre()
	_ears.global_position = centre + Vector3(0.0, 0.0, 6.0)
	_tell(night, {"type": &"board_torn", "barricade_id": id, "boards": 3, "zombie_id": 1})
	var heard := _last(&"board_tear")
	assert_bool(heard.is_empty()).is_false()
	assert_vector(heard["at"]).is_equal_approx(centre + NightSounds.BOARD_LIFT, NEAR)
	assert_array(_ids()).not_contains([&"board_last"])


func test_the_last_board_going_has_its_own_louder_sound() -> void:
	var night := await _start()
	var id := _breach(night)
	_ears.global_position = night.world.barricade(id).centre()
	_tell(night, {"type": &"board_torn", "barricade_id": id, "boards": 0, "zombie_id": 1})
	assert_array(_ids()).contains([&"board_last"])
	assert_array(_ids()).not_contains([&"board_tear"])


func test_a_board_put_back_knocks_at_the_breach() -> void:
	var night := await _start()
	var id := _breach(night)
	_ears.global_position = night.world.barricade(id).centre()
	_tell(night, {"type": &"board_repaired", "barricade_id": id, "boards": 2, "player_id": OWN})
	assert_array(_ids()).contains([&"board_repair"])


func test_a_breach_too_far_to_hear_is_dropped_not_played() -> void:
	var night := await _start()
	var id := _breach(night)
	_ears.global_position = night.world.barricade(id).centre() + Vector3(500.0, 0.0, 0.0)
	var culled := Audio.culled
	_tell(night, {"type": &"board_torn", "barricade_id": id, "boards": 2, "zombie_id": 1})
	assert_array(_ids()).not_contains([&"board_tear"])
	assert_int(Audio.culled).is_equal(culled + 1)


func test_a_real_tear_and_repair_through_the_rules_make_their_sounds() -> void:
	var night := await _start()
	var id := _breach(night)
	_ears.global_position = night.world.barricade(id).centre()
	var rules := night.server.rules
	rules.apply(RulesAction.skip_break())
	var zombie_id := -1
	for _i in 600:
		NightFixture.run(night, 1)
		if not rules.zombie_ids().is_empty():
			zombie_id = rules.zombie_ids()[0]
			break
	assert_int(zombie_id).is_greater(-1)
	night.state.apply_events(rules.apply(RulesAction.tear_board(id, zombie_id)))
	assert_array(_ids()).contains([&"board_tear"])
	night.state.apply_events(rules.apply(RulesAction.repair(OWN, id)))
	assert_array(_ids()).contains([&"board_repair"])


func test_a_door_opening_sounds_at_the_door() -> void:
	var night := await _start()
	var door: StringName = night.world.door_ids()[0]
	var point := night.world.door_points(door)[0]
	_ears.global_position = point
	_tell(night, {"type": &"door_opened", "door_id": door})
	var heard := _last(&"door_open")
	assert_bool(heard.is_empty()).is_false()
	assert_vector(heard["at"]).is_equal_approx(point, NEAR)


func test_a_purchase_rings_the_till_where_the_buyer_stands() -> void:
	var night := await _start()
	var stands: Vector3 = night.state.position()
	_ears.global_position = stands
	_tell(
		night,
		{
			"type": &"purchase_made",
			"player_id": OWN,
			"item_id": &"door_yard",
			"price": 750,
			"detail": {}
		}
	)
	var heard := _last(&"till_ring")
	assert_bool(heard.is_empty()).is_false()
	assert_vector(heard["at"]).is_equal_approx(stands + NightSounds.HEAD_LIFT, NEAR)


func test_a_swing_of_the_crowbar_whooshes_and_a_gun_does_not() -> void:
	var night := await _start()
	var muzzle := Vector3(1.0, 1.4, 1.0)
	_ears.global_position = muzzle
	_tell(night, _swing(&"rifle", muzzle))
	assert_array(_ids()).not_contains([&"melee_swing"])
	_tell(night, _swing(&"crowbar", muzzle))
	assert_array(_ids()).contains([&"melee_swing"])


func test_a_blow_that_lands_thuds_and_a_bullet_does_not() -> void:
	var night := await _start()
	var point := Vector3(2.0, 1.0, 2.0)
	_ears.global_position = point
	var hit := {
		"type": &"damage_dealt",
		"shooter_id": OWN,
		"target_id": 1,
		"zone": &"body",
		"damage": 40.0,
		"headshot": false,
		"melee": false,
		"pellets": 1,
		"health": 10.0,
		"point": point,
	}
	_tell(night, hit)
	assert_array(_ids()).not_contains([&"melee_hit"])
	hit["melee"] = true
	_tell(night, hit)
	assert_array(_ids()).contains([&"melee_hit"])


func test_the_score_belongs_to_the_breaks() -> void:
	var night := await _start()
	Audio.advance(4.0)
	assert_float(Audio.bed_fade_db(&"bed_score")).is_equal(0.0)
	_tell(
		night,
		{
			"type": &"round_started",
			"round": 1,
			"zombie_count": 6,
			"special_id": &"",
			"boss_count": 0
		}
	)
	Audio.advance(3.0)
	assert_bool(Audio.is_bed_running(&"bed_score")).is_false()
	assert_bool(Audio.is_bed_running(&"bed_crickets")).is_true()
	_tell(night, {"type": &"round_ended", "round": 1, "special_id": &""})
	assert_bool(Audio.is_bed_running(&"bed_score")).is_true()


func test_game_over_fades_the_whole_bed_out() -> void:
	var night := await _start()
	Audio.advance(4.0)
	_tell(night, {"type": &"game_over", "reason": &"all_down", "round_reached": 3})
	_tell(night, {"type": &"round_ended", "round": 3, "special_id": &""})
	Audio.advance(3.0)
	for id in BED_IDS:
		assert_bool(Audio.is_bed_running(id)).override_failure_message(id).is_false()


func test_leaving_the_night_leaves_no_bed_playing() -> void:
	var night := await _start()
	Audio.advance(4.0)
	night.free()
	Audio.advance(3.0)
	for id in BED_IDS:
		assert_bool(Audio.is_bed_running(id)).override_failure_message(id).is_false()
