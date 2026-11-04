# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## What the soldiers say, driven like a client: events in, takes out, on a clock the test steps by
## hand. The local player's voice is flat, a teammate's is where they stand, a downed or hurt line
## cuts the others, and the moments that are not voiced all the time are asked until they are.

const OWN := 1
const MATE := 2
const AT_MATE := Vector3(6.0, 0.0, 2.0)

var _heard: Array[Dictionary] = []
var _voice: SoldierVoice
var _state: ClientState
## A dead one close to the player, so a round is never a lull (and the soldier does not muse).
var _dead_near := true


func before_test() -> void:
	_heard = []
	_state = ClientState.new()
	_state.player_id = OWN
	_voice = auto_free(SoldierVoice.new())
	_voice.play = func(id: StringName, at: Variant, db: float) -> bool:
		_heard.append({"id": id, "at": at, "db": db, "t": _voice.director.now()})
		return true
	add_child(_voice)
	_voice.setup(_state, 5)
	_frame(GameRules.Phase.ACTIVE)


func _frame(phase: int, mate_downed := false) -> void:
	(
		_state
		. apply_events(
			[
				{
					"type": &"frame",
					"phase": phase,
					"players":
					{
						OWN: {"pos": Vector3.ZERO, "downed": false, "health": 100.0},
						MATE: {"pos": AT_MATE, "downed": mate_downed, "health": 100.0},
					},
					"zombies": [],
				}
			]
		)
	)
	if _dead_near:
		_state.zombies = [{"position": Vector3(4.0, 0.0, 0.0)}]


func _tell(event: Dictionary) -> void:
	_state.apply_events([event])


## Steps the clock past the longest line and its gap, so the next request meets a free channel.
func _settle(seconds := 12.0) -> void:
	_voice.step(seconds)


func _moments() -> Array:
	var found: Array = []
	for line in _voice.director.history:
		found.append(String(line["event"]))
	return found


func _hurt(who: int, health := 80.0) -> Dictionary:
	return {
		"type": &"player_hurt",
		"player_id": who,
		"damage": 10.0,
		"health": health,
		"max_health": 100.0,
		"bearing": 0.0,
		"source_id": 4,
	}


func _killed(killer: int, boss := false) -> Dictionary:
	return {
		"type": &"zombie_removed",
		"zombie_id": 3,
		"zombie_type": &"walker",
		"boss": boss,
		"cause": &"killed",
		"killer_id": killer,
		"zone": &"body",
		"melee": false,
	}


func _say_until(event: StringName, speaker: int) -> bool:
	for i in 40:
		if _voice.say(event, speaker):
			return true
	return false


func test_a_take_is_a_sound_of_the_catalog_and_names_its_moment() -> void:
	assert_bool(_say_until(&"reload", OWN)).is_true()
	assert_str(_heard[0]["id"]).starts_with("vox_reload_")
	assert_object(SoundCatalog.get_def(_heard[0]["id"])).is_not_null()


## A frame in which `OWN` speaks with `own_voice` and `MATE` with `mate_voice`.
func _voices(own_voice: StringName, mate_voice: StringName) -> void:
	(
		_state
		. apply_events(
			[
				{
					"type": &"frame",
					"phase": GameRules.Phase.ACTIVE,
					"players":
					{
						OWN:
						{"pos": Vector3.ZERO, "downed": false, "health": 100.0, "voice": own_voice},
						MATE:
						{"pos": AT_MATE, "downed": false, "health": 100.0, "voice": mate_voice},
					},
					"zombies": [],
				}
			]
		)
	)
	_state.zombies = [{"position": Vector3(4.0, 0.0, 0.0)}]


