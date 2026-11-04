extends GdUnitTestSuite
## The dead go over a window's sill in a clip of their own (#991): `Climb_Sill` for a body that
## stands, `Crawl_Climb` for one that crawls. The simulation carries the zombie along the lift and
## the clip follows where it is, so its hands and feet meet the sill and the floor at any pace. A
## straight-line window: the wall is the line x = 0 and the way in is +x.

const SILL := ZombieRig.CLIMB_SILL
const WALLS: Array[float] = [0.2, 0.3, 0.56]
const STANDING: Array[StringName] = [
	&"walker", &"greaser", &"usher", &"farmhand", &"runner", &"brute"
]
const MAPS: Array[String] = [
	"res://world/drive_in_greybox.tscn", "res://world/smallmap/smallmap_greybox.tscn"
]
## The opening's top on the lower of the two maps' windows.
const LINTEL := 2.2
## Metres a foot may be in the wall's top (a boot's sole on the sill, a brute's bigger foot).
const FOOT_SLACK := 0.03
## How near the sill or the floor the lowest foot comes where it stands on them, metres.
const CONTACT := 0.14
## Steps along the way.
const STEPS := 90


func _gate(thick: float, inward := Vector3.RIGHT) -> ZombieGate:
	return ZombieGate.new(&"win", Vector3.ZERO, inward, 2.05, SILL, thick, 2.0)


func _view(look: StringName = &"walker") -> ZombieView:
	var view := ZombieView.new()
	add_child(auto_free(view))
	view.setup(ZombieModels.scene(look), 1, 0.25, 0.7, look)
	return view


func _entry(at: Vector3, climbing := true, yaw := PI * 0.5) -> Dictionary:
	return {
		"id": 1,
		"position": at,
		"yaw": yaw,
		"mode": ZombieBody.Mode.CHASE,
		"episode": 1,
		"speed": 1.2,
		"climbing": climbing,
	}


## `point`'s place on the way: x along the depth and the height the simulation has it at.
func _on_way(gate: ZombieGate, depth: float) -> Vector3:
	var at := gate.inward * depth
	return at + Vector3.UP * gate.lift_at(at)


## The state and the clip's time the tree is in now.
func _playhead(view: ZombieView) -> float:
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	return playback.get_current_play_position()


func _bone(view: ZombieView, name: String) -> Vector3:
	var skeleton := view.model().find_child("Skeleton3D", true, false) as Skeleton3D
	return (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
	)


## Walks a view through a window and calls `look_at` with the depth at every step.
func _cross(view: ZombieView, gate: ZombieGate, way: float, look_at: Callable) -> void:
	view.climb_gate = gate
	var reach := gate.thickness * 0.5 + ZombieGate.BODY_CLEARANCE + ZombieGate.CLIMB_RAMP
	var yaw := atan2(gate.inward.x * way, gate.inward.z * way)
	for i in STEPS + 1:
		var depth := lerpf(-reach, reach, float(i) / STEPS) * way
		var at := _on_way(gate, depth)
		view.apply(_entry(at, gate.lift_at(at) >= 0.1, yaw), 1.0 / 60.0)
		view.accumulated = 1.0 / 60.0
		view.advance_animation()
		look_at.call(depth * way)


# --- What the clip is written for ---


func test_every_window_on_both_maps_has_the_sill_the_clips_are_written_for() -> void:
	for path in MAPS:
		var text := FileAccess.get_file_as_string(path)
		var sills := RegEx.create_from_string("metadata/sill = ([0-9.]+)").search_all(text)
		var walls := RegEx.create_from_string("metadata/thickness = ([0-9.]+)").search_all(text)
		assert_int(sills.size()).is_greater(0)
		for found in sills:
			assert_float(float(found.get_string(1))).is_equal_approx(SILL, 0.001)
		for found in walls:
			assert_float(float(found.get_string(1))).is_less_equal(ZombieRig.CLIMB_WALL)


func test_the_clips_match_their_frames_in_the_files_json() -> void:
	var spec: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/characters/zombies/clips/clips.json")
	)
	for clip: StringName in [ZombieRig.CLIMB_CLIP, ZombieRig.CRAWL_CLIMB_CLIP]:
		var entry: Dictionary = spec["clips"][clip]
		assert_bool(entry["loop"]).is_false()
		assert_float(float(entry["frames"])).is_equal(ZombieRig.CLIMB_FRAMES)
		assert_float(float(entry["events"]["over"])).is_equal(ZombieRig.CLIMB_RISE)
		assert_float(float(entry["events"]["down"])).is_equal(ZombieRig.CLIMB_OVER)


