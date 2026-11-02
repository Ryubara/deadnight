# The player's feet in the night: the local player's own steps are quiet, flat and from the softer
# set; everyone else's are where their feet are; the ground picks gravel or asphalt; a sprint is
# louder and quicker, a crouch much quieter; none in the air; the takes vary.
extends GdUnitTestSuite

const OWN := Night.PLAYER_ID
const OTHER := 2
const STRIDE := 1.9
## Where the yard's ground is clear of the generator and the cages, from its first slab's centre.
const YARD_OPEN_GROUND := Vector3(-7.0, 0.3, 4.0)

var _steps: Array[Dictionary] = []
var _start_point := Vector3.ZERO


func before_test() -> void:
	Audio.stop_all()
	Audio.seed_random(5)
	_steps = []


func after_test() -> void:
	Audio.stop_all()


func _record(id: StringName, at: Variant, extra_db: float) -> void:
	_steps.append({"id": id, "at": at, "db": extra_db})


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 30)
	_feet(night).play = _record
	return night


func _feet(night: Night) -> FootstepSounds:
	return night.view.sounds.get_node("FootstepSounds") as FootstepSounds


func _walk(sprint := false, crouch := false, jump := false) -> NightCommand:
	var command := NightCommand.new()
	command.motion.move = Vector2(0.0, -1.0)
	command.motion.sprint = sprint
	command.motion.crouch = crouch
	command.motion.jump = jump
	return command


## A client for frames alone: the other players of an online night.
func _frames_only() -> Array:
	var state := ClientState.new()
	state.player_id = OWN
	var feet := FootstepSounds.new()
	add_child(feet)
	feet.setup(state, func(_id: int) -> Player: return null, 3)
	feet.play = _record
	feet.surface_probe = func(point: Vector3) -> StringName:
		return &"gravel" if point.x > 50.0 else &"asphalt"
	return [state, feet]


func _frame(tick: int, positions: Dictionary) -> Dictionary:
	var players := {}
	for id: int in positions:
		players[id] = {"pos": positions[id], "downed": false}
	return {
		"type": &"frame",
		"tick": tick,
		"players": players,
		"zombies": ZombieCodec.encode({}),
	}


## A player walking along x at `speed` for `seconds`, one frame every two ticks.
func _run_frames(state: ClientState, id: int, speed: float, seconds: float, x0 := 0.0) -> void:
	var tick := 0
	for i in int(seconds * 30.0) + 1:
		state.apply_events([_frame(tick, {id: Vector3(x0 + speed * tick / 60.0, 0.0, 0.0)})])
		tick += 2


func _mean_db(steps: Array[Dictionary]) -> float:
	assert_int(steps.size()).is_greater(1)
	var total := 0.0
	for step in steps:
		total += step["db"]
	return total / steps.size()


## The steps a run of 100 ticks under `command` makes.
func _steps_of(night: Night, command: NightCommand) -> Array[Dictionary]:
	_steps = []
	night.player().teleport(_start_point)
	NightFixture.run(night, 3)
	_steps = []
	NightFixture.run(night, 100, command)
	var found: Array[Dictionary] = []
	found.assign(_steps)
	return found


func test_the_levels_rise_with_pace_and_a_crouch_is_the_quietest() -> void:
	var walk := FootstepSounds.level_db(4.8, false, false)
	var sprint := FootstepSounds.level_db(7.0, true, false)
	var creep := FootstepSounds.level_db(2.4, false, true)
	assert_float(walk).is_equal_approx(0.0, 0.01)
	assert_float(sprint - walk).is_between(3.0, 5.0)
	assert_float(walk - creep).is_greater(9.0)
	assert_float(FootstepSounds.level_db(0.1, false, true)).is_equal(
		NightSoundTuning.current().step_min_db
	)
	assert_float(FootstepSounds.level_db(30.0, true, false)).is_less_equal(
		NightSoundTuning.current().step_max_db
	)


func test_the_sound_follows_the_surface_and_whose_feet_they_are() -> void:
	assert_str(FootstepSounds.sound_for(&"asphalt", true)).is_equal("step_own_asphalt")
	assert_str(FootstepSounds.sound_for(&"gravel", true)).is_equal("step_own_gravel")
	assert_str(FootstepSounds.sound_for(&"asphalt", false)).is_equal("step_asphalt")
	assert_str(FootstepSounds.sound_for(&"gravel", false)).is_equal("step_gravel")
	for surface in FootSurface.SURFACES:
		for own in [true, false]:
			var def := SoundCatalog.get_def(FootstepSounds.sound_for(surface, own))
			assert_object(def).is_not_null()
			assert_int(def.variants).is_greater_equal(8)


func test_your_own_steps_are_flat_and_from_the_soft_set() -> void:
	var night := await _start()
	NightFixture.run(night, 90, _walk())
	assert_int(_steps.size()).is_greater(2)
	for step in _steps:
		assert_bool(String(step["id"]).begins_with("step_own_")).is_true()
		assert_object(step["at"]).is_null()
	night.queue_free()


func test_a_walk_steps_once_per_stride_of_ground_covered() -> void:
	var night := await _start()
	var body := night.player()
	var from := body.global_position
	NightFixture.run(night, 90, _walk())
	var covered := (
		Vector2(body.global_position.x - from.x, body.global_position.z - from.z).length()
	)
	assert_float(covered).is_greater(3.0)
	assert_int(_steps.size()).is_between(int(covered / STRIDE) - 1, int(covered / STRIDE) + 1)
	night.queue_free()