func test_a_player_speaks_with_the_voice_their_frame_names() -> void:
	_voices(&"female", &"male")
	assert_bool(_say_until(&"reload", OWN)).is_true()
	assert_str(_heard[0]["id"]).starts_with("voxf_reload_")
	_settle()
	assert_bool(_say_until(&"reload", MATE)).is_true()
	assert_str(_heard[1]["id"]).starts_with("vox_reload_")
	_settle()
	_voices(&"male", &"female")
	assert_bool(_say_until(&"dry", MATE)).is_true()
	assert_str(_heard[2]["id"]).starts_with("voxf_dry_")


func test_every_moment_is_voiced_for_both_characters_with_a_file_for_each() -> void:
	for voice: StringName in SoldierVoiceCatalog.voices():
		_voices(voice, voice)
		for event: StringName in SoldierVoiceCatalog.events():
			_settle(30.0)
			var before := _heard.size()
			(
				assert_bool(_say_until(event, OWN))
				. override_failure_message("%s %s" % [voice, event])
				. is_true()
			)
			var id: StringName = _heard[before]["id"]
			assert_str(id).starts_with(SoldierVoiceCatalog.VOICES[voice]["prefix"] + String(event))
			var def := SoundCatalog.get_def(id)
			assert_object(def).override_failure_message(String(id)).is_not_null()
			(
				assert_bool(ResourceLoader.exists(def.path_for(1)))
				. override_failure_message(String(id))
				. is_true()
			)


func test_the_local_player_is_flat_and_a_little_lower() -> void:
	assert_bool(_say_until(&"reload", OWN)).is_true()
	assert_object(_heard[0]["at"]).is_null()
	assert_float(_heard[0]["db"]).is_equal(SoundCatalog.mix().own_voice_db)


func test_a_teammate_speaks_from_where_they_stand() -> void:
	assert_bool(_say_until(&"reload", MATE)).is_true()
	assert_vector(_heard[0]["at"]).is_equal_approx(
		AT_MATE + SoldierVoice.HEAD_LIFT, Vector3.ONE * 0.01
	)
	assert_float(_heard[0]["db"]).is_equal(0.0)


func test_a_reload_makes_the_shooter_call_it_out() -> void:
	for i in 40:
		_tell(
			{"type": &"reload_started", "shooter_id": MATE, "weapon_id": &"rifle", "seconds": 2.0}
		)
		_settle()
		if not _heard.is_empty():
			break
	assert_array(_moments()).contains([&"reload"])
	assert_int(_voice.director.history[0]["speaker"]).is_equal(MATE)


func test_an_empty_trigger_is_the_dry_call() -> void:
	for i in 40:
		_tell({"type": &"fire_rejected", "shooter_id": OWN, "seq": 1, "reason": &"empty"})
		_settle()
	assert_array(_moments()).contains([&"dry"])
	_heard.clear()
	_voice.director.history.clear()
	_tell({"type": &"fire_rejected", "shooter_id": OWN, "seq": 2, "reason": &"cooldown"})
	assert_array(_moments()).is_empty()


func test_the_last_rounds_with_nothing_in_reserve_are_a_low_ammo_call() -> void:
	var shot := {
		"type": &"shot_fired",
		"shooter_id": OWN,
		"weapon_id": &"rifle",
		"seq": 1,
		"muzzle": Vector3.ZERO,
		"ends": [],
		"ammo": 2,
		"reserve": 8,
	}
	_tell(shot)
	assert_array(_moments()).is_empty()
	shot["reserve"] = 0
	_tell(shot)
	assert_array(_moments()).contains([&"low_ammo"])


func test_a_melee_swing_is_never_low_ammo() -> void:
	_tell(
		{
			"type": &"shot_fired",
			"shooter_id": OWN,
			"weapon_id": &"crowbar",
			"seq": 1,
			"muzzle": Vector3.ZERO,
			"ends": [],
			"ammo": 1,
			"reserve": 0,
		}
	)
	assert_array(_moments()).is_empty()


func test_four_kills_close_together_are_a_streak() -> void:
	for i in 4:
		_tell(_killed(OWN))
		_voice.step(0.5)
	assert_array(_moments()).contains([&"streak"])