func test_the_clip_starts_ends_and_turns_where_the_lift_does_on_every_wall() -> void:
	var fps := ZombieRig.CLIMB_FPS
	for thick in WALLS:
		var gate := _gate(thick)
		var held := thick * 0.5 + ZombieGate.BODY_CLEARANCE
		var far := held + ZombieGate.CLIMB_RAMP
		for way: float in [1.0, -1.0]:
			var at := func(depth: float) -> float:
				return ZombieRig.climb_time(gate, gate.inward * depth * way, way) * fps
			assert_float(at.call(-far)).is_equal_approx(0.0, 0.001)
			assert_float(at.call(-held)).is_equal_approx(ZombieRig.CLIMB_RISE, 0.001)
			assert_float(at.call(0.0)).is_equal_approx(22.0, 0.001)
			assert_float(at.call(held)).is_equal_approx(ZombieRig.CLIMB_OVER, 0.001)
			assert_float(at.call(far)).is_equal_approx(ZombieRig.CLIMB_FRAMES, 0.001)


# --- The view plays it ---


func test_the_view_plays_the_climb_on_the_bit_and_blends_back_to_the_gait() -> void:
	var view := _view()
	var gate := _gate(0.56)
	view.climb_gate = gate
	var playback: AnimationNodeStateMachinePlayback = view.tree.get(ZombieRig.PLAYBACK_PARAMETER)
	view.apply(_entry(_on_way(gate, -2.0), false), 0.016)
	view.accumulated = 0.016
	view.advance_animation()
	assert_str(playback.get_current_node()).is_equal(ZombieRig.STATE_MOVE)
	view.apply(_entry(_on_way(gate, -0.9)), 0.016)
	view.accumulated = 0.3
	view.advance_animation()
	assert_bool(view.is_climbing()).is_true()
	assert_str(playback.get_current_node()).is_equal(ZombieRig.STATE_CLIMB)
	view.apply(_entry(_on_way(gate, 2.0), false), 0.3)
	view.accumulated = 0.3
	view.advance_animation()
	assert_bool(view.is_climbing()).is_false()
	assert_str(playback.get_current_node()).is_equal(ZombieRig.STATE_MOVE)


func test_the_clip_is_where_the_zombie_is_at_any_pace_and_stands_when_it_stands() -> void:
	var gate := _gate(0.56)
	var view := _view()
	view.climb_gate = gate
	view.apply(_entry(_on_way(gate, -0.9)), 0.016)
	view.accumulated = 0.3
	view.advance_animation()
	for depth: float in [-0.5, 0.0, 0.3]:
		var at := _on_way(gate, depth)
		view.apply(_entry(at), 0.016)
		view.accumulated = 0.016
		view.advance_animation()
		assert_float(_playhead(view)).is_equal_approx(ZombieRig.climb_time(gate, at), 0.001)
	var held := _playhead(view)
	view.accumulated = 0.5
	view.advance_animation()
	assert_float(_playhead(view)).is_equal_approx(held, 0.001)


func test_a_body_turns_square_to_the_window_and_back() -> void:
	var gate := _gate(0.56)
	var view := _view()
	view.climb_gate = gate
	# Coming at the window a little askew: its body is turned to face the wall squarely.
	var askew := PI * 0.5 + 0.4
	for i in 30:
		view.apply(_entry(_on_way(gate, -0.8), true, askew), 0.033)
	assert_float(view.rotation.y + view.model().rotation.y).is_equal_approx(PI * 0.5, 0.01)
	for i in 30:
		view.apply(_entry(_on_way(gate, 1.5), false, askew), 0.033)
	assert_float(view.model().rotation.y).is_equal(0.0)


