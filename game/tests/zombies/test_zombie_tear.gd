extends GdUnitTestSuite
## The dead pulling boards off, as a client draws it: the snapshot's tearing flag puts a zombie in
## the tear clip, and the clip's yank lands on the rules' tear (Deadnight #221). Every step is
## taken by hand: nothing here reads the clock.

const GATE := &"nw"
const TARGETS := {1: Vector3(20.0, 0.0, 0.0)}
## One server step of the clip, scaled to a brute's pace (the fastest tearer, 2.5x): the most the
## playhead can be off by when a tear lands between two steps.
const SLACK := ZombieSim.STEP * 2.5 * 1.5

var _barricades: BarricadeState


func before_test() -> void:
	_barricades = BarricadeState.new(BarricadeTuning.new())
	_barricades.boards[GATE] = 5


func _view(board_seconds: float = 1.2) -> ZombieView:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(), 1, 0.0, 0.7, ZombieModels.DEFAULT, 1.0, board_seconds)
	return view


func _entry(mode: int, tearing: bool, episode: int = 1) -> Dictionary:
	return {
		"id": 1,
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"mode": mode,
		"episode": episode,
		"speed": 0.0,
		"tearing": tearing,
	}


func _state(view: ZombieView) -> StringName:
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	return playback.get_current_node()


func _advance(view: ZombieView, seconds: float) -> void:
	view.accumulated += seconds
	view.advance_animation()


func test_the_tear_clip_is_in_the_shared_library_and_loops() -> void:
	var view := _view()
	var player := view.model().find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip := player.get_animation("%s/%s" % [ZombieRig.LIBRARY, ZombieRig.TEAR_CLIP])
	assert_object(clip).is_not_null()
	assert_int(clip.loop_mode).is_equal(Animation.LOOP_LINEAR)
	assert_float(clip.length).is_equal_approx(ZombieRig.TEAR_SECONDS, 0.01)


func test_the_clip_constants_match_the_built_file() -> void:
	var spec: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/characters/zombies/clips/clips.json")
	)
	var tear: Dictionary = spec["clips"][String(ZombieRig.TEAR_CLIP)]
	var fps: float = spec["fps"]
	assert_float(tear["events"]["yank"] / fps).is_equal_approx(ZombieRig.TEAR_YANK_SECONDS, 0.001)
	assert_float(tear["frames"] / fps).is_equal_approx(ZombieRig.TEAR_SECONDS, 0.001)


func test_every_track_of_the_tear_clip_finds_its_bone() -> void:
	var view := _view()
	var player := view.model().find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip := player.get_animation("%s/%s" % [ZombieRig.LIBRARY, ZombieRig.TEAR_CLIP])
	var root := player.get_node(player.root_node)
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		var skeleton := root.get_node_or_null(NodePath(path.get_concatenated_names()))
		assert_object(skeleton).is_instanceof(Skeleton3D)
		var bone := (skeleton as Skeleton3D).find_bone(path.get_concatenated_subnames())
		assert_int(bone).override_failure_message("no bone for %s" % path).is_not_equal(-1)


func test_the_flag_picks_the_tear_state_and_new_swings_do_not_restart_it() -> void:
	var view := _view()
	view.apply(_entry(ZombieBody.Mode.CHASE, false), 0.05)
	_advance(view, 0.05)
	view.apply(_entry(ZombieBody.Mode.ATTACK, true, 2), 0.05)
	_advance(view, 0.5)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_TEAR)
	var at := view.tear_position()
	assert_float(at).is_greater(0.2)
	view.apply(_entry(ZombieBody.Mode.ATTACK, true, 3), 0.05)  # the sim's next swing
	_advance(view, 0.05)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_TEAR)
	assert_float(view.tear_position()).is_greater(at)
	view.apply(_entry(ZombieBody.Mode.ATTACK, false, 3), 0.05)  # through, or the boards are gone
	_advance(view, 0.05)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_ATTACK)


func test_a_stagger_at_the_boards_plays_the_stagger() -> void:
	var view := _view()
	view.apply(_entry(ZombieBody.Mode.ATTACK, true), 0.05)
	_advance(view, 0.3)
	view.apply(_entry(ZombieBody.Mode.STAGGER, false, 2), 0.05)
	_advance(view, 0.05)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_STAGGER)


func test_tore_is_ignored_when_not_tearing() -> void:
	var view := _view()
	view.apply(_entry(ZombieBody.Mode.ATTACK, false), 0.05)
	view.tore()
	_advance(view, 0.05)
	assert_str(_state(view)).is_equal(ZombieRig.STATE_ATTACK)


## The whole chain: the simulation's tears, its snapshots through the wire format, and the view.
## At every tear the clip is at its yank, for a walker and for a brute.
func test_the_yank_lands_on_every_tear_of_the_rules() -> void:
	for speed: float in [1.0, 2.5]:
		var sim := ZombieFixture.sim()
		sim.gates[GATE] = ZombieGate.new(GATE, Vector3.ZERO, Vector3.RIGHT)
		sim.barricades = _barricades
		sim.board_seconds = 1.2
		var profile := ZombieProfile.plain(sim.tuning)
		profile.barrier_speed = speed
		sim.spawn(1, 2.0, Vector3(-3.0, 0.0, 0.0), 0.0, profile, GATE).enter(ZombieBody.Mode.CHASE)
		var view := _view(1.2 / speed)
		var tears := 0
		for _step in roundi(6.0 / ZombieSim.STEP):
			var events := sim.tick(ZombieSim.STEP, TARGETS)
			for entry in ZombieCodec.decode(ZombieCodec.encode(sim.zombies)):
				view.apply(entry, ZombieSim.STEP)
			_advance(view, ZombieSim.STEP)
			for event in events:
				if event["type"] != &"zombie_tore":
					continue
				tears += 1
				assert_str(_state(view)).is_equal(ZombieRig.STATE_TEAR)
				(
					assert_float(view.tear_position())
					. override_failure_message(
						(
							"speed %s tear %d at %.3f s of the clip"
							% [speed, tears, view.tear_position()]
						)
					)
					. is_between(
						ZombieRig.TEAR_YANK_SECONDS - SLACK, ZombieRig.TEAR_YANK_SECONDS + SLACK
					)
				)
				view.tore()
		assert_int(tears).is_greater(3)


func test_the_wire_carries_the_flag_beside_the_mode() -> void:
	var sim := ZombieFixture.sim()
	var zombie := sim.spawn(7, 2.0, Vector3.ZERO, 0.0, ZombieProfile.plain(sim.tuning))
	zombie.enter(ZombieBody.Mode.ATTACK)
	zombie.tearing = true
	var entry: Dictionary = ZombieCodec.decode(ZombieCodec.encode(sim.zombies))[0]
	assert_int(entry["mode"]).is_equal(ZombieBody.Mode.ATTACK)
	assert_bool(entry["tearing"]).is_true()
	zombie.tearing = false
	entry = ZombieCodec.decode(ZombieCodec.encode(sim.zombies))[0]
	assert_bool(entry["tearing"]).is_false()
	assert_dict(entry).contains_keys(zombie.view_entry().keys())
