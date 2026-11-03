class_name SmallMapSounds
extends Node3D
## What the second map sounds like, made only from what the server sent and where the listener
## stands (the map's `NightSounds`, which it is added beside: the guns, the dead, the till and the
## feet stay the night's). Indoors, a room tone under everything and the wind under the roof
## upstairs, each following the room the listener is in; outside, the cold yard heard through the
## windows (`SmallMapYard`, `SmallMapWays`) and a fence rattling now and then; and the map's pieces:
## the dead tearing the boards off a window and the player putting them back, a plank door opening
## and a debris blocker coming off its stair. The wind under the roof and the yard's four wind
## loops swell with the gust that is blowing (`wind`, the night's `WindSounds`: its `swell()`, read
## ten times a second), so the located wind follows the same gusts as the open-air layer. It holds
## no game state and asks the server nothing.
## The design is `docs/research/maps/small-map-audio.md`.

const ROOM_TONE := &"bed_room_tone"
const ROOF_WIND := &"bed_roof_wind"
const RATTLE := &"yard_rattle"
## The roof wind is told a new level only when it moves this far (dB).
const ROOF_STEP_DB := 0.05
## The backdrop's fences (multimeshes): the runs of wire and the posts that hold them.
const FENCE_NODES: Array[String] = ["Yard/WireFence", "Yard/FencePosts"]
## The doors that are a pile of rubble and furniture on a stair, not a plank door.
const DEBRIS_DOORS: Array[StringName] = [&"door_stairs_start", &"door_stairs_side"]
## What a purchase of each of those plays besides the till: nothing (no padlock on a pile; the
## sound is the pile coming off, when `door_opened` says). `WorldSounds.item_sounds` takes it.
const ITEM_SOUNDS := {&"door_stairs_start": [], &"door_stairs_side": []}

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test
## listens instead.
var play := Callable()
var schedule := SoundSchedule.new()
var rooms: SmallMapRooms
var ways: SmallMapWays
var yard: SmallMapYard
## The night's wind, whose blowing gust the roof and yard wind swell with (`NightSounds.wind`; set
## by whoever adds this beside `NightSounds`). None: they stay as they rest.
var wind: WindSounds
## The node name of the room the listener is in now (`Start`, `Side`, `UpperA`, `UpperB`), `&""`
## outside.
var room := &""

var _t := SmallMapSoundTuning.current()
var _state: ClientState
var _door_points: Dictionary[StringName, Vector3] = {}
var _posts: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _since_update := 0.0
var _over := false
var _started := false
var _roof_level := SmallMapSoundTuning.SILENT_DB


## `greybox` is the map (`smallmap_greybox.tscn`), `backdrop` its outside (null for none).
func setup(state: ClientState, greybox: Node3D, backdrop: Node3D = null, seed_value := 657) -> void:
	_state = state
	_rng.seed = seed_value
	rooms = SmallMapRooms.new(greybox)
	ways = SmallMapWays.new(greybox, rooms, _t)
	yard = SmallMapYard.new()
	yard.name = "Yard"
	add_child(yard)
	yard.setup(ways, _t, backdrop)
	_read_doors(greybox)
	_read_posts(backdrop)
	Audio.start_bed(ROOM_TONE, true)
	Audio.start_bed(ROOF_WIND, true)
	state.event_received.connect(_on_event)
	_schedule_rattle()


func _exit_tree() -> void:
	Audio.stop_bed(ROOM_TONE)
	Audio.stop_bed(ROOF_WIND)
	if yard == null:
		return
	for source in yard.sources:
		if source.player != null:
			source.player.stop()


func _process(delta: float) -> void:
	advance(delta)


## Moves the clock: the rooms and the yard follow the listener, and a fence rattles when it is due.
func advance(delta: float) -> void:
	schedule.advance(delta)
	_since_update += delta
	if not _started or _since_update >= 1.0 / _t.update_hz:
		_follow(_since_update)
		_since_update = 0.0
		_started = true


## The fence posts a fence can rattle at, in the world.
func fence_posts() -> Array[Vector3]:
	return _posts