func test_the_crawler_climbs_in_its_own_clip_and_the_headliner_keeps_walking() -> void:
	var gate := _gate(0.56)
	var crawler := _view(&"crawler")
	crawler.climb_gate = gate
	crawler.apply(_entry(_on_way(gate, -0.8)), 0.016)
	crawler.accumulated = 0.3
	crawler.advance_animation()
	assert_str((crawler.tree.get(ZombieRig.PLAYBACK_PARAMETER)).get_current_node()).is_equal(
		ZombieRig.STATE_CRAWL_CLIMB
	)
	var boss := _view(&"headliner")
	boss.climb_gate = gate
	boss.apply(_entry(_on_way(gate, -0.8)), 0.016)
	assert_bool(boss.is_climbing()).is_false()


func test_a_flinch_on_the_sill_stays_in_the_climb_and_a_fall_leaves_it() -> void:
	var gate := _gate(0.56)
	var view := _view()
	view.climb_gate = gate
	var entry := _entry(_on_way(gate, 0.0))
	view.apply(entry, 0.016)
	entry["mode"] = ZombieBody.Mode.STAGGER
	entry["episode"] = 2
	view.apply(entry, 0.016)
	assert_bool(view.is_climbing()).is_true()
	entry["mode"] = ZombieBody.Mode.DYING
	view.apply(entry, 0.016)
	assert_bool(view.is_climbing()).is_false()


func test_the_horde_finds_the_window_from_the_snapshot() -> void:
	var horde: ZombieHorde = auto_free(ZombieHorde.new())
	add_child(horde)
	horde.setup_client(null, 0.7)
	var gate := _gate(0.56)
	horde.gates = [gate]
	var body := ZombieBody.new()
	body.id = 7
	body.position = _on_way(gate, -0.2)
	body.climbing = true
	body.enter(ZombieBody.Mode.CHASE)
	var zombies: Dictionary[int, ZombieBody] = {7: body}
	horde.apply_snapshot(ZombieCodec.encode(zombies), 0.033)
	assert_object(horde.view_of(7).climb_gate).is_same(gate)
	assert_bool(horde.view_of(7).is_climbing()).is_true()
	body.climbing = false
	body.position = Vector3(5.0, 0.0, 0.0)
	horde.apply_snapshot(ZombieCodec.encode(zombies), 0.033)
	assert_object(horde.view_of(7).climb_gate).is_null()


# --- Its feet stay out of the sill ---


func test_no_foot_goes_into_the_sill_on_any_wall_either_way_in_any_body() -> void:
	var looks: Array[StringName] = STANDING.duplicate()
	looks.append(&"crawler")
	for look in looks:
		for thick in WALLS:
			for way: float in [1.0, -1.0]:
				var view := _view(look)
				var gate := _gate(thick)
				var check := func(_depth: float) -> void:
					for foot: String in ["Foot.L", "Foot.R"]:
						var at := _bone(view, foot)
						if absf(at.x) < thick * 0.5:
							(
								assert_float(at.y)
								. override_failure_message(
									"%s %.2f %s in the wall at %s" % [look, thick, foot, at]
								)
								. is_greater(SILL - FOOT_SLACK)
							)
				_cross(view, gate, way, check)


func test_a_walkers_feet_meet_the_sill_and_the_floor() -> void:
	var view := _view()
	var gate := _gate(0.56)
	# In a dictionary: a lambda keeps its own copy of a plain number.
	var near := {"sill": INF, "floor": INF}
	var check := func(depth: float) -> void:
		var low := minf(_bone(view, "Foot.L").y, _bone(view, "Foot.R").y)
		if absf(depth) < 0.2:
			near["sill"] = minf(near["sill"], absf(low - SILL))
		if depth > 0.9:
			near["floor"] = minf(near["floor"], absf(low))
	_cross(view, gate, 1.0, check)
	assert_float(near["sill"]).is_less(CONTACT)
	assert_float(near["floor"]).is_less(CONTACT)


func test_the_head_goes_under_the_lintel() -> void:
	for look: StringName in [&"walker", &"brute", &"crawler"]:
		var view := _view(look)
		var gate := _gate(0.56)
		var top := {"head": 0.0}
		var check := func(_depth: float) -> void:
			var head := _bone(view, "Head")
			if absf(head.x) < 0.28:
				top["head"] = maxf(top["head"], head.y)
		_cross(view, gate, 1.0, check)
		# The bone is at the jaw: the head stands this much over it, in a walker's kit metres.
		var crown := 0.55 * ZombieModels.GAME_SCALE * ZombieModels.height_of(look)
		assert_float(top["head"] + crown).is_less(LINTEL)