func test_kills_far_apart_are_not_a_streak() -> void:
	for i in 6:
		_tell(_killed(OWN))
		_settle(NightSoundTuning.current().streak_window + 3.0)
	assert_array(_moments()).not_contains([&"streak"])


func test_a_dead_boss_is_its_own_moment_not_a_kill() -> void:
	_tell(_killed(OWN, true))
	_settle()
	assert_array(_moments()).contains([&"boss_dead"])
	assert_array(_moments()).not_contains([&"kill"])


func test_a_boss_arriving_is_called_out_after_a_beat() -> void:
	_tell(
		{
			"type": &"zombie_spawn_requested",
			"zombie_id": 9,
			"zombie_type": &"headliner",
			"boss": true
		}
	)
	assert_array(_moments()).is_empty()
	_voice.step(NightSoundTuning.current().boss_delay + 0.1)
	assert_array(_moments()).contains([&"boss_arrive"])


func test_a_round_starts_after_the_sting_and_a_boss_round_has_the_boss_line_instead() -> void:
	_tell(
		{
			"type": &"round_started",
			"round": 2,
			"zombie_count": 8,
			"special_id": &"",
			"boss_count": 0
		}
	)
	_voice.step(NightSoundTuning.current().round_start_delay + 0.1)
	assert_array(_moments()).contains([&"round_start"])
	_settle(30.0)
	_voice.director.history.clear()
	_tell(
		{
			"type": &"round_started",
			"round": 5,
			"zombie_count": 8,
			"special_id": &"",
			"boss_count": 1
		}
	)
	_voice.step(NightSoundTuning.current().round_start_delay + 0.1)
	assert_array(_moments()).not_contains([&"round_start"])


func test_a_cleared_round_is_a_moment_to_catch_the_breath() -> void:
	_tell({"type": &"round_ended", "round": 2, "special_id": &""})
	_voice.step(NightSoundTuning.current().round_clear_delay + 0.1)
	assert_array(_moments()).contains([&"round_clear"])


func test_a_blow_is_a_hurt_grunt_and_a_bad_one_a_close_call_afterwards() -> void:
	_tell(_hurt(OWN, 20.0))
	_voice.step(8.0)
	assert_array(_moments()).contains([&"close_call"])


func test_going_down_cuts_the_line_that_speaks_and_a_teammate_calls_it() -> void:
	assert_bool(_say_until(&"idle", OWN)).is_true()
	_voice.step(0.5)
	_tell({"type": &"player_downed", "player_id": OWN, "cause": &"blow", "bearing": 0.0})
	assert_str(_voice.director.history.back()["event"]).is_equal("downed")
	_frame(GameRules.Phase.ACTIVE)
	_voice.step(10.0)
	assert_array(_moments()).contains([&"teammate_down"])
	var call: Dictionary = _voice.director.history.back()
	assert_int(call["speaker"]).is_equal(MATE)


func test_a_downed_player_says_nothing_but_their_own_fall() -> void:
	_frame(GameRules.Phase.ACTIVE, true)
	assert_bool(_voice.say(&"reload", MATE)).is_false()
	assert_bool(_say_until(&"downed", MATE)).is_true()


func test_getting_up_is_a_thank_you() -> void:
	_tell({"type": &"player_revived", "player_id": MATE})
	_voice.step(1.0)
	assert_array(_moments()).contains([&"revived"])


func test_a_bought_weapon_a_big_one_and_a_door_each_have_their_line() -> void:
	_tell({"type": &"purchase_made", "player_id": OWN, "item_id": &"weapon_shotgun", "price": 900})
	_voice.step(1.0)
	_settle()
	_tell({"type": &"purchase_made", "player_id": OWN, "item_id": &"weapon_rifle", "price": 1200})
	_voice.step(1.0)
	_settle()
	_tell({"type": &"purchase_made", "player_id": OWN, "item_id": &"door_yard", "price": 500})
	_voice.step(1.0)
	_settle()
	_tell({"type": &"purchase_made", "player_id": OWN, "item_id": &"ammo_rifle", "price": 80})
	_voice.step(1.0)
	assert_array(_moments()).is_equal(["buy_weapon", "buy_big", "door"])


