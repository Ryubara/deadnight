# The second map's yard (issue #657, docs/research/maps/small-map-audio.md): loops at the backdrop's
# places, heard through the windows of the listener's room (from the window, at the level of the
# way round and the window's boards) and not through the walls, stopping out of reach, and a fence
# rattling now and then where a post stands.
extends GdUnitTestSuite

const GREYBOX := preload("res://world/smallmap/smallmap_greybox.tscn")
const BACKDROP := preload("res://world/smallmap/backdrop.tscn")
const SETTLE_FRAMES := 4
## Inside the start room, facing the first window across the hall.
const START_EAR := Vector3(4.0, 1.6, 10.0)
const WINDOW_1 := Vector3(4.0, 1.55, 14.65)
## South of that window, straight out of it, and due north through the walls.
const OUT_SOUTH := Vector3(4.0, 1.6, 40.0)
const OUT_NORTH := Vector3(4.0, 1.6, -30.0)
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


# --- The yard ---


func test_the_yard_is_loops_at_the_backdrops_places() -> void:
	await _start()
	var yard := _sounds.yard
	assert_int(yard.source_of(&"yard_wind").size()).is_equal(4)
	assert_int(yard.source_of(&"yard_fire").size()).is_equal(2)
	assert_int(yard.source_of(&"yard_wire").size()).is_equal(SmallMapYard.WIRE_POLES)
	assert_int(yard.source_of(&"yard_road").size()).is_equal(1)
	var fires: Array[Vector3] = []
	for path in SmallMapYard.FIRE_NODES:
		fires.append((_backdrop.get_node(path) as Node3D).global_position)
	for source in yard.source_of(&"yard_fire"):
		var flat := source.anchor.global_position * Vector3(1, 0, 1)
		assert_array(fires).contains([flat])
	for source in yard.sources:
		assert_bool((source.player.stream as AudioStreamOggVorbis).loop).is_true()
	# The poles hum where the poles stand: outside the building and not side by side.
	var wires := yard.source_of(&"yard_wire")
	for wire in wires:
		assert_float(wire.anchor.global_position.length()).is_greater(20.0)
	(
		assert_float(wires[0].anchor.global_position.distance_to(wires[1].anchor.global_position))
		. is_greater_equal(SmallMapYard.WIRE_APART)
	)


func test_the_fence_posts_are_read_from_the_backdrops_buffer_not_its_transforms() -> void:
	await _start()
	var posts := _sounds.fence_posts()
	assert_int(posts.size()).is_greater(50)
	var origin := 0
	for post in posts:
		if post.length() < 1.0:
			origin += 1
	assert_int(origin).is_less(2)


func test_a_window_nearer_the_listener_is_not_louder_for_it() -> void:
	await _start(false)
	var unit := 10.0
	var heard: Array[float] = []
	for z in [6.0, 10.0, 13.5]:
		var ear := Vector3(4.0, 1.6, z)
		var way := _sounds.ways.route(ear, OUT_SOUTH, unit)
		assert_str(way.window).is_equal("start_1")
		var gain := 20.0 * log(unit / ear.distance_to(way.at)) / log(10.0) + way.extra_db
		heard.append(gain)
	# Walking 7 m toward the window shortens the way round by 7 m of 33: a little louder, no jump.
	assert_float(heard[2] - heard[0]).is_between(0.0, 3.5)
	assert_float(heard[1] - heard[0]).is_between(0.0, 2.0)


func test_the_yard_is_heard_through_a_boarded_window_from_the_window() -> void:
	await _start(false)
	var way := _sounds.ways.route(START_EAR, OUT_SOUTH, 10.0)
	assert_str(way.window).is_equal("start_1")
	assert_str(way.kind).is_equal("boarded")
	assert_float(way.at.distance_to(WINDOW_1)).is_less(1.0)
	var point: Vector3 = _sounds.ways.window_point(&"start_1")
	var total := START_EAR.distance_to(point) + point.distance_to(OUT_SOUTH)
	# The player's own fall-off at the window is unit / distance: the extra level is the ratio.
	var way_round := 20.0 * log(START_EAR.distance_to(way.at) / total) / log(10.0)
	var t := SmallMapSoundTuning.current()
	assert_float(way.extra_db).is_equal_approx(way_round + t.boarded_db, 0.01)
	assert_float(way.cutoff_hz).is_equal(t.boarded_cutoff_hz)
	# Heard from the window at the engine's `unit / distance`, plus the extra, the yard is as loud as
	# the whole way round (unit / total) less the boards: not 18 dB louder for the window being near.
	var unit := 10.0
	var at_the_window := 20.0 * log(unit / START_EAR.distance_to(way.at)) / log(10.0)
	var whole_way := 20.0 * log(unit / total) / log(10.0)
	assert_float(at_the_window + way.extra_db).is_equal_approx(whole_way + t.boarded_db, 0.01)