func _follow(delta: float) -> void:
	var ear := Audio.listener_position()
	var now := rooms.room_at(ear)
	if now != room or not _started:
		room = now
		if not _over:
			Audio.set_bed_level(ROOM_TONE, _t.tone_db.get(room, SmallMapSoundTuning.SILENT_DB))
	var swell := gust_swell()
	if not _over:
		_set_roof_wind(swell)
	yard.update(ear, delta, _t.yard_gust_db * swell)


## How far into its swell the blowing gust is, 0 (none, no wind, or at its ends) to 1 (its peak).
func gust_swell() -> float:
	if wind == null or not wind.is_running():
		return 0.0
	return wind.swell()


## The wind under the roof, in the listener's room: where it rests (the room's level, this far
## under the loop's raised trim) and up to `roof_gust_db` over that at the gust's peak. A room
## with none is silent. The bed is only told when its level moves.
func _set_roof_wind(swell: float) -> void:
	var rests: float = _t.roof_db.get(room, SmallMapSoundTuning.SILENT_DB)
	var level := SmallMapSoundTuning.SILENT_DB
	if rests > SmallMapSoundTuning.SILENT_DB + 0.5:
		level = rests - SmallMapSoundTuning.ROOF_HEADROOM_DB + _t.roof_gust_db * swell
	if not _started or absf(level - _roof_level) >= ROOF_STEP_DB:
		_roof_level = level
		Audio.set_bed_level(ROOF_WIND, level)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"board_torn":
			var window_id := StringName(event["barricade_id"])
			ways.set_boards(window_id, int(event["boards"]))
			_at_window(&"board_last" if event["boards"] == 0 else &"board_tear", window_id)
		&"board_repaired":
			var window_id := StringName(event["barricade_id"])
			ways.set_boards(window_id, int(event["boards"]))
			_at_window(&"board_repair", window_id)
		&"door_opened":
			var door_id := StringName(event["door_id"])
			if _door_points.has(door_id):
				_play(
					&"debris_clear" if door_id in DEBRIS_DOORS else &"door_open",
					_door_points[door_id]
				)
		&"game_over":
			_over = true
			Audio.stop_bed(ROOM_TONE)
			Audio.stop_bed(ROOF_WIND)
			yard.finish()


## A window's sound: where its boards are, the middle of the opening.
func _at_window(sound: StringName, window_id: StringName) -> void:
	var point: Variant = ways.window_point(window_id)
	if point is Vector3:
		_play(sound, point)


## A fence rattles at a post in reach, then again after a gap.
func _rattle() -> void:
	var ear := Audio.listener_position()
	var def := SoundCatalog.get_def(RATTLE)
	var near: Array[Vector3] = []
	for post in _posts:
		if post.distance_to(ear) <= minf(_t.rattle_reach, def.max_distance):
			near.append(post)
	if not near.is_empty():
		var post: Vector3 = near[_rng.randi() % near.size()]
		var way := ways.route(ear, post, def.unit_size)
		var extra := way.extra_db
		if not Audio.filters_apply and way.kind != &"outside":
			extra += _t.no_filter_db
		_play(RATTLE, way.at, extra)
	_schedule_rattle()


func _schedule_rattle() -> void:
	schedule.add(_rng.randf_range(_t.rattle_gap_min, _t.rattle_gap_max), _rattle, &"rattle")


func _play(sound: StringName, at: Variant, extra_db := 0.0) -> void:
	if play.is_valid():
		play.call(sound, at, extra_db)
	else:
		Audio.play(sound, at, extra_db)


## Where each purchase door's slab stands, read now: a bought door's slabs are taken away.
func _read_doors(greybox: Node3D) -> void:
	var doors := greybox.get_node_or_null("Doors")
	if doors == null:
		return
	for door in doors.get_children():
		for part in door.get_children():
			if part is CSGShape3D and (part as CSGShape3D).use_collision:
				_door_points[StringName(door.get_meta(&"shop_id"))] = (
					(part as Node3D).global_position
				)
				break


## What a fence can rattle at in the backdrop, in the world: each run of wire fence and each post.
func _read_posts(backdrop: Node3D) -> void:
	if backdrop == null:
		return
	for path in FENCE_NODES:
		var fence := backdrop.get_node_or_null(path) as MultiMeshInstance3D
		if fence == null:
			continue
		for at in SmallMapYard.copies_of(fence):
			_posts.append(at + Vector3.UP)