func test_the_generator_coming_on_and_going_low_are_called() -> void:
	_tell({"type": &"fuel_restored"})
	_settle()
	_tell({"type": &"fuel_low"})
	assert_array(_moments()).is_equal(["power_on", "power_low"])


func test_a_thrown_grenade_is_called_by_the_thrower() -> void:
	for i in 40:
		_tell({"type": &"grenade_thrown", "grenade_id": 1, "thrower_id": MATE, "position": AT_MATE})
		_settle()
	assert_array(_moments()).contains([&"grenade"])
	assert_int(_voice.director.history[0]["speaker"]).is_equal(MATE)


func test_a_quiet_break_makes_the_soldier_muse_but_a_short_one_does_not() -> void:
	_frame(GameRules.Phase.BREAK)
	_tell({"type": &"break_started", "next_round": 2, "seconds": 20.0})
	_voice.step(NightSoundTuning.current().idle_after + 0.5)
	assert_array(_moments()).contains([&"idle"])
	_settle(60.0)
	_voice.director.history.clear()
	_tell({"type": &"break_started", "next_round": 3, "seconds": 9.0})
	_voice.step(NightSoundTuning.current().idle_after + 0.5)
	assert_array(_moments()).not_contains([&"idle"])


func test_a_lull_in_a_round_makes_the_soldier_muse_but_the_dead_close_by_do_not() -> void:
	_dead_near = false
	_frame(GameRules.Phase.ACTIVE)
	_voice.step(NightSoundTuning.current().idle_after + 1.0)
	_voice.step(NightSoundTuning.current().lull + 0.5)
	assert_array(_moments()).contains([&"idle"])
	_settle(60.0)
	_voice.director.history.clear()
	_dead_near = true
	_frame(GameRules.Phase.ACTIVE)
	for i in 40:
		_voice.step(1.0)
	assert_array(_moments()).not_contains([&"idle"])


func test_the_night_ending_stops_the_talk() -> void:
	_tell({"type": &"round_ended", "round": 2, "special_id": &""})
	_tell({"type": &"game_over", "reason": &"all_down", "round_reached": 2})
	_voice.step(10.0)
	assert_array(_moments()).is_empty()


func test_lines_played_through_the_service_are_dropped_cleanly_when_it_says_no() -> void:
	_voice.play = func(_id: StringName, _at: Variant, _db: float) -> Variant: return null
	assert_bool(_voice.say(&"reload", OWN)).is_false()
	assert_array(_moments()).is_empty()


## Players wearing `bodies` ({player id: &"male" or &"female"}), heard the way a night hears looks.
func _wearing(bodies: Dictionary) -> LookRegistry:
	var looks := LookRegistry.new()
	for id: int in bodies:
		var look := CharacterLook.default_look()
		look.set_body(bodies[id])
		looks.receive(LookWire.player_look(id, id - 1, look))
	return looks


func test_the_character_a_player_chose_sets_the_voice_they_speak_with() -> void:
	_voice.looks = _wearing({OWN: LookCatalog.FEMALE, MATE: LookCatalog.MALE})
	assert_str(String(_voice._player(OWN)["voice"])).is_equal("female")
	assert_str(String(_voice._player(MATE)["voice"])).is_equal("male")
	# She speaks with her lines (voxf_), he with his (vox_), for the same moment.
	assert_bool(_say_until(&"reload", OWN)).is_true()
	assert_str(String(_heard[0]["id"])).starts_with("voxf_reload_")
	_settle()
	_heard.clear()
	assert_bool(_say_until(&"reload", MATE)).is_true()
	assert_str(String(_heard[0]["id"])).starts_with("vox_reload_")
	assert_object(SoundCatalog.get_def(_heard[0]["id"])).is_not_null()