func test_standing_still_makes_no_steps() -> void:
	var night := await _start()
	NightFixture.run(night, 90)
	assert_int(_steps.size()).is_equal(0)
	night.queue_free()


func test_a_sprint_is_louder_and_a_crouch_quieter_than_a_walk() -> void:
	var night := await _start()
	_start_point = night.player().global_position
	var walked := _mean_db(_steps_of(night, _walk()))
	var sprinted := _mean_db(_steps_of(night, _walk(true)))
	var crouched := _mean_db(_steps_of(night, _walk(false, true)))
	assert_float(sprinted).is_greater(walked + 1.0)
	assert_float(crouched).is_less(walked - 4.0)
	night.queue_free()


func test_no_steps_while_airborne() -> void:
	var night := await _start()
	NightFixture.run(night, 20, _walk())
	NightFixture.run(night, 1, _walk(false, false, true))
	var body := night.player()
	var in_air := 0
	var steps_in_air := 0
	for _i in 40:
		var before := _steps.size()
		NightFixture.run(night, 1, _walk())
		if not body.state.on_floor:
			in_air += 1
			steps_in_air += _steps.size() - before
	assert_int(in_air).is_greater(10)
	assert_int(steps_in_air).is_equal(0)
	night.queue_free()


func test_each_surface_has_its_ground_in_the_lot() -> void:
	var night := await _start()
	var greybox := night.world.greybox
	var yard := greybox.get_node("GeneratorYard/Ground0_0") as CSGBox3D
	var field := greybox.get_node("Field/GroundC1_1") as CSGBox3D
	await get_tree().physics_frame
	var surfaces := FootSurface.new()
	var space := night.get_world_3d().direct_space_state
	var top := Vector3(0.0, yard.size.y * 0.5, 0.0)
	assert_str(surfaces.at(space, yard.global_position + top)).is_equal("gravel")
	top = Vector3(0.0, field.size.y * 0.5, 0.0)
	assert_str(surfaces.at(space, field.global_position + top)).is_equal("asphalt")
	night.queue_free()


func test_other_players_are_heard_where_their_feet_are() -> void:
	var made := _frames_only()
	var state: ClientState = made[0]
	var feet: FootstepSounds = made[1]
	_run_frames(state, OTHER, 4.8, 6.0, 0.0)
	assert_int(_steps.size()).is_between(14, 16)
	for step in _steps:
		assert_str(step["id"]).is_equal("step_asphalt")
		assert_bool(step["at"] is Vector3).is_true()
	assert_int(feet.counts[OTHER]).is_equal(_steps.size())
	feet.queue_free()


func test_other_players_on_gravel_step_on_gravel() -> void:
	var made := _frames_only()
	_run_frames(made[0], OTHER, 4.8, 3.0, 60.0)
	assert_int(_steps.size()).is_greater(3)
	for step in _steps:
		assert_str(step["id"]).is_equal("step_gravel")
	(made[1] as FootstepSounds).queue_free()


func test_a_faster_other_player_steps_faster_and_louder() -> void:
	var made := _frames_only()
	_run_frames(made[0], OTHER, 4.8, 6.0)
	var walk_count := _steps.size()
	var walk_db := _mean_db(_steps.duplicate())
	_steps = []
	_run_frames(made[0], 3, 7.0, 6.0)
	assert_int(_steps.size()).is_greater(walk_count + 3)
	assert_float(_mean_db(_steps.duplicate())).is_greater(walk_db)
	(made[1] as FootstepSounds).queue_free()


func test_a_player_who_leaves_is_forgotten() -> void:
	var made := _frames_only()
	_run_frames(made[0], OTHER, 4.8, 1.0)
	(made[0] as ClientState).apply_events([_frame(200, {})])
	assert_bool((made[1] as FootstepSounds)._strides.is_empty()).is_true()
	(made[1] as FootstepSounds).queue_free()


func test_the_takes_vary_and_never_repeat_back_to_back() -> void:
	var seen := {}
	var last := ""
	Audio.seed_random(21)
	for _i in 60:
		Audio.advance(0.3)
		var player := Audio.play(&"step_own_asphalt") as AudioStreamPlayer
		var path := PcmStream.source(player.stream)
		assert_str(path).is_not_equal(last)
		last = path
		seen[path] = true
	assert_int(seen.size()).is_equal(8)


func test_your_own_steps_hold_two_voices_and_a_crowds_never_take_them() -> void:
	var own := SoundCatalog.get_def(&"step_own_asphalt")
	var crowd := SoundCatalog.get_def(&"step_asphalt")
	assert_str(own.group).is_equal("step_own")
	assert_int(SoundCatalog.group_limits()[own.group]).is_equal(2)
	assert_str(crowd.group).is_equal("step")
	assert_int(own.priority).is_greater(crowd.priority)
	assert_str(own.bus).is_equal("Effects")


func test_walking_in_the_yard_steps_on_gravel() -> void:
	var night := await _start()
	var yard := night.world.greybox.get_node("GeneratorYard/Ground0_0") as CSGBox3D
	night.player().teleport(yard.global_position + YARD_OPEN_GROUND)
	NightFixture.run(night, 5)
	await get_tree().physics_frame
	_steps = []
	NightFixture.run(night, 90, _walk())
	assert_int(_steps.size()).is_greater(2)
	for step in _steps:
		assert_str(step["id"]).is_equal("step_own_gravel")
	night.queue_free()


func test_other_players_close_up_are_held_to_their_own_level() -> void:
	for id in [&"step_asphalt", &"step_gravel"]:
		assert_float(SoundCatalog.get_def(id).near_cap_db).is_equal(0.0)