func test_a_window_with_no_boards_lets_more_of_the_yard_in() -> void:
	await _start(false)
	var boarded := _sounds.ways.route(START_EAR, OUT_SOUTH, 10.0)
	_tell({"type": &"board_torn", "barricade_id": &"start_1", "boards": 0, "zombie_id": 1})
	var open := _sounds.ways.route(START_EAR, OUT_SOUTH, 10.0)
	var t := SmallMapSoundTuning.current()
	assert_str(open.kind).is_equal("open")
	assert_float(open.extra_db - boarded.extra_db).is_equal_approx(t.open_db - t.boarded_db, 0.01)
	assert_float(open.cutoff_hz).is_greater(boarded.cutoff_hz)
	_tell({"type": &"board_repaired", "barricade_id": &"start_1", "boards": 1, "player_id": 1})
	assert_str(_sounds.ways.route(START_EAR, OUT_SOUTH, 10.0).kind).is_equal("boarded")


func test_the_yard_behind_the_building_comes_through_the_wall() -> void:
	await _start(false)
	var way := _sounds.ways.route(START_EAR, OUT_NORTH, 10.0)
	var t := SmallMapSoundTuning.current()
	assert_str(way.kind).is_equal("wall")
	assert_str(way.window).is_equal("")
	assert_vector(way.at).is_equal(OUT_NORTH)
	assert_float(way.extra_db).is_equal(t.wall_db)
	assert_float(way.cutoff_hz).is_equal(t.wall_cutoff_hz)


func test_outside_nothing_stands_between_the_listener_and_the_yard() -> void:
	await _start(false)
	var way := _sounds.ways.route(OUTSIDE, OUT_NORTH, 10.0)
	assert_str(way.kind).is_equal("outside")
	assert_float(way.extra_db).is_equal(0.0)
	assert_vector(way.at).is_equal(OUT_NORTH)


func test_a_window_is_heard_from_its_own_room_and_floor_only() -> void:
	await _start(false)
	var in_side := _sounds.ways.route(Vector3(0.0, 1.6, -4.0), OUT_SOUTH, 10.0)
	assert_str(in_side.window).is_not_equal("start_1")
	var upstairs := _sounds.ways.route(Vector3(4.0, 5.0, 2.0), OUT_SOUTH, 10.0)
	assert_bool(upstairs.window == &"" or String(upstairs.window).begins_with("upper_")).is_true()


func test_every_yard_loop_follows_the_listener_and_stops_out_of_reach() -> void:
	await _start()
	var yard := _sounds.yard
	_stand(START_EAR)
	var fire := yard.source_of(&"yard_fire")[0]
	assert_bool(fire.player.playing).is_true()
	assert_float(fire.player.volume_db).is_less(fire.def.volume_db + 0.1)
	assert_float(fire.player.global_position.distance_to(fire.way.at)).is_less(0.01)
	_stand(FAR_AWAY)
	for source in yard.sources:
		assert_bool(source.player.playing).override_failure_message(source.id).is_false()
	_stand(OUTSIDE)
	assert_bool(yard.source_of(&"yard_wind")[0].player.playing).is_true()


func test_a_yard_loop_fades_and_never_cuts_when_the_listener_steps_from_the_window() -> void:
	await _start()
	var wind := _sounds.yard.source_of(&"yard_wind")[0]
	_stand(START_EAR)
	var before := wind.player.volume_db
	_ears.global_position = Vector3(14.0, 1.6, 2.0)
	_sounds.advance(0.1)
	var step := absf(wind.player.volume_db - before)
	assert_float(step).is_less_equal(SmallMapSoundTuning.current().slew_db_per_s * 0.1 + 0.001)


func test_a_fence_rattles_now_and_then_where_a_post_stands() -> void:
	await _start()
	_listen()
	var t := SmallMapSoundTuning.current()
	_run(t.rattle_gap_max + 0.5)
	assert_array(_ids()).contains([&"yard_rattle"])
	var heard := _last(&"yard_rattle")
	assert_bool(heard["at"] is Vector3).is_true()
	assert_float(heard["db"]).is_less_equal(0.0)
	_heard.clear()
	_run(t.rattle_gap_max * 3.0)
	assert_int(_ids().size()).is_between(2, 20)


func test_a_fence_out_of_reach_does_not_rattle() -> void:
	await _start()
	_listen()
	_ears.global_position = FAR_AWAY
	_run(SmallMapSoundTuning.current().rattle_gap_max * 3.0)
	assert_array(_ids()).not_contains([&"yard_rattle"])


func test_the_rattles_are_the_same_every_time_for_a_seed() -> void:
	var runs: Array = []
	for _i in 2:
		_heard.clear()
		await _start()
		_listen()
		_run(80.0)
		runs.append(_heard.duplicate(true))
		_sounds.queue_free()
		_greybox.queue_free()
		_backdrop.queue_free()
		await get_tree().process_frame
	assert_array(runs[0]).is_not_empty()
	assert_array(runs[0]).is_equal(runs[1])