## What the frame entry names wins over the look.
func test_a_voice_the_frame_names_wins_over_the_look() -> void:
	_voice.looks = _wearing({OWN: LookCatalog.FEMALE, MATE: LookCatalog.FEMALE})
	_voices(&"male", &"male")
	assert_bool(_say_until(&"reload", OWN)).is_true()
	assert_str(String(_heard[0]["id"])).starts_with("vox_reload_")


func test_a_player_whose_look_has_not_arrived_has_his_voice() -> void:
	_voice.looks = _wearing({OWN: LookCatalog.FEMALE})
	assert_str(String(_voice.look_voice(MATE))).is_equal("male")
	assert_bool(_say_until(&"reload", MATE)).is_true()
	assert_str(String(_heard[0]["id"])).starts_with("vox_reload_")


func test_a_cheer_for_every_progression_moment_plays_for_both_voices() -> void:
	for voice: StringName in [&"male", &"female"]:
		_voices(voice, voice)
		for event in SoldierVoiceCatalog.PROGRESS:
			_voice.step(100.0)
			_heard.clear()
			_voice.celebrate(event, OWN)
			_voice.step(0.1)
			assert_int(_heard.size()).override_failure_message("%s %s" % [voice, event]).is_equal(1)
			var prefix: String = SoldierVoiceCatalog.VOICES[voice]["prefix"]
			assert_str(String(_heard[0]["id"])).starts_with("%s%s_" % [prefix, event])
			assert_object(SoundCatalog.get_def(_heard[0]["id"])).is_not_null()


func test_a_teammates_cheer_is_heard_where_they_stand_and_ours_is_flat() -> void:
	_voice.celebrate(&"level_up", MATE)
	_voice.step(0.1)
	assert_int(_heard.size()).is_equal(1)
	assert_vector(_heard[0]["at"]).is_equal_approx(
		AT_MATE + SoldierVoice.HEAD_LIFT, Vector3.ONE * 0.01
	)
	assert_float(_heard[0]["db"]).is_equal(0.0)
	_voice.step(100.0)
	_heard.clear()
	_voice.celebrate(&"level_up", OWN)
	_voice.step(0.1)
	assert_object(_heard[0]["at"]).is_null()
	assert_float(_heard[0]["db"]).is_equal(SoundCatalog.mix().own_voice_db)


func test_a_cheer_waits_for_the_line_that_speaks_instead_of_being_dropped() -> void:
	assert_bool(_say_until(&"reload", OWN)).is_true()
	_voice.step(0.2)
	_voice.celebrate(&"tier_up", MATE)
	_voice.step(0.2)
	assert_array(_moments()).is_equal(["reload"])
	_voice.step(12.0)
	assert_array(_moments()).is_equal(["reload", "tier_up"])


func test_a_downed_player_does_not_cheer_and_a_hurt_cuts_a_cheer() -> void:
	_frame(GameRules.Phase.ACTIVE, true)
	_voice.celebrate(&"level_up", MATE)
	_voice.step(0.1)
	assert_array(_moments()).is_empty()
	_frame(GameRules.Phase.ACTIVE)
	_voice.celebrate(&"level_up", OWN)
	_voice.step(0.1)
	assert_array(_moments()).is_equal(["level_up"])
	assert_bool(_say_until(&"hurt", OWN)).is_true()
	assert_array(_moments()).is_equal(["level_up", "hurt"])


func _level_up(who: int, level := 2) -> Dictionary:
	return {"type": &"level_up", "player_id": who, "level": level, "total": 100}


func _tier_up(who: int) -> Dictionary:
	return {"type": &"tier_up", "player_id": who, "tier": 1, "tier_name": "Cartoon", "level": 6}


func _unlock(who: int, slot: StringName, item := &"thing") -> Dictionary:
	return {"type": &"unlock_earned", "player_id": who, "level": 3, "slot": slot, "item": item}


