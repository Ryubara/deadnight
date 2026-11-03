class_name SmallMapSounds
extends Node3D
## What the second map sounds like, made only from what the server sent and where the listener
## stands (the map's `NightSounds`, which it is added beside: the guns, the dead, the till and the
## feet stay the night's). Indoors, a room tone under everything and the wind under the roof
## upstairs, each following the room the listener is in; outside, the cold yard heard through the
## windows (`SmallMapYard`, `SmallMapWays`) and a fence rattling now and then; and the map's pieces:
## the dead tearing the boards off a window and the player putting them back, a plank door opening
## and a debris blocker coming off its stair. It holds no game state and asks the server nothing.
## The design is `docs/research/maps/small-map-audio.md`.

const ROOM_TONE := &"bed_room_tone"
const ROOF_WIND := &"bed_roof_wind"
const RATTLE := &"yard_rattle"
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
			Audio.set_bed_level(ROOF_WIND, _t.roof_db.get(room, SmallMapSoundTuning.SILENT_DB))
	yard.update(ear, delta)


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