func test_the_server_telling_a_teammates_level_up_is_heard_where_they_stand() -> void:
	_tell(_level_up(MATE))
	_voice.step(0.05)
	assert_array(_moments()).is_empty()
	_voice.step(_voice._t.cheer_window)
	assert_array(_moments()).is_equal(["level_up"])
	assert_vector(_heard[0]["at"]).is_equal_approx(
		AT_MATE + SoldierVoice.HEAD_LIFT, Vector3.ONE * 0.01
	)
	assert_int(_voice.director.history[0]["speaker"]).is_equal(MATE)


func test_a_tier_a_level_and_an_item_that_come_together_are_one_cheer() -> void:
	_tell(_level_up(OWN, 6))
	_tell(_tier_up(OWN))
	_tell(_unlock(OWN, &"headwear"))
	_settle()
	assert_array(_moments()).is_equal(["tier_up"])
	assert_int(_heard.size()).is_equal(1)


func test_a_level_that_gives_an_item_is_cheered_for_the_item_by_its_slot() -> void:
	var expected := {
		&"colour": "unlock",
		&"top": "unlock",
		&"map": "unlock",
		&"tier_card": "card",
		&"calling_cards": "card",
		&"tier_emblem": "emblem",
		&"emblem": "emblem",
		&"plate_frame": "emblem",
	}
	for slot: StringName in expected:
		_voice.step(100.0)
		_voice.director.history.clear()
		_tell(_level_up(MATE))
		_tell(_unlock(MATE, slot))
		_settle()
		assert_array(_moments()).override_failure_message(String(slot)).is_equal([expected[slot]])


func test_a_level_alone_is_cheered_as_a_level() -> void:
	_tell(_level_up(MATE))
	_tell(_level_up(MATE, 3))
	_settle()
	assert_array(_moments()).is_equal(["level_up"])


func test_two_players_who_level_up_together_are_cheered_one_after_the_other() -> void:
	_tell(_level_up(OWN))
	_tell(_level_up(MATE))
	for _i in 200:
		_voice.step(0.1)
	assert_array(_moments()).is_equal(["level_up", "level_up"])
	var speakers := _voice.director.history.map(
		func(line: Dictionary) -> int: return line["speaker"]
	)
	assert_array(speakers).contains_exactly_in_any_order([OWN, MATE])


func test_events_that_are_no_cheer_say_nothing_and_the_night_ending_drops_a_waiting_one() -> void:
	_tell(
		{
			"type": &"xp_gained",
			"player_id": MATE,
			"hundredths": 100,
			"xp": 1,
			"total": 1,
			"sources": {},
		}
	)
	_settle()
	assert_array(_moments()).is_empty()
	_tell(_level_up(MATE))
	_tell({"type": &"game_over", "round_reached": 3})
	_settle()
	assert_array(_moments()).is_empty()
	# And the next cheer is not held back by the dropped one.
	_tell(_level_up(MATE))
	_settle()
	assert_array(_moments()).is_equal(["level_up"])


func test_a_level_up_told_while_a_reload_speaks_is_cheered_when_it_ends() -> void:
	assert_bool(_say_until(&"reload", OWN)).is_true()
	_tell(_level_up(MATE))
	for _i in 12:
		_voice.step(0.1)
	assert_array(_moments()).is_equal(["reload"])
	_settle()
	assert_array(_moments()).is_equal(["reload", "level_up"])


func test_a_cheer_for_a_downed_player_is_dropped_and_leaves_nothing_scheduled() -> void:
	_frame(GameRules.Phase.ACTIVE, true)
	_tell(_level_up(MATE))
	_settle()
	assert_array(_moments()).is_empty()
	assert_int(_voice.schedule.pending()).is_equal(0)
	# They get up and the next level is cheered.
	_frame(GameRules.Phase.ACTIVE)
	_tell(_level_up(MATE, 3))
	_settle()
	assert_array(_moments()).is_equal(["level_up"])
